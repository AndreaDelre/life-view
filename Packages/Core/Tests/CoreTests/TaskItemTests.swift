import XCTest
@testable import Core

final class TaskItemTests: XCTestCase {
    func testInitDefaultsNotesAndDueToNil() {
        let item = TaskItem(id: "abc", title: "Buy milk", status: .needsAction, position: "00000000000000000001")

        XCTAssertNil(item.notes)
        XCTAssertNil(item.due)
        XCTAssertEqual(item.status, .needsAction)
    }

    func testEquatabilityComparesAllFields() {
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let lhs = TaskItem(id: "1", title: "T", notes: "n", status: .completed, due: due, position: "p")
        let rhs = TaskItem(id: "1", title: "T", notes: "n", status: .completed, due: due, position: "p")
        XCTAssertEqual(lhs, rhs)

        let differentTitle = TaskItem(id: "1", title: "T2", notes: "n", status: .completed, due: due, position: "p")
        XCTAssertNotEqual(lhs, differentTitle)
    }

    func testPositionIsCompareLexicographically() {
        // Sanity check that Google's lexicographic position strings sort the
        // way the UI expects them to (string comparison, not numeric).
        let positions = ["00000000000000000010", "00000000000000000002", "00000000000000000001"]
        XCTAssertEqual(
            positions.sorted(),
            ["00000000000000000001", "00000000000000000002", "00000000000000000010"]
        )
    }
}

final class TaskListTests: XCTestCase {
    func testIdentifiableConformanceUsesID() {
        let list = TaskList(id: "list-1", title: "Personnel", updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(list.id, "list-1")
    }
}

final class TaskStatusTests: XCTestCase {
    func testRawValuesMatchGoogleTasksAPI() {
        // Google Tasks returns these exact strings on the wire — keep the
        // raw values aligned so the REST DTOs can decode straight into the
        // domain enum.
        XCTAssertEqual(TaskStatus.needsAction.rawValue, "needsAction")
        XCTAssertEqual(TaskStatus.completed.rawValue, "completed")
    }
}
