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
    private let logger: Logger
    private let decoder: JSONDecoder

    private var cachedLists: [TaskList]?
    private var cachedTasks: [String: [TaskItem]] = [:]

    public init(
        authorizing: TasksAuthorizing,
        http: TasksHTTPClient = URLSessionTasksHTTPClient()
    ) {
        self.authorizing = authorizing
        self.http = http
        self.logger = Logger(subsystem: "fr.andreadelre.LifeView", category: "GoogleTasksClient")
        self.decoder = Self.makeDecoder()
    }

    // MARK: - Public API

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
    public func fetchTasks(in listID: String, forceReload: Bool = false) async throws -> [TaskItem] {
        if !forceReload, let cached = cachedTasks[listID] {
            return cached
        }

        let raw = try await fetchAllPages(
            description: "tasks",
            urlForToken: { GoogleTasksEndpoints.tasks(in: listID, pageToken: $0) },
            page: RemoteTaskPage.self,
            items: \.items,
            nextToken: \.nextPageToken
        )
        let mapped = raw.compactMap { $0.toDomain() }
            .sorted { $0.position < $1.position }
        cachedTasks[listID] = mapped
        logger.debug("Fetched \(mapped.count, privacy: .public) task(s) for list")
        return mapped
    }

    /// Drops all cached data. Called on sign-out and account switch (P4).
    public func invalidateCache() {
        cachedLists = nil
        cachedTasks.removeAll()
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
        let (data, response) = try await performAuthorizedRequest(url: url)

        guard (200..<300).contains(response.statusCode) else {
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

    private func performAuthorizedRequest(url: URL) async throws -> (Data, HTTPURLResponse) {
        let initialToken = try await authorizing.accessToken()
        let request = makeRequest(url: url, bearer: initialToken)

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
        let retryRequest = makeRequest(url: url, bearer: refreshedToken)
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

    private func makeRequest(url: URL, bearer: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Decoder

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
}
