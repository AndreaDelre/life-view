@testable import Core
import XCTest

final class TaskPatchTests: XCTestCase {
    func testEmptyPatchIsEmpty() {
        XCTAssertTrue(TaskPatch().isEmpty)
        XCTAssertFalse(TaskPatch(title: .set("x")).isEmpty)
        XCTAssertFalse(TaskPatch(due: .clear).isEmpty)
    }

    func testApplyChangesOnlyTouchedFields() {
        var task = TaskItem(
            id: "t1",
            title: "Original",
            notes: "kept",
            status: .needsAction,
            due: Date(timeIntervalSince1970: 1000),
            position: "p"
        )

        TaskPatch(title: .set("Renamed")).apply(to: &task)

        XCTAssertEqual(task.title, "Renamed")
        XCTAssertEqual(task.notes, "kept", "untouched fields must stay")
        XCTAssertEqual(task.due, Date(timeIntervalSince1970: 1000))
    }

    func testApplyClearableFieldsClearWhenSetToNil() {
        var task = TaskItem(
            id: "t1",
            title: "x",
            notes: "to-clear",
            status: .needsAction,
            due: Date(timeIntervalSince1970: 1000),
            position: "p"
        )

        TaskPatch(notes: .clear, due: .clear).apply(to: &task)

        XCTAssertNil(task.notes)
        XCTAssertNil(task.due)
    }

    func testApplyDoesNotClearStatusOrTitleEvenIfSetToNil() {
        // `title` and `status` cannot meaningfully be `nil` in the domain
        // model — `apply` ignores `.set(nil)` for these. The wire encoder
        // would still emit `null`, but Google rejects that for required
        // fields. Belt-and-braces: do not corrupt the local task.
        var task = TaskItem(id: "t1", title: "x", status: .needsAction, position: "p")

        TaskPatch(title: .set(nil), status: .set(nil)).apply(to: &task)

        XCTAssertEqual(task.title, "x")
        XCTAssertEqual(task.status, .needsAction)
    }
}
