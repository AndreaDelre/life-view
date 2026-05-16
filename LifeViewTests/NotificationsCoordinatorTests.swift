import Core
import Foundation
import GoogleAuth
@testable import LifeView
import XCTest

/// Pure-function tests for ``NotificationsCoordinator/desiredFromState(_:)``
/// — the mapping from a ``TasksViewModel/State`` to the flat set of
/// notifications the scheduler should reflect.
final class NotificationsCoordinatorTests: XCTestCase {
    private let accountID = AccountID("acct-1")
    private let listID = "list-1"

    private func account() -> Account {
        Account(
            id: accountID,
            profile: AccountProfile(
                subject: "s1",
                email: "u@example.com",
                displayName: "U",
                avatarURL: nil
            )
        )
    }

    private func task(_ id: String, due: Date?, status: TaskStatus = .needsAction) -> TaskItem {
        TaskItem(id: id, title: "T \(id)", status: status, due: due, position: "p")
    }

    func testIdleStateReturnsEmpty() {
        XCTAssertTrue(NotificationsCoordinator.desiredFromState(.idle).isEmpty)
        XCTAssertTrue(NotificationsCoordinator.desiredFromState(.loading).isEmpty)
        XCTAssertTrue(NotificationsCoordinator.desiredFromState(.error("x")).isEmpty)
    }

    func testSingleModeIncludesOnlyDuedNeedsAction() {
        let due = Date().addingTimeInterval(3600)
        let items: [TaskItem] = [
            task("a", due: due),
            task("b", due: nil),              // no due → excluded
            task("c", due: due, status: .completed) // completed → excluded
        ]
        let payload = TasksViewModel.SinglePayload(
            account: account(),
            lists: [TaskList(id: listID, title: "L", updatedAt: Date())],
            selectedListID: listID,
            tasksState: .loaded(items)
        )
        let desired = NotificationsCoordinator.desiredFromState(.singleLoaded(payload))
        XCTAssertEqual(desired.count, 1)
        XCTAssertEqual(desired.first?.taskID, "a")
    }

    func testAggregatedModeWalksEverySliceAndAccount() {
        let due = Date().addingTimeInterval(3600)
        let slice1 = TasksViewModel.ListSlice(
            list: TaskList(id: "L1", title: "L1", updatedAt: Date()),
            tasksState: .loaded([task("a", due: due), task("b", due: nil)])
        )
        let slice2 = TasksViewModel.ListSlice(
            list: TaskList(id: "L2", title: "L2", updatedAt: Date()),
            tasksState: .loaded([task("c", due: due)])
        )
        let section = TasksViewModel.AccountSection(
            account: account(),
            slices: [slice1, slice2]
        )
        let desired = NotificationsCoordinator.desiredFromState(.allLoaded([section]))
        XCTAssertEqual(desired.count, 2)
        XCTAssertEqual(Set(desired.map(\.taskID)), Set(["a", "c"]))
    }

    func testAggregatedModeSkipsLoadingAndErrorSlices() {
        let due = Date().addingTimeInterval(3600)
        let loadingSlice = TasksViewModel.ListSlice(
            list: TaskList(id: "L1", title: "L1", updatedAt: Date()),
            tasksState: .loading
        )
        let errorSlice = TasksViewModel.ListSlice(
            list: TaskList(id: "L2", title: "L2", updatedAt: Date()),
            tasksState: .error("nope")
        )
        let loadedSlice = TasksViewModel.ListSlice(
            list: TaskList(id: "L3", title: "L3", updatedAt: Date()),
            tasksState: .loaded([task("z", due: due)])
        )
        let section = TasksViewModel.AccountSection(
            account: account(),
            slices: [loadingSlice, errorSlice, loadedSlice]
        )
        let desired = NotificationsCoordinator.desiredFromState(.allLoaded([section]))
        XCTAssertEqual(desired.count, 1)
        XCTAssertEqual(desired.first?.taskID, "z")
    }
}
