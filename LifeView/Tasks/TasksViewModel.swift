import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
import Observation

/// Drives the tasks corner of the panel for both display modes.
///
/// Single mode (`.single(AccountID)`) mirrors the P3 behaviour: lists + tasks
/// for one account, with a list picker. Aggregated mode (`.all([AccountID])`)
/// renders every list of every account as one scrollable view, grouped by
/// account.
///
/// The view-model owns no client itself: it asks an
/// ``AccountSessionRegistry`` for the per-account ``GoogleTasksClient``
/// that matches the current selection. That keeps each client (and its
/// in-memory cache) bound to one account — switching back to a
/// previously-loaded account is therefore instant.
@MainActor
@Observable
final class TasksViewModel {
    // MARK: - Public types

    enum Selection: Sendable, Equatable {
        /// No account is currently selected (e.g. user just signed out).
        case none
        /// One specific account.
        case single(AccountID)
        /// Aggregated view of N accounts, in display order.
        case all([AccountID])
    }

    enum TasksState: Equatable {
        case loading
        case loaded([TaskItem])
        case error(String)
    }

    struct SinglePayload: Equatable {
        var account: Account
        var lists: [TaskList]
        var selectedListID: String?
        var tasksState: TasksState
    }

    struct ListSlice: Identifiable, Equatable {
        var list: TaskList
        var tasksState: TasksState
        var id: String { list.id }
    }

    struct AccountSection: Identifiable, Equatable {
        var account: Account
        var slices: [ListSlice]
        var id: AccountID { account.id }
    }

    enum State: Equatable {
        case idle
        case loading
        case singleLoaded(SinglePayload)
        case allLoaded([AccountSection])
        case error(String)
    }

    // MARK: - Observable state

    private(set) var state: State = .idle
    private(set) var isRefreshing: Bool = false
    private(set) var showsCompleted: Bool
    private(set) var selection: Selection = .none

    // MARK: - Dependencies

    private let sessions: AccountSessionRegistry
    private let accountLookup: @MainActor (AccountID) -> Account?
    private let preferences: UserDefaults

    /// Generation counter incremented on every selection change and on
    /// every manual refresh. Async work checks this against the value it
    /// captured at start: if the user moved on, results are dropped.
    private var generation = UUID()

    private var autoRefreshTask: Task<Void, Never>?

    private static let showsCompletedKey = "TasksViewModel.showsCompleted"
    /// Polling cadence. Matches `tasks.google.com`'s own roughly-once-a-
    /// minute refresh in an open tab: short enough to feel live, far
    /// enough from quota.
    private static let autoRefreshInterval: Duration = .seconds(60)

    init(
        sessions: AccountSessionRegistry,
        accountLookup: @escaping @MainActor (AccountID) -> Account?,
        preferences: UserDefaults = .standard
    ) {
        self.sessions = sessions
        self.accountLookup = accountLookup
        self.preferences = preferences
        self.showsCompleted = preferences.bool(forKey: Self.showsCompletedKey)
    }

    // MARK: - Selection / lifecycle

    /// Re-points the view-model at a new selection. No-op if `next`
    /// matches the current selection.
    func setSelection(_ next: Selection) async {
        guard next != selection else { return }
        selection = next

        switch next {
        case .none:
            await reset()
        case .single, .all:
            await reload(forceReload: false)
        }
    }

    /// User-initiated refresh (button + pull-to-refresh). Bypasses the
    /// client caches. Keeps the visible payload up while the new data
    /// is fetched; surfaces errors via the displayed state.
    func refresh() async {
        await reload(forceReload: true, fromUser: true)
    }

    /// Drops to `.idle` and tears the polling loop down. Called when the
    /// last account is signed out.
    func reset() async {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        generation = UUID()
        state = .idle
    }

    /// Switches to a different task list **in single mode**. No-op in
    /// aggregated mode, where every list is rendered concurrently.
    func selectList(_ listID: String) {
        guard case .singleLoaded(var payload) = state else { return }
        guard payload.selectedListID != listID else { return }
        guard payload.lists.contains(where: { $0.id == listID }) else { return }

        payload.selectedListID = listID
        state = .singleLoaded(payload)

        let generation = self.generation
        let accountID: AccountID? = {
            if case .single(let id) = selection { return id }
            return nil
        }()
        guard let accountID else { return }
        Task { await self.loadTasks(accountID: accountID, listID: listID, generation: generation, forceReload: false) }
    }

