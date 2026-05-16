import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
import Observation
import OfflineCache

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

    enum Selection: Equatable {
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
        var id: String {
            list.id
        }
    }

    struct AccountSection: Identifiable, Equatable {
        var account: Account
        var slices: [ListSlice]
        var id: AccountID {
            account.id
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case singleLoaded(SinglePayload)
        case allLoaded([AccountSection])
        case error(String)
    }

    // MARK: - Observable state

    /// Write access kept "internal" (no `private(set)`) so the loading
    /// and mutations extensions can apply state transitions. Outside
    /// the view-model family no other LifeView code writes to it.
    var state: State = .idle
    var isRefreshing: Bool = false
    private(set) var showsCompleted: Bool
    private(set) var selection: Selection = .none
    /// Task IDs whose mutation has been applied locally but not yet
    /// confirmed (or failed) by the server. Views read this through
    /// ``isPending(taskID:)``.
    var pendingTaskIDs: Set<String> = []
    /// Last mutation error to surface as a toast. Cleared by
    /// ``dismissError()`` once the view has shown it.
    var lastError: String?

    /// Task id the panel should select / scroll to on the next
    /// rendering pass. Set non-nil by ``focusTask(accountID:listID:taskID:)``
    /// (called when a notification is tapped); cleared by the view
    /// after it has applied the focus.
    var focusRequestTaskID: String?

    // MARK: - Dependencies

    let sessions: AccountSessionRegistry
    let accountLookup: @MainActor (AccountID) -> Account?
    private let preferences: UserDefaults
    let writeQueue: SerialOperationQueue<AccountID>
    /// Disk cache + persistent write queue. Optional so the test
    /// fixture (which doesn't need persistence) can omit it without
    /// dragging a database into every unit test.
    let cache: OfflineCacheStore?
    /// Sync coordinator (network monitor + drainer). Optional for the
    /// same reason as `cache`. The view-model calls
    /// ``OfflineSyncCoordinator/requestDrain(accountID:)`` after a
    /// successful mutation so any backlog flushes opportunistically.
    weak var syncCoordinator: OfflineSyncCoordinator?

    /// Generation counter incremented on every selection change and on
    /// every manual refresh. Async work checks this against the value it
    /// captured at start: if the user moved on, results are dropped.
    var generation = UUID()

    var autoRefreshTask: Task<Void, Never>?

    private static let showsCompletedKey = "TasksViewModel.showsCompleted"
    /// Polling cadence. Matches `tasks.google.com`'s own roughly-once-a-
    /// minute refresh in an open tab: short enough to feel live, far
    /// enough from quota.
    static let autoRefreshInterval: Duration = .seconds(60)

    init(
        sessions: AccountSessionRegistry,
        accountLookup: @escaping @MainActor (AccountID) -> Account?,
        preferences: UserDefaults = .standard,
        writeQueue: SerialOperationQueue<AccountID> = SerialOperationQueue<AccountID>(),
        cache: OfflineCacheStore? = nil,
        syncCoordinator: OfflineSyncCoordinator? = nil
    ) {
        self.sessions = sessions
        self.accountLookup = accountLookup
        self.preferences = preferences
        self.writeQueue = writeQueue
        self.cache = cache
        self.syncCoordinator = syncCoordinator
        showsCompleted = preferences.bool(forKey: Self.showsCompletedKey)
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
            // Hydrate from disk synchronously so the user sees data
            // immediately while the network sync runs in background.
            hydrateFromCache(for: next)
            await reload(forceReload: false)
        }
    }

    /// Synchronously paints `state` from the disk cache for `selection`.
    /// No-op when the cache is absent or empty. Runs *before* every
    /// network reload so the first frame the user sees is never an
    /// empty spinner — provided the previous launch persisted data.
    func hydrateFromCache(for selection: Selection) {
        guard let cache else { return }
        switch selection {
        case .none:
            return
        case let .single(accountID):
            guard let account = accountLookup(accountID),
                  let snapshot = try? cache.snapshot(accountID: accountID),
                  !snapshot.lists.isEmpty else { return }
            let preferredID = snapshot.lists.first?.id
            state = .singleLoaded(SinglePayload(
                account: account,
                lists: snapshot.lists,
                selectedListID: preferredID,
                tasksState: .loaded(preferredID.map(snapshot.tasks) ?? [])
            ))
        case let .all(ids):
            let sections: [AccountSection] = ids.compactMap { id in
                guard let account = accountLookup(id),
                      let snapshot = try? cache.snapshot(accountID: id),
                      !snapshot.lists.isEmpty else { return nil }
                let slices = snapshot.lists.map { list in
                    ListSlice(list: list, tasksState: .loaded(snapshot.tasks(for: list.id)))
                }
                return AccountSection(account: account, slices: slices)
            }
            guard !sections.isEmpty else { return }
            state = .allLoaded(sections)
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
        guard case var .singleLoaded(payload) = state else { return }
        guard payload.selectedListID != listID else { return }
        guard payload.lists.contains(where: { $0.id == listID }) else { return }

        payload.selectedListID = listID
        state = .singleLoaded(payload)

        let generation = generation
        let accountID: AccountID? = {
            if case let .single(id) = selection { return id }
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

    /// Patches the loaded tasks for `(accountID, listID)` in-place,
    /// covering both single and aggregated state shapes. Lives on the
    /// class so `state` keeps its `private(set)` invariant — the P5
    /// mutations extension routes every write through here.
    func mutateTaskList(
        accountID: AccountID,
        listID: String,
        mutator: (inout [TaskItem]) -> Void
    ) {
        switch state {
        case var .singleLoaded(payload):
            guard payload.selectedListID == listID,
                  case var .loaded(items) = payload.tasksState else { return }
            mutator(&items)
            payload.tasksState = .loaded(items)
            state = .singleLoaded(payload)
        case var .allLoaded(sections):
            guard let sectionIdx = sections.firstIndex(where: { $0.id == accountID }),
                  let sliceIdx = sections[sectionIdx].slices.firstIndex(where: { $0.list.id == listID }),
                  case var .loaded(items) = sections[sectionIdx].slices[sliceIdx].tasksState else { return }
            mutator(&items)
            sections[sectionIdx].slices[sliceIdx].tasksState = .loaded(items)
            state = .allLoaded(sections)
        default:
            break
        }
    }

    /// Patches the lists of `accountID` in-place, covering both state
    /// shapes. The mutator works against a plain `[TaskList]`; in
    /// aggregated mode the helper rebuilds ``ListSlice``s from the
    /// updated lists, preserving tasksState for known IDs and seeding
    /// new lists with `.loading` (the next reload picks them up).
    /// Maintains `selectedListID` validity in single mode when the
    /// selected list is removed.
    func mutateAccountLists(
        accountID: AccountID,
        mutator: (inout [TaskList]) -> Void
    ) {
        switch state {
        case var .singleLoaded(payload):
            guard case let .single(id) = selection, id == accountID else { return }
            mutator(&payload.lists)
            let stillContainsSelected = payload.selectedListID
                .map { id in payload.lists.contains(where: { $0.id == id }) } ?? true
            if !stillContainsSelected {
                payload.selectedListID = payload.lists.first?.id
                payload.tasksState = .loaded([])
            }
            state = .singleLoaded(payload)
        case var .allLoaded(sections):
            guard let sectionIdx = sections.firstIndex(where: { $0.id == accountID }) else { return }
            var lists = sections[sectionIdx].slices.map(\.list)
            mutator(&lists)
            let existingByID = Dictionary(
                uniqueKeysWithValues: sections[sectionIdx].slices.map { ($0.list.id, $0) }
            )
            sections[sectionIdx].slices = lists.map { list in
                if var existing = existingByID[list.id] {
                    existing.list = list
                    return existing
                }
                return ListSlice(list: list, tasksState: .loading)
            }
            state = .allLoaded(sections)
        default:
            break
        }
    }

    // MARK: - Error formatting

    /// Localised mutation/refresh error formatter. `nonisolated static`
    /// so the aggregated-mode task group and the P5 mutation extension
    /// — both running off the actor or in another file — can call it
    /// without re-entering the view-model.
    nonisolated static func messageFor(_ error: Error) -> String {
        if let tasksError = error as? GoogleTasksError {
            switch tasksError {
            case .unauthorized: return "Session Google expirée. Reconnecte-toi."
            case let .http(status): return "Erreur Google Tasks (HTTP \(status))."
            case .decodingFailed: return "Réponse Google inattendue."
            case let .transport(message): return "Problème réseau : \(message)"
            case .emptyPatch: return "Modification vide ignorée."
            }
        }
        return (error as NSError).localizedDescription
    }
}
