import Core
import GoogleAuth
import GoogleTasksClient
@testable import LifeView
import XCTest

/// P5 acceptance: every mutation must apply locally on the spot, swap
/// for the server's representation on success, and roll back to the
/// pre-mutation state on failure (with a localised toast on
/// ``TasksViewModel/lastError``).
@MainActor
final class TasksViewModelMutationsTests: XCTestCase {
    // MARK: - createTask

    func testCreateTaskOptimisticallyInsertsThenReconciles() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(
                    statusCode: 200,
                    body: TasksViewModelFixture.taskResponse(
                        id: "server-1",
                        title: "Acheter du pain",
                        position: "00000000000000000001"
                    )
                )
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)

        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        let inserted = viewModel.createTask(title: "Acheter du pain")
        XCTAssertTrue(inserted)

        // Optimistic state: a "local-…" row is already there with
        // pendingTaskIDs containing it.
        let optimisticTasks = tasksInState(viewModel.state)
        XCTAssertEqual(optimisticTasks.count, 1)
        XCTAssertTrue(optimisticTasks[0].id.hasPrefix("local-"))
        XCTAssertEqual(optimisticTasks[0].title, "Acheter du pain")
        XCTAssertTrue(viewModel.isPending(taskID: optimisticTasks[0].id))

        // After the queue drains, the local row is swapped for the
        // server-assigned one and the pending mark is cleared.
        await AsyncWait.until {
            tasksInState(viewModel.state).first?.id == "server-1"
        }
        let reconciled = tasksInState(viewModel.state)
        XCTAssertEqual(reconciled.map(\.id), ["server-1"])
        XCTAssertFalse(viewModel.isPending(taskID: "server-1"))
        XCTAssertNil(viewModel.lastError)
    }

    func testCreateTaskFailureRollsBackAndSurfacesError() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes() + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)

        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        XCTAssertTrue(viewModel.createTask(title: "Tâche"))
        XCTAssertEqual(tasksInState(viewModel.state).count, 1)

        await AsyncWait.until { viewModel.lastError != nil }
        XCTAssertEqual(tasksInState(viewModel.state).count, 0, "failed insert must be rolled back")
        XCTAssertNotNil(viewModel.lastError)
    }

    func testCreateTaskRejectsEmptyTitle() async {
        let http = StubTasksHTTPClient(TasksViewModelFixture.makeInitialFetchOutcomes())
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)

        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        XCTAssertFalse(viewModel.createTask(title: "   "))
        XCTAssertEqual(tasksInState(viewModel.state).count, 0)
    }

    func testCreateTaskRejectedInAggregatedMode() async {
        let http = StubTasksHTTPClient(TasksViewModelFixture.makeInitialFetchOutcomes())
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.all([TasksViewModelFixture.accountID]))

        XCTAssertFalse(viewModel.createTask(title: "Anything"))
    }

    // MARK: - setCompletion

    func testSetCompletionFailureRollsBackStatus() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Acheter du pain", status: "needsAction", position: "00000000000000000001")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        // Optimistic toggle hides the task (showsCompleted=false by default).
        viewModel.setCompletion(
            true,
            for: "t1",
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )
        XCTAssertEqual(tasksInState(viewModel.state).count, 0, "optimistic toggle hides the task")
        XCTAssertTrue(viewModel.isPending(taskID: "t1"))

        await AsyncWait.until { viewModel.lastError != nil }
        let restored = tasksInState(viewModel.state)
        XCTAssertEqual(restored.map(\.status), [.needsAction], "status must roll back to needsAction")
        XCTAssertFalse(viewModel.isPending(taskID: "t1"))
        XCTAssertNotNil(viewModel.lastError)
    }

    // MARK: - editTaskTitle

    func testEditTaskTitleFailureRollsBackTitle() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Avant", status: "needsAction", position: "00000000000000000001")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.editTaskTitle(
            "Après",
            for: "t1",
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )
        XCTAssertEqual(tasksInState(viewModel.state).first?.title, "Après", "optimistic rename")

        await AsyncWait.until { viewModel.lastError != nil }
        XCTAssertEqual(tasksInState(viewModel.state).first?.title, "Avant", "title must roll back on failure")
    }

    func testEditTaskTitleNoOpForUnchangedValue() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Pareil", status: "needsAction", position: "00000000000000000001")
            ])
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.editTaskTitle(
            "  Pareil  ",
            for: "t1",
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )

        // No PATCH request should fire — the stub's queue is empty
        // beyond the initial fetches.
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertFalse(viewModel.isPending(taskID: "t1"))
    }

    // MARK: - deleteTask

    func testDeleteTaskFailureRestoresAtOriginalIndex() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "First", status: "needsAction", position: "00000000000000000001"),
                (id: "t2", title: "Second", status: "needsAction", position: "00000000000000000002"),
                (id: "t3", title: "Third", status: "needsAction", position: "00000000000000000003")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.deleteTask(
            taskID: "t2",
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )
        XCTAssertEqual(tasksInState(viewModel.state).map(\.id), ["t1", "t3"], "optimistic delete")

        await AsyncWait.until { viewModel.lastError != nil }
        XCTAssertEqual(
            tasksInState(viewModel.state).map(\.id),
            ["t1", "t2", "t3"],
            "rollback must re-insert at position-sorted index"
        )
    }

    func testDeleteTaskSuccessLeavesItGone() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "Adieu", status: "needsAction", position: "00000000000000000001")
            ]) + [
                .success(statusCode: 204, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.deleteTask(
            taskID: "t1",
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )

        // Wait for the DELETE request to land.
        await AsyncWait.until { http.requests.count == 3 }
        XCTAssertEqual(tasksInState(viewModel.state).count, 0)
        XCTAssertNil(viewModel.lastError)
    }

    // MARK: - moveTask

    func testMoveTaskOptimisticallyReordersAndReconciles() async throws {
        // After: t1 moves to index 2 (between t2 and t3 in the original
        // array). Expected order post-move: [t2, t1, t3].
        let moveResp = Data(#"""
        {"id":"t1","title":"A","status":"needsAction","position":"00000000000000000015"}
        """#.utf8)
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "A", status: "needsAction", position: "00000000000000000001"),
                (id: "t2", title: "B", status: "needsAction", position: "00000000000000000002"),
                (id: "t3", title: "C", status: "needsAction", position: "00000000000000000003")
            ]) + [
                .success(statusCode: 200, body: moveResp)
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        // Drag t1 (source 0) down past t2 (drop index 2 = "after the
        // item originally at index 1") — IndexSet.onMove convention.
        viewModel.moveTask(
            from: 0,
            to: 2,
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )

        // Optimistic reorder is immediate.
        XCTAssertEqual(tasksInState(viewModel.state).map(\.id), ["t2", "t1", "t3"])
        XCTAssertTrue(viewModel.isPending(taskID: "t1"))

        // Wait for the move request to land and the row to reconcile.
        await AsyncWait.until { http.requests.count == 3 }
        await AsyncWait.until { !viewModel.isPending(taskID: "t1") }

        XCTAssertEqual(tasksInState(viewModel.state).map(\.id), ["t2", "t1", "t3"])
        // The server's updated `position` must be reflected on the row.
        XCTAssertEqual(
            tasksInState(viewModel.state).first(where: { $0.id == "t1" })?.position,
            "00000000000000000015"
        )
        XCTAssertNil(viewModel.lastError)

        // The move request must carry `previous=t2` (the new sibling
        // immediately above t1 in the reordered array).
        let moveReq = http.requests[2]
        XCTAssertEqual(moveReq.httpMethod, "POST")
        XCTAssertEqual(moveReq.url?.path.hasSuffix("/lists/list-1/tasks/t1/move"), true)
        let query = URLComponents(url: try XCTUnwrap(moveReq.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "previous" })?.value, "t2")
    }

    func testMoveTaskToTopSendsNoPreviousQueryParam() async throws {
        let moveResp = Data(#"""
        {"id":"t3","title":"C","status":"needsAction","position":"00000000000000000000"}
        """#.utf8)
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "A", status: "needsAction", position: "00000000000000000001"),
                (id: "t2", title: "B", status: "needsAction", position: "00000000000000000002"),
                (id: "t3", title: "C", status: "needsAction", position: "00000000000000000003")
            ]) + [
                .success(statusCode: 200, body: moveResp)
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.moveTask(
            from: 2,
            to: 0,
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )

        XCTAssertEqual(tasksInState(viewModel.state).map(\.id), ["t3", "t1", "t2"])
        await AsyncWait.until { http.requests.count == 3 }

        let moveReq = http.requests[2]
        let query = URLComponents(url: try XCTUnwrap(moveReq.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertNil(
            query?.first(where: { $0.name == "previous" }),
            "moving to the top must omit the `previous` query param"
        )
    }

    func testMoveTaskFailureRollsBackOrder() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "A", status: "needsAction", position: "00000000000000000001"),
                (id: "t2", title: "B", status: "needsAction", position: "00000000000000000002"),
                (id: "t3", title: "C", status: "needsAction", position: "00000000000000000003")
            ]) + [
                .success(statusCode: 500, body: Data())
            ]
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.moveTask(
            from: 0,
            to: 2,
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )
        XCTAssertEqual(tasksInState(viewModel.state).map(\.id), ["t2", "t1", "t3"])

        await AsyncWait.until { viewModel.lastError != nil }
        XCTAssertEqual(
            tasksInState(viewModel.state).map(\.id),
            ["t1", "t2", "t3"],
            "failed move must restore the original order"
        )
        XCTAssertFalse(viewModel.isPending(taskID: "t1"))
    }

    func testMoveTaskNoOpWhenDestinationEqualsSource() async {
        let http = StubTasksHTTPClient(
            TasksViewModelFixture.makeInitialFetchOutcomes(tasks: [
                (id: "t1", title: "A", status: "needsAction", position: "00000000000000000001"),
                (id: "t2", title: "B", status: "needsAction", position: "00000000000000000002")
            ])
        )
        let viewModel = TasksViewModelFixture.makeViewModel(http: http)
        await viewModel.setSelection(.single(TasksViewModelFixture.accountID))

        viewModel.moveTask(
            from: 1,
            to: 1,
            in: TasksViewModelFixture.listID,
            account: TasksViewModelFixture.accountID
        )

        // Only the two initial fetches should have hit the network.
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(tasksInState(viewModel.state).map(\.id), ["t1", "t2"])
        XCTAssertFalse(viewModel.isPending(taskID: "t1"))
    }

    // MARK: - Helpers

    /// Pulls the visible `[TaskItem]` out of the VM state regardless of
    /// which `.singleLoaded` / `.allLoaded` shape we're in. Tests only
    /// drive single mode, so this returns the active list's tasks.
    private func tasksInState(_ state: TasksViewModel.State) -> [TaskItem] {
        if case let .singleLoaded(payload) = state,
           case let .loaded(tasks) = payload.tasksState
        {
            return tasks
        }
        return []
    }
}
