import Core
import Foundation
import GoogleAuth
@testable import LifeView
import OfflineCache
import XCTest

/// P6.6 acceptance: when the network fails on a transport-shaped error
/// (transport / 5xx / 408 / 429) the optimistic mutation **must** be
/// preserved locally and the intent **must** be persisted to the
/// pending-writes queue so the drainer can replay it after reconnect.
@MainActor
final class TasksViewModelOfflineTests: XCTestCase {
    private let listID = TasksViewModelFixture.listID
    private let accountID = TasksViewModelFixture.accountID

    func testHydrateFromCache_paintsListsAndTasksBeforeNetwork() async throws {
        let cache = try OfflineCacheStore.inMemory()
        try await cache.saveLists([
            TaskList(id: listID, title: "Personnel", updatedAt: Date())
        ], accountID: accountID)
        try await cache.saveTasks([
            TaskItem(id: "cached-1", title: "Cold start", status: .needsAction, position: "p")
        ], listID: listID, accountID: accountID)

        // No HTTP responses queued — if the view-model hits the
        // network for its initial paint, the stub throws.
        let http = StubTasksHTTPClient([])
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)

        // `setSelection` calls hydrateFromCache before kicking the
        // network reload, so by the time we observe the state the
        // cache has already painted.
        viewModel.hydrateFromCache(for: .single(accountID))

        let tasks = tasksInState(viewModel.state)
        XCTAssertEqual(tasks.map(\.id), ["cached-1"])
    }

    func testCreateTaskTransportFailure_enqueuesPendingWrite() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))

        XCTAssertTrue(viewModel.createTask(title: "Hors-ligne"))

        await waitForPendingWrite(cache: cache, accountID: accountID)
        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
        if case let .createTask(persistedListID, _, draft) = pending.first?.payload {
            XCTAssertEqual(persistedListID, listID)
            XCTAssertEqual(draft.title, "Hors-ligne")
        } else {
            XCTFail("expected .createTask payload, got \(String(describing: pending.first?.payload))")
        }
        // The optimistic row stays put so the user keeps seeing their work.
        let tasks = tasksInState(viewModel.state)
        XCTAssertEqual(tasks.count, 1)
    }

    func testDeleteTaskTransportFailure_enqueuesAndKeepsRowGone() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Adieu", status: "needsAction", position: "00000000000000000001")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))

        viewModel.deleteTask(taskID: "t1", in: listID, account: accountID)
        XCTAssertEqual(tasksInState(viewModel.state).count, 0)

        await waitForPendingWrite(cache: cache, accountID: accountID)
        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
        if case .deleteTask(let pListID, let pTaskID) = pending.first?.payload {
            XCTAssertEqual(pListID, listID)
            XCTAssertEqual(pTaskID, "t1")
        } else {
            XCTFail("expected .deleteTask payload")
        }
        // The row stayed gone in the UI; the rollback path was skipped.
        XCTAssertEqual(tasksInState(viewModel.state).count, 0)
    }

    // MARK: - Collapse: offline edits on a not-yet-flushed local task

    /// Create offline → toggle: the queue must end up with **one**
    /// `.createTask` whose draft carries the final status, not a pair
    /// (`.createTask` + `.completeTask`).
    func testCollapse_createOfflineThenToggle_mergesIntoCreateDraft() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))
        XCTAssertTrue(viewModel.createTask(title: "Hors-ligne"))
        await waitForPendingWrite(cache: cache, accountID: accountID)

        let localID = try XCTUnwrap(firstLocalTaskID(in: viewModel.state))
        viewModel.setCompletion(true, for: localID, in: listID, account: accountID)
        await waitForCollapse(cache: cache, accountID: accountID) { writes in
            guard case let .createTask(_, _, draft)? = writes.first?.payload else { return false }
            return draft.status == .completed
        }

        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertEqual(pending.count, 1, "collapse must not stack a separate completeTask")
        if case let .createTask(_, _, draft) = pending.first?.payload {
            XCTAssertEqual(draft.title, "Hors-ligne")
            XCTAssertEqual(draft.status, .completed)
        } else {
            XCTFail("expected .createTask payload, got \(String(describing: pending.first?.payload))")
        }
    }

    /// Create offline → rename: queue stays at one `.createTask` whose
    /// draft.title reflects the rename.
    func testCollapse_createOfflineThenRename_mergesIntoCreateDraft() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))
        XCTAssertTrue(viewModel.createTask(title: "Brouillon"))
        await waitForPendingWrite(cache: cache, accountID: accountID)

        let localID = try XCTUnwrap(firstLocalTaskID(in: viewModel.state))
        viewModel.editTaskTitle("Titre final", for: localID, in: listID, account: accountID)
        await waitForCollapse(cache: cache, accountID: accountID) { writes in
            guard case let .createTask(_, _, draft)? = writes.first?.payload else { return false }
            return draft.title == "Titre final"
        }

        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
        if case let .createTask(_, _, draft) = pending.first?.payload {
            XCTAssertEqual(draft.title, "Titre final")
        } else {
            XCTFail("expected .createTask payload")
        }
    }

    /// Edit title + toggle on the same local task must preserve **both**
    /// mutations in the queued draft — the merge is field-scoped.
    func testCollapse_renameThenToggle_preservesBothFields() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))
        XCTAssertTrue(viewModel.createTask(title: "Initial"))
        await waitForPendingWrite(cache: cache, accountID: accountID)

        let localID = try XCTUnwrap(firstLocalTaskID(in: viewModel.state))
        viewModel.editTaskTitle("Renommé", for: localID, in: listID, account: accountID)
        await waitForCollapse(cache: cache, accountID: accountID) { writes in
            guard case let .createTask(_, _, draft)? = writes.first?.payload else { return false }
            return draft.title == "Renommé"
        }
        viewModel.setCompletion(true, for: localID, in: listID, account: accountID)
        await waitForCollapse(cache: cache, accountID: accountID) { writes in
            guard case let .createTask(_, _, draft)? = writes.first?.payload else { return false }
            return draft.status == .completed
        }

        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
        if case let .createTask(_, _, draft) = pending.first?.payload {
            XCTAssertEqual(draft.title, "Renommé")
            XCTAssertEqual(draft.status, .completed)
        } else {
            XCTFail("expected .createTask payload")
        }
    }

    /// Create offline → delete: the queue ends up empty (no orphan
    /// `.createTask` waiting to resurrect the row) and the local row is
    /// gone.
    func testCollapse_createOfflineThenDelete_removesQueueEntry() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))
        XCTAssertTrue(viewModel.createTask(title: "À supprimer"))
        await waitForPendingWrite(cache: cache, accountID: accountID)

        let localID = try XCTUnwrap(firstLocalTaskID(in: viewModel.state))
        viewModel.deleteTask(taskID: localID, in: listID, account: accountID)
        await waitForQueueEmpty(cache: cache, accountID: accountID)

        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(tasksInState(viewModel.state).count, 0)
    }

    /// Once the optimistic create has failed offline, the row must
    /// stop reporting as "pending" so the UI lets the user toggle /
    /// rename / delete it.
    func testCreateOffline_clearsPendingFlagAfterEnqueue() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))
        XCTAssertTrue(viewModel.createTask(title: "Tâche libre"))
        await waitForPendingWrite(cache: cache, accountID: accountID)

        let localID = try XCTUnwrap(firstLocalTaskID(in: viewModel.state))
        XCTAssertFalse(viewModel.isPending(taskID: localID), "offline create must release pending flag")
    }

    func testCompletionTransportFailure_enqueuesCompleteTaskVariant() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Cocher", status: "needsAction", position: "p1")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))

        viewModel.setCompletion(true, for: "t1", in: listID, account: accountID)

        await waitForPendingWrite(cache: cache, accountID: accountID)
        let pending = try await cache.pendingWrites(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
        if case let .completeTask(_, taskID, isCompleted) = pending.first?.payload {
            XCTAssertEqual(taskID, "t1")
            XCTAssertTrue(isCompleted)
        } else {
            XCTFail("expected .completeTask payload, got \(String(describing: pending.first?.payload))")
        }
    }

    /// Toggle complétion sur tâche server-ID en offline → l'opération
    /// est queue ET le flag `pendingTaskIDs` est libéré pour que la row
    /// reste interactive (la dernière mutation drainée gagne).
    func testCompletionTransportFailure_clearsPendingFlag() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Cocher", status: "needsAction", position: "p1")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))

        viewModel.setCompletion(true, for: "t1", in: listID, account: accountID)
        await waitForPendingWrite(cache: cache, accountID: accountID)

        XCTAssertFalse(
            viewModel.isPending(taskID: "t1"),
            "offline completion must release pending flag so the row stays interactive"
        )
    }

    /// Drag-to-reorder en offline → la move est queue ET le flag
    /// `pendingTaskIDs` est libéré.
    func testMoveTransportFailure_clearsPendingFlag() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Un", status: "needsAction", position: "00000000000000000001"),
                (id: "t2", title: "Deux", status: "needsAction", position: "00000000000000000002")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http, cache: cache)
        await viewModel.setSelection(.single(accountID))

        // Move t1 (index 0) to be after t2 (drop at index 2).
        viewModel.moveTask(from: 0, to: 2, in: listID, account: accountID)
        await waitForPendingWrite(cache: cache, accountID: accountID)

        XCTAssertFalse(
            viewModel.isPending(taskID: "t1"),
            "offline move must release pending flag so the row stays interactive"
        )
    }
}

