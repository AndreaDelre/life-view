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