    /// Toggles completed-task visibility for both modes. Persisted to
    /// `UserDefaults`. Per-(listID, showCompleted) caching inside each
    /// ``GoogleTasksClient`` keeps the toggle instant after the first
    /// fetch under each state.
    func toggleShowsCompleted() {
        showsCompleted.toggle()
        preferences.set(showsCompleted, forKey: Self.showsCompletedKey)
        Task { await reload(forceReload: false) }
    }

    // MARK: - Reload

    private func reload(forceReload: Bool, fromUser: Bool = false) async {
        let generation = UUID()
        self.generation = generation

        switch selection {
        case .none:
            state = .idle
            return

        case .single(let accountID):
            await reloadSingle(accountID: accountID, generation: generation, forceReload: forceReload, fromUser: fromUser)

        case .all(let ids):
            await reloadAll(accountIDs: ids, generation: generation, forceReload: forceReload, fromUser: fromUser)
        }

        startAutoRefreshIfNeeded()
    }

    // MARK: - Single-mode loading

    private func reloadSingle(
        accountID: AccountID,
        generation: UUID,
        forceReload: Bool,
        fromUser: Bool
    ) async {
        guard let account = accountLookup(accountID) else {
            // Account vanished between setSelection and reload (e.g. just
            // got removed). Snap back to idle and let the panel react.
            state = .idle
            return
        }

        // Keep the previous payload visible during a manual refresh so
        // the panel doesn't flash to a spinner.
        if fromUser, case .singleLoaded(var existing) = state {
            isRefreshing = true
            existing.account = account
            state = .singleLoaded(existing)
        } else {
            state = .loading
        }

        defer { if fromUser { isRefreshing = false } }

        let client = sessions.client(for: accountID)
        do {
            let lists = try await client.fetchTaskLists(forceReload: forceReload)
            guard self.generation == generation else { return }

            guard !lists.isEmpty else {
                state = .singleLoaded(SinglePayload(
                    account: account,
                    lists: [],
                    selectedListID: nil,
                    tasksState: .loaded([])
                ))
                return
            }

            let preservedListID = currentlySelectedSingleListID
            let selection: String = {
                if let preservedListID, lists.contains(where: { $0.id == preservedListID }) {
                    return preservedListID
                }
                return lists[0].id
            }()

            state = .singleLoaded(SinglePayload(
                account: account,
                lists: lists,
                selectedListID: selection,
                tasksState: .loading
            ))

            // Warm the cache for every list so subsequent list-switches
            // are instant. Errors here are swallowed individually — a
            // failure on one list must not block the others.
            await preloadTasks(client: client, lists: lists, forceReload: forceReload, generation: generation)
            guard self.generation == generation else { return }

            await loadTasks(accountID: accountID, listID: selection, generation: generation, forceReload: false)
        } catch {
            guard self.generation == generation else { return }
            state = .error(Self.message(for: error))
        }
    }

    private func loadTasks(accountID: AccountID, listID: String, generation: UUID, forceReload: Bool) async {
        let client = sessions.client(for: accountID)
        let showsCompleted = self.showsCompleted

        // Fast path: cache hit → swap directly, no loading flash.
        if !forceReload, let cached = await client.cachedTasks(for: listID, showCompleted: showsCompleted) {
            guard self.generation == generation else { return }
            guard case .singleLoaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(cached)
            state = .singleLoaded(payload)
            return
        }

        if case .singleLoaded(var payload) = state, payload.selectedListID == listID {
            payload.tasksState = .loading
            state = .singleLoaded(payload)
        }

        do {
            let tasks = try await client.fetchTasks(
                in: listID,
                showCompleted: showsCompleted,
                forceReload: forceReload
            )
            guard self.generation == generation else { return }
            guard case .singleLoaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(tasks)
            state = .singleLoaded(payload)
        } catch {
            guard self.generation == generation else { return }
            guard case .singleLoaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .error(Self.message(for: error))
            state = .singleLoaded(payload)
        }
    }

