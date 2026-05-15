import Core
import Foundation
import GoogleTasksClient
import Observation

/// Drives the tasks corner of the panel.
///
/// Loading model: at first sign-in we fetch the lists and **all** their
/// tasks concurrently, so list-switching is instant from the in-memory
/// cache afterwards. A periodic background refresh keeps the data warm
/// (Google Tasks has no push channel, so polling is the only option) and
/// the user can also trigger an immediate refresh from the header.
///
/// Lives on the main actor because every transition feeds the SwiftUI
/// view tree directly. The underlying ``GoogleTasksClient`` is an actor,
/// so its calls suspend without blocking the main thread.
@MainActor
@Observable
final class TasksViewModel {
    enum TasksState: Equatable {
        case loading
        case loaded([TaskItem])
        case error(String)
    }

    struct Payload: Equatable {
        var lists: [TaskList]
        var selectedListID: String?
        var tasksState: TasksState
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded(Payload)
        case error(String)
    }

    private(set) var state: State = .idle
    /// `true` while a refresh is in flight — drives the spinner overlay
    /// on the refresh button. The displayed payload is **not** swapped
    /// to `.loading` during a refresh; we keep the stale view until the
    /// new data lands.
    private(set) var isRefreshing: Bool = false
    private(set) var showsCompleted: Bool

    private let client: GoogleTasksClient
    private let preferences: UserDefaults

    /// Identifier of the in-flight tasks fetch for the *selected* list.
    /// Used to drop responses from a previous list when the user
    /// switches faster than the network responds.
    private var currentTasksFetch: UUID?

    /// Long-lived task that re-runs `refresh(silent: true)` on a timer
    /// while the view-model is "live" (between `start()` and `reset()`).
    private var autoRefreshTask: Task<Void, Never>?

    private static let showsCompletedKey = "TasksViewModel.showsCompleted"
    /// Polling cadence. 60 s mirrors what `tasks.google.com` itself does
    /// in the open tab (it polls roughly every minute). Short enough to
    /// feel live, long enough to stay well clear of any quota.
    private static let autoRefreshInterval: Duration = .seconds(60)

    init(client: GoogleTasksClient, preferences: UserDefaults = .standard) {
        self.client = client
        self.preferences = preferences
        self.showsCompleted = preferences.bool(forKey: Self.showsCompletedKey)
    }

    // No `deinit` cancellation: the auto-refresh task captures `weak
    // self`, so once the view-model is gone the loop exits silently on
    // the next tick. ``reset()`` is the explicit cancellation point.

    // MARK: - Lifecycle

    /// Idempotent first-run trigger. Loads task lists and pre-fetches
    /// all their tasks if the view-model is still in `.idle`. Starts the
    /// background polling loop after a successful first load.
    func start() async {
        guard case .idle = state else { return }
        await initialLoad()
        startAutoRefreshIfNeeded()
    }

    /// User-initiated refresh (button + pull-to-refresh). Re-fetches
    /// lists AND tasks for every list, bypassing the cache. Keeps the
    /// currently displayed payload visible until the new data arrives;
    /// surfaces errors via the displayed state.
    func refresh() async {
        await performRefresh(silent: false)
    }

    /// Drops to `.idle` and clears the cache + the polling loop. Called
    /// when the user signs out so a subsequent sign-in starts clean.
    func reset() async {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        state = .idle
        currentTasksFetch = nil
        await client.invalidateCache()
    }

    /// Switches to a different task list. After the initial load every
    /// list is already in the client's cache, so this is effectively
    /// instant — ``loadTasks`` short-circuits on cache hits and never
    /// flashes a loading spinner.
    func selectList(_ listID: String) {
        guard case .loaded(var payload) = state else { return }
        guard payload.selectedListID != listID else { return }
        guard payload.lists.contains(where: { $0.id == listID }) else { return }

        payload.selectedListID = listID
        state = .loaded(payload)
        Task { await loadTasks(for: listID, forceReload: false) }
    }

    /// Toggles the visibility of completed (and Google-hidden) tasks.
    /// Persisted to `UserDefaults`. The cache in ``GoogleTasksClient``
    /// keeps both states independently — toggling back to a previously
    /// loaded state is instant.
    func toggleShowsCompleted() {
        showsCompleted.toggle()
        preferences.set(showsCompleted, forKey: Self.showsCompletedKey)

        guard case .loaded(let payload) = state else { return }

        // Pre-fetch the new state for every list in the background so a
        // future list-switch under the new toggle is also instant.
        let lists = payload.lists
        let snapshot = showsCompleted
        Task { await self.preloadTasks(for: lists, showCompleted: snapshot, forceReload: false) }

        if let listID = payload.selectedListID {
            Task { await loadTasks(for: listID, forceReload: false) }
        }
    }

