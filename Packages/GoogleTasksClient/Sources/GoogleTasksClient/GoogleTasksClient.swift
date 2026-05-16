import Core
import Foundation
import os

/// Async/await client for the Google Tasks REST v1 API.
///
/// Architecturally the package owns three concerns:
///
/// 1. **Authorization** — fetches an access token from a ``TasksAuthorizing``
///    seam, retries once with a forcibly-refreshed token on `401`.
/// 2. **Transport + decoding** — wraps `URLSession`, follows pagination,
///    decodes wire DTOs, maps to domain models from `Core`.
/// 3. **Memory cache** — per-account-session in-memory cache; invalidated
///    by passing `forceReload: true` (which the view-model wires to
///    pull-to-refresh).
///
/// The client is an actor because the cache is shared mutable state and
/// view-model refreshes can race with user-driven list switches. Public
/// methods serialise on the actor; the underlying network calls suspend
/// without holding the actor — so a slow request does not block other
/// readers from hitting the cache.
public actor GoogleTasksClient {
    private let authorizing: TasksAuthorizing
    private let http: TasksHTTPClient
    let logger: Logger
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var cachedLists: [TaskList]?
    /// Keyed by ``TasksCacheKey`` so the panel can flip the
    /// "show completed" toggle without invalidating the cached
    /// "needsAction-only" view (and vice-versa).
    private var cachedTasks: [TasksCacheKey: [TaskItem]] = [:]

    private struct TasksCacheKey: Hashable {
        let listID: String
        let showCompleted: Bool
    }

    public init(
        authorizing: TasksAuthorizing,
        http: TasksHTTPClient = URLSessionTasksHTTPClient()
    ) {
        self.authorizing = authorizing
        self.http = http
        logger = Logger(subsystem: "fr.andreadelre.LifeView", category: "GoogleTasksClient")
        decoder = Self.makeDecoder()
        encoder = Self.makeEncoder()
    }

    // MARK: - Public API — Read

    /// Returns all task lists for the signed-in account.
    ///
    /// Uses the in-memory cache when available. Pass `forceReload: true`
    /// (typically from `.refreshable`) to bypass and re-fetch from Google.
    public func fetchTaskLists(forceReload: Bool = false) async throws -> [TaskList] {
        if !forceReload, let cached = cachedLists {
            return cached
        }

        let raw = try await fetchAllPages(
            description: "tasklists",
            urlForToken: { GoogleTasksEndpoints.taskLists(pageToken: $0) },
            page: RemoteTaskListPage.self,
            items: \.items,
            nextToken: \.nextPageToken
        )
        let mapped = raw.map { $0.toDomain() }
        cachedLists = mapped
        logger.debug("Fetched \(mapped.count, privacy: .public) task list(s)")
        return mapped
    }

    /// Returns the tasks of one list, sorted by `position` (Google's
    /// canonical lexicographic ordering).
    ///
    /// `showCompleted` toggles the inclusion of `completed` (and
    /// `hidden`) tasks. Both states are cached independently so a user
    /// flipping the panel toggle back and forth doesn't re-hit Google
    /// every time.
    public func fetchTasks(
        in listID: String,
        showCompleted: Bool = false,
        forceReload: Bool = false
    ) async throws -> [TaskItem] {
        let cacheKey = TasksCacheKey(listID: listID, showCompleted: showCompleted)
        if !forceReload, let cached = cachedTasks[cacheKey] {
            return cached
        }

        let raw = try await fetchAllPages(
            description: "tasks",
            urlForToken: { GoogleTasksEndpoints.tasks(in: listID, pageToken: $0, showCompleted: showCompleted) },
            page: RemoteTaskPage.self,
            items: \.items,
            nextToken: \.nextPageToken
        )
        // Hierarchical sort: top-level tasks in position order, each
        // followed by its sub-tasks in their own position order.
        // ``TaskItem/position`` is scoped to siblings, so a flat sort
        // would interleave children of different parents.
        let mapped = TaskItem.hierarchicallySorted(raw.compactMap { $0.toDomain() })
        cachedTasks[cacheKey] = mapped
        logger.debug("Fetched \(mapped.count, privacy: .public) task(s) for list")
        return mapped
    }

    /// Returns cached tasks for `(listID, showCompleted)` without
    /// triggering a fetch. Used by the view-model to avoid flashing a
    /// loading spinner on a switch that's actually instant.
    public func cachedTasks(for listID: String, showCompleted: Bool) -> [TaskItem]? {
        cachedTasks[TasksCacheKey(listID: listID, showCompleted: showCompleted)]
    }

    /// Drops all cached data. Called on sign-out and account switch (P4).
    public func invalidateCache() {
        cachedLists = nil
        cachedTasks.removeAll()
    }

    // MARK: - Public API — Write (P5)

    /// Creates a new task in `listID`. Returns the server's canonical
    /// representation (with the server-assigned `id` and `position`).
    ///
    /// On success, the client surgically appends the task to every
    /// cached `(listID, *)` entry where the new task would be visible —
    /// a freshly-inserted task is always `needsAction`, so it appears
    /// in both `showCompleted=false` and `showCompleted=true` views.
    @discardableResult
    public func insertTask(in listID: String, draft: TaskDraft) async throws -> TaskItem {
        let body = try encoder.encode(RemoteTaskInput(draft: draft))
        let url = GoogleTasksEndpoints.insertTask(in: listID)
        let remote: RemoteTask = try await performMutation(
            description: "POST tasks",
            method: "POST",
            url: url,
            body: body
        )
        guard let inserted = remote.toDomain() else {
            throw GoogleTasksError.decodingFailed
        }
        applyInsertToCache(inserted, listID: listID)
        logger.debug("Inserted task in list")
        return inserted
    }

    /// Applies a partial update. No-ops (empty patch) short-circuit
    /// without hitting the network — Google would reject an empty
    /// PATCH body anyway, and avoiding the call keeps the optimistic-UI
    /// queue cheap.
    @discardableResult
    public func updateTask(
        in listID: String,
        taskID: String,
        patch: TaskPatch
    ) async throws -> TaskItem {
        if patch.isEmpty {
            // Refetch from cache if possible; otherwise fall through to
            // a `GET`-like resolution would be overkill. The view-model
            // never sends empty patches in practice.
            throw GoogleTasksError.emptyPatch
        }
        let body = try encoder.encode(RemoteTaskPatch(patch: patch))
        let url = GoogleTasksEndpoints.updateTask(in: listID, taskID: taskID)
        let remote: RemoteTask = try await performMutation(
            description: "PATCH tasks",
            method: "PATCH",
            url: url,
            body: body
        )
        guard let updated = remote.toDomain() else {
            throw GoogleTasksError.decodingFailed
        }
        applyUpdateToCache(updated, listID: listID)
        logger.debug("Patched task in list")
        return updated
    }

    /// Deletes the task. Surgically removes it from every cached view
    /// of `listID` on success.
    public func deleteTask(in listID: String, taskID: String) async throws {
        let url = GoogleTasksEndpoints.deleteTask(in: listID, taskID: taskID)
        try await performMutationVoid(
            description: "DELETE tasks",
            method: "DELETE",
            url: url,
            body: nil
        )
        applyDeleteToCache(taskID: taskID, listID: listID)
        logger.debug("Deleted task in list")
    }

    /// Creates a new task list. Returns the server's canonical
    /// representation (with the server-assigned `id` and `updatedAt`).
    @discardableResult
    public func insertTaskList(title: String) async throws -> TaskList {
        let body = try encoder.encode(RemoteTaskListInput(title: title))
        let url = GoogleTasksEndpoints.insertTaskList()
        let remote: RemoteTaskList = try await performMutation(
            description: "POST lists",
            method: "POST",
            url: url,
            body: body
        )
        let inserted = remote.toDomain()
        applyInsertToListsCache(inserted)
        logger.debug("Inserted task list")
        return inserted
    }

    /// Renames an existing list. Only `title` is mutable.
    @discardableResult
    public func renameTaskList(listID: String, title: String) async throws -> TaskList {
        let body = try encoder.encode(RemoteTaskListInput(title: title))
        let url = GoogleTasksEndpoints.updateTaskList(listID: listID)
        let remote: RemoteTaskList = try await performMutation(
            description: "PATCH lists",
            method: "PATCH",
            url: url,
            body: body
        )
        let renamed = remote.toDomain()
        applyUpdateToListsCache(renamed)
        logger.debug("Renamed task list")
        return renamed
    }

    /// Deletes a list (and every task it contains — server-side cascade).
    /// Drops cached lists and any cached tasks for this list.
    public func deleteTaskList(listID: String) async throws {
        let url = GoogleTasksEndpoints.deleteTaskList(listID: listID)
        try await performMutationVoid(
            description: "DELETE lists",
            method: "DELETE",
            url: url,
            body: nil
        )
        applyDeleteToListsCache(listID: listID)
        logger.debug("Deleted task list")
    }

    // MARK: - Cache helpers

    private func applyInsertToCache(_ task: TaskItem, listID: String) {
        for key in cachedTasks.keys where key.listID == listID {
            var list = cachedTasks[key] ?? []
            list.removeAll { $0.id == task.id }
            list.append(task)
            list = TaskItem.hierarchicallySorted(list)
            cachedTasks[key] = list
        }
    }

    func applyUpdateToCache(_ task: TaskItem, listID: String) {
        for key in cachedTasks.keys where key.listID == listID {
            var list = cachedTasks[key] ?? []
            list.removeAll { $0.id == task.id }
            // Re-insert only if the task belongs in this view: the
            // `showCompleted=false` cache must not retain a task that
            // just got marked as completed.
            if key.showCompleted || task.status == .needsAction {
                list.append(task)
                list = TaskItem.hierarchicallySorted(list)
            }
            cachedTasks[key] = list
        }
    }

    private func applyDeleteToCache(taskID: String, listID: String) {
        for key in cachedTasks.keys where key.listID == listID {
            cachedTasks[key]?.removeAll { $0.id == taskID }
        }
    }

    private func applyInsertToListsCache(_ list: TaskList) {
        guard var cached = cachedLists else { return }
        cached.removeAll { $0.id == list.id }
        cached.append(list)
        cachedLists = cached
    }

    private func applyUpdateToListsCache(_ list: TaskList) {
        guard var cached = cachedLists else { return }
        if let index = cached.firstIndex(where: { $0.id == list.id }) {
            cached[index] = list
            cachedLists = cached
        }
    }

    private func applyDeleteToListsCache(listID: String) {
        cachedLists?.removeAll { $0.id == listID }
        // Drop every tasks-cache entry for the deleted list — those rows
        // no longer exist server-side after the cascade.
        cachedTasks = cachedTasks.filter { $0.key.listID != listID }
    }

    // MARK: - Pagination

    private func fetchAllPages<Page: Decodable, Item>(
        description: String,
        urlForToken: (String?) -> URL,
        page _: Page.Type,
        items: KeyPath<Page, [Item]?>,
        nextToken: KeyPath<Page, String?>
    ) async throws -> [Item] {
        var aggregated: [Item] = []
        var pageToken: String?

        repeat {
            let url = urlForToken(pageToken)
            let decoded: Page = try await fetch(url: url, as: Page.self)
            if let pageItems = decoded[keyPath: items] {
                aggregated.append(contentsOf: pageItems)
            }
            pageToken = decoded[keyPath: nextToken]
        } while pageToken != nil

        logger.debug("Aggregated \(aggregated.count, privacy: .public) item(s) from \(description, privacy: .public)")
        return aggregated
    }

    // MARK: - HTTP + 401 retry

    private func fetch<T: Decodable>(url: URL, as _: T.Type) async throws -> T {
        let (data, response) = try await performAuthorizedRequest { token in
            self.makeRequest(url: url, bearer: token, method: "GET", body: nil)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            logger.error("HTTP \(response.statusCode, privacy: .public) for \(url.path, privacy: .public)")
            throw GoogleTasksError.http(statusCode: response.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding failed for \(url.path, privacy: .public)")
            throw GoogleTasksError.decodingFailed
        }
    }

    func performMutation<T: Decodable>(
        description: String,
        method: String,
        url: URL,
        body: Data?
    ) async throws -> T {
        let (data, response) = try await performAuthorizedRequest { token in
            self.makeRequest(url: url, bearer: token, method: method, body: body)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            logger.error("HTTP \(response.statusCode, privacy: .public) for \(description, privacy: .public)")
            throw GoogleTasksError.http(statusCode: response.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding failed for \(description, privacy: .public)")
            throw GoogleTasksError.decodingFailed
        }
    }

    private func performMutationVoid(
        description: String,
        method: String,
        url: URL,
        body: Data?
    ) async throws {
        let (_, response) = try await performAuthorizedRequest { token in
            self.makeRequest(url: url, bearer: token, method: method, body: body)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            logger.error("HTTP \(response.statusCode, privacy: .public) for \(description, privacy: .public)")
            throw GoogleTasksError.http(statusCode: response.statusCode)
        }
    }

    private func performAuthorizedRequest(
        buildRequest: (String) -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let initialToken = try await authorizing.accessToken()
        let request = buildRequest(initialToken)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.send(request)
        } catch let error as GoogleTasksError {
            throw error
        } catch {
            throw GoogleTasksError.transport(message: (error as NSError).localizedDescription)
        }

        guard response.statusCode == 401 else {
            return (data, response)
        }

        // 401 path: force a refresh, retry the request once.
        logger.debug("Received 401 — forcing refresh and retrying once")
        let refreshedToken: String
        do {
            refreshedToken = try await authorizing.refreshedAccessToken()
        } catch {
            throw GoogleTasksError.unauthorized
        }
        let retryRequest = buildRequest(refreshedToken)
        let (retryData, retryResponse): (Data, HTTPURLResponse)
        do {
            (retryData, retryResponse) = try await http.send(retryRequest)
        } catch let error as GoogleTasksError {
            throw error
        } catch {
            throw GoogleTasksError.transport(message: (error as NSError).localizedDescription)
        }

        if retryResponse.statusCode == 401 {
            throw GoogleTasksError.unauthorized
        }
        return (retryData, retryResponse)
    }

    private func makeRequest(url: URL, bearer: String, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: - Decoder + Encoder

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Google Tasks emits RFC3339 datetimes — `updated` carries
        // millisecond precision, `due` doesn't. `Date.ISO8601FormatStyle`
        // is `Sendable` (unlike `ISO8601DateFormatter`), so it captures
        // cleanly into the strategy closure under strict concurrency.
        let withFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let withoutFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? withFractional.parse(raw) { return date }
            if let date = try? withoutFractional.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised RFC3339 datetime"
            )
        }
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Symmetric to the decoder: emit RFC3339 with fractional seconds.
        // Google accepts both shapes; this avoids drift if a round-trip
        // re-encodes a previously-decoded date.
        let formatter = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.format(date))
        }
        return encoder
    }
}
