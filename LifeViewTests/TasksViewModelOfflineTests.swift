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