    // MARK: - Initial load

    private func initialLoad() async {
        state = .loading
        do {
            let lists = try await client.fetchTaskLists(forceReload: false)
            guard !lists.isEmpty else {
                state = .loaded(Payload(lists: [], selectedListID: nil, tasksState: .loaded([])))
                return
            }

            let selection = lists[0].id
            state = .loaded(Payload(
                lists: lists,
                selectedListID: selection,
                tasksState: .loading
            ))

            await preloadTasks(for: lists, showCompleted: showsCompleted, forceReload: false)
            await loadTasks(for: selection, forceReload: false)
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    // MARK: - Refresh

    private func performRefresh(silent: Bool) async {
        guard !isRefreshing else { return }
        guard case .loaded = state else {
            // Refresh requested before the initial load finished — fold
            // into the standard initial-load path.
            await initialLoad()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let preservedSelection = currentlySelectedListID
        do {
            let lists = try await client.fetchTaskLists(forceReload: true)
            guard !lists.isEmpty else {
                state = .loaded(Payload(lists: [], selectedListID: nil, tasksState: .loaded([])))
                return
            }

            let selection: String = {
                if let preservedSelection, lists.contains(where: { $0.id == preservedSelection }) {
                    return preservedSelection
                }
                return lists[0].id
            }()

            await preloadTasks(for: lists, showCompleted: showsCompleted, forceReload: true)

            // Pull the freshly-cached tasks for the selected list.
            let tasks = (try? await client.fetchTasks(
                in: selection,
                showCompleted: showsCompleted,
                forceReload: false
            )) ?? []
            state = .loaded(Payload(lists: lists, selectedListID: selection, tasksState: .loaded(tasks)))
        } catch {
            // Auto-refresh ticks must not wipe the displayed data on a
            // transient blip — log and move on. Manual refresh (button /
            // pull) surfaces the error so the user knows to retry.
            if !silent {
                state = .error(Self.message(for: error))
            }
        }
    }

    // MARK: - Auto-refresh loop

    private func startAutoRefreshIfNeeded() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.autoRefreshInterval)
                } catch {
                    return // task cancelled during sleep
                }
                guard let self else { return }
                await self.performRefresh(silent: true)
            }
        }
    }

    // MARK: - Tasks fetch helpers

    private var currentlySelectedListID: String? {
        if case .loaded(let payload) = state { return payload.selectedListID }
        return nil
    }

    /// Concurrently warm the cache for every list in `lists`. Errors are
    /// swallowed individually — a single list failing must not block the
    /// others nor surface on top of a working selected list.
    private func preloadTasks(for lists: [TaskList], showCompleted: Bool, forceReload: Bool) async {
        let client = self.client
        await withTaskGroup(of: Void.self) { group in
            for list in lists {
                let listID = list.id
                group.addTask {
                    _ = try? await client.fetchTasks(
                        in: listID,
                        showCompleted: showCompleted,
                        forceReload: forceReload
                    )
                }
            }
        }
    }

    private func loadTasks(for listID: String, forceReload: Bool) async {
        // Fast path: cache hit → swap directly, no `.loading` flash.
        if !forceReload, let cached = await client.cachedTasks(for: listID, showCompleted: showsCompleted) {
            guard case .loaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(cached)
            state = .loaded(payload)
            return
        }

        // Slow path: real fetch — show the spinner first.
        if case .loaded(var payload) = state, payload.selectedListID == listID {
            payload.tasksState = .loading
            state = .loaded(payload)
        }

        let fetchID = UUID()
        currentTasksFetch = fetchID

        do {
            let tasks = try await client.fetchTasks(
                in: listID,
                showCompleted: showsCompleted,
                forceReload: forceReload
            )
            guard currentTasksFetch == fetchID else { return }
            guard case .loaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(tasks)
            state = .loaded(payload)
        } catch {
            guard currentTasksFetch == fetchID else { return }
            guard case .loaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .error(Self.message(for: error))
            state = .loaded(payload)
        }
    }

    // MARK: - Helpers

    private static func message(for error: Error) -> String {
        if let tasksError = error as? GoogleTasksError {
            switch tasksError {
            case .unauthorized: return "Session Google expirée. Reconnecte-toi."
            case .http(let status): return "Erreur Google Tasks (HTTP \(status))."
            case .decodingFailed: return "Réponse Google inattendue."
            case .transport(let message): return "Problème réseau : \(message)"
            }
        }
        return (error as NSError).localizedDescription
    }
}