/// Small helper duplicated from the P5 test file because XCTestCase
/// classes can't share members across files without making them
/// public on a shared base.
@MainActor
private func tasksInState(_ state: TasksViewModel.State) -> [TaskItem] {
    switch state {
    case let .singleLoaded(payload):
        if case let .loaded(items) = payload.tasksState { return items }
        return []
    default:
        return []
    }
}

/// Polls the persistent cache until at least one pending write is
/// observed for `accountID`. Replaces `AsyncWait.until` which only
/// accepts a synchronous predicate.
@MainActor
private func waitForPendingWrite(
    cache: OfflineCacheStore,
    accountID: AccountID,
    timeout: TimeInterval = 1.0
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let writes = try? await cache.pendingWrites(accountID: accountID), !writes.isEmpty {
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// Polls the persistent cache until `predicate(writes)` returns `true`
/// or `timeout` elapses. Used by the collapse tests to wait until a
/// muted `.createTask` payload is observable.
@MainActor
private func waitForCollapse(
    cache: OfflineCacheStore,
    accountID: AccountID,
    timeout: TimeInterval = 1.0,
    where predicate: ([PendingWrite]) -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let writes = try? await cache.pendingWrites(accountID: accountID), predicate(writes) {
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// Polls until the queue is empty (used by the create-then-delete
/// collapse test).
@MainActor
private func waitForQueueEmpty(
    cache: OfflineCacheStore,
    accountID: AccountID,
    timeout: TimeInterval = 1.0
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let writes = try? await cache.pendingWrites(accountID: accountID), writes.isEmpty {
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// Extracts the first `local-…` task ID from a single-mode state. The
/// optimistic `createTask` inserts at index 0, so the assertion is
/// stable.
@MainActor
private func firstLocalTaskID(in state: TasksViewModel.State) -> String? {
    tasksInState(state).first(where: { $0.id.hasPrefix("local-") })?.id
}