    private func preloadTasks(
        client: GoogleTasksClient,
        lists: [TaskList],
        forceReload: Bool,
        generation: UUID
    ) async {
        let showsCompleted = self.showsCompleted
        await withTaskGroup(of: Void.self) { group in
            for list in lists {
                let listID = list.id
                group.addTask {
                    _ = try? await client.fetchTasks(
                        in: listID,
                        showCompleted: showsCompleted,
                        forceReload: forceReload
                    )
                }
            }
        }
        _ = generation // generation captured here only as documentation
    }

    private var currentlySelectedSingleListID: String? {
        if case .singleLoaded(let payload) = state { return payload.selectedListID }
        return nil
    }

    // MARK: - Aggregated-mode loading

    private func reloadAll(
        accountIDs: [AccountID],
        generation: UUID,
        forceReload: Bool,
        fromUser: Bool
    ) async {
        // Filter to accounts we can resolve right now. An id whose
        // ``accountLookup`` returns `nil` was just removed. Forwarded
        // through an explicit closure rather than passed by reference:
        // Swift 6.0 cannot prove that a `@MainActor` function reference
        // is non-throwing when it lands in `Array.compactMap`'s
        // `rethrows` slot, even though the call site is itself on the
        // main actor.
        let resolved: [Account] = accountIDs.compactMap { accountLookup($0) }

        guard !resolved.isEmpty else {
            state = .idle
            return
        }

        if fromUser, case .allLoaded = state {
            isRefreshing = true
        } else {
            state = .loading
        }
        defer { if fromUser { isRefreshing = false } }

        let showsCompleted = self.showsCompleted
        let sessions = self.sessions

        let sections: [AccountSection] = await withTaskGroup(of: AccountSection?.self) { group in
            for account in resolved {
                let client = sessions.client(for: account.id)
                group.addTask {
                    await Self.section(
                        for: account,
                        client: client,
                        showsCompleted: showsCompleted,
                        forceReload: forceReload
                    )
                }
            }
            var out: [AccountID: AccountSection] = [:]
            for await section in group {
                if let section { out[section.account.id] = section }
            }
            // Preserve user-display order.
            return resolved.compactMap { out[$0.id] }
        }

        guard self.generation == generation else { return }
        state = .allLoaded(sections)
    }

    /// Fetches lists + tasks for one account. Errors on individual lists
    /// surface inside the section so the rest of the aggregated view
    /// keeps rendering.
    private static func section(
        for account: Account,
        client: GoogleTasksClient,
        showsCompleted: Bool,
        forceReload: Bool
    ) async -> AccountSection? {
        let lists: [TaskList]
        do {
            lists = try await client.fetchTaskLists(forceReload: forceReload)
        } catch {
            // Whole account failed to load lists. We still surface a
            // section so the UI shows the user *which* account is in
            // trouble; the per-list error renders in place of tasks.
            let slice = ListSlice(
                list: TaskList(id: "__lists_error__", title: "—", updatedAt: Date()),
                tasksState: .error(messageFor(error))
            )
            return AccountSection(account: account, slices: [slice])
        }

        let slices: [ListSlice] = await withTaskGroup(of: ListSlice.self) { group in
            for list in lists {
                let captured = list
                group.addTask {
                    do {
                        let tasks = try await client.fetchTasks(
                            in: captured.id,
                            showCompleted: showsCompleted,
                            forceReload: forceReload
                        )
                        return ListSlice(list: captured, tasksState: .loaded(tasks))
                    } catch {
                        return ListSlice(list: captured, tasksState: .error(messageFor(error)))
                    }
                }
            }
            var out: [ListSlice] = []
            for await slice in group { out.append(slice) }
            // Keep Google's lexicographic ordering by `id` — there is
            // no documented ordering for task *lists* themselves, but
            // stable across launches matters more than alphabetical.
            return out.sorted { $0.list.id < $1.list.id }
        }

        return AccountSection(account: account, slices: slices)
    }

    // MARK: - Auto-refresh loop

    private func startAutoRefreshIfNeeded() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.autoRefreshInterval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.reload(forceReload: true, fromUser: false)
            }
        }
    }

    // MARK: - Error formatting

    private static func message(for error: Error) -> String {
        messageFor(error)
    }

    /// Free-function variant so the aggregated-mode task group (which
    /// runs off the actor) can format errors without re-entering the
    /// view-model.
    nonisolated private static func messageFor(_ error: Error) -> String {
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
