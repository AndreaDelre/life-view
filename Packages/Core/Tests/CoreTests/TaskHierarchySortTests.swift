import XCTest
@testable import Core

final class TaskHierarchySortTests: XCTestCase {
    func testEmptyAndSingleTaskReturnUnchanged() {
        XCTAssertEqual(TaskItem.hierarchicallySorted([]), [])
        let solo = makeTask(id: "a", position: "1")
        XCTAssertEqual(TaskItem.hierarchicallySorted([solo]), [solo])
    }

    func testTopLevelTasksSortedByPosition() {
        let tasks = [
            makeTask(id: "c", position: "00000000000000000003"),
            makeTask(id: "a", position: "00000000000000000001"),
            makeTask(id: "b", position: "00000000000000000002")
        ]
        XCTAssertEqual(TaskItem.hierarchicallySorted(tasks).map(\.id), ["a", "b", "c"])
    }

    func testChildrenAreEmittedRightAfterTheirParent() {
        // Real-world shape of the bug seen in #34: two parents each with
        // children. A flat sort by `position` would interleave them; the
        // hierarchical sort must keep each parent's sub-tasks together.
        let tasks = [
            // top-levels (their position governs the parent order)
            makeTask(id: "p1", position: "00000000000000000001"),
            makeTask(id: "p2", position: "00000000000000000002"),
            // p1's children — sibling-local positions
            makeTask(id: "p1.c1", position: "00000000000000000001", parent: "p1"),
            makeTask(id: "p1.c2", position: "00000000000000000002", parent: "p1"),
            // p2's children — same sibling-local positions
            makeTask(id: "p2.c1", position: "00000000000000000001", parent: "p2"),
            makeTask(id: "p2.c2", position: "00000000000000000002", parent: "p2")
        ]
        XCTAssertEqual(
            TaskItem.hierarchicallySorted(tasks).map(\.id),
            ["p1", "p1.c1", "p1.c2", "p2", "p2.c1", "p2.c2"]
        )
    }

    func testChildrenSortedByLocalPosition() {
        let tasks = [
            makeTask(id: "p", position: "00000000000000000001"),
            makeTask(id: "c.late", position: "00000000000000000003", parent: "p"),
            makeTask(id: "c.early", position: "00000000000000000001", parent: "p"),
            makeTask(id: "c.mid", position: "00000000000000000002", parent: "p")
        ]
        XCTAssertEqual(
            TaskItem.hierarchicallySorted(tasks).map(\.id),
            ["p", "c.early", "c.mid", "c.late"]
        )
    }

    func testOrphanedChildIsPromotedToTopLevel() {
        // The parent ID points at something we don't have in the input
        // (typically the parent is completed and hidden by the filter).
        // The orphan must still appear; placing it at top level is the
        // same behaviour `TaskHierarchy.entries` falls back to so the
        // view stays consistent.
        let orphan = makeTask(id: "orphan", position: "00000000000000000005", parent: "ghost")
        let top = makeTask(id: "real", position: "00000000000000000001")
        let result = TaskItem.hierarchicallySorted([orphan, top])
        XCTAssertEqual(result.map(\.id), ["real", "orphan"])
    }

    func testParentChildCycleTerminates() {
        // Defensive: a malformed cache could in theory link two rows at
        // each other. The function must not infinite-loop and must
        // return both rows in some order.
        let tasks = [
            makeTask(id: "a", position: "1", parent: "b"),
            makeTask(id: "b", position: "2", parent: "a")
        ]
        let result = TaskItem.hierarchicallySorted(tasks)
        XCTAssertEqual(Set(result.map(\.id)), Set(["a", "b"]))
    }

    private func makeTask(id: String, position: String, parent: String? = nil) -> TaskItem {
        TaskItem(
            id: id,
            title: id,
            status: .needsAction,
            position: position,
            parent: parent
        )
    }
}
