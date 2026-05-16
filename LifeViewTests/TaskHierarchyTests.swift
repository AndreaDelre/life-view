import Core
@testable import LifeView
import XCTest

/// Covers the flat-to-hierarchical adapter the task list view uses to
/// turn a `[TaskItem]` into a `[TaskHierarchyEntry]` annotated with
/// depth + sub-task counts.
final class TaskHierarchyTests: XCTestCase {
    func testEntriesPreserveInputOrder() {
        let tasks = [
            makeTask(id: "p1"),
            makeTask(id: "c1", parent: "p1"),
            makeTask(id: "p2")
        ]
        let entries = TaskHierarchy.entries(for: tasks)
        XCTAssertEqual(entries.map(\.task.id), ["p1", "c1", "p2"])
    }

    func testDepthIsZeroForTopLevelAndOneForDirectChild() {
        let tasks = [
            makeTask(id: "p1"),
            makeTask(id: "c1", parent: "p1")
        ]
        let entries = TaskHierarchy.entries(for: tasks)
        XCTAssertEqual(entries.first(where: { $0.id == "p1" })?.depth, 0)
        XCTAssertEqual(entries.first(where: { $0.id == "c1" })?.depth, 1)
    }

    func testOrphanedChildPromotesToTopLevel() {
        // The parent ID points at something we don't have in the input
        // — typically because the user filtered out completed parents.
        // We must not drop the child; we render it at the root.
        let tasks = [makeTask(id: "c1", parent: "ghost")]
        let entries = TaskHierarchy.entries(for: tasks)
        XCTAssertEqual(entries.first?.depth, 0)
    }

    func testSubtaskCountsAggregatePerParent() {
        let tasks = [
            makeTask(id: "p1"),
            makeTask(id: "c1", status: .completed, parent: "p1"),
            makeTask(id: "c2", parent: "p1"),
            makeTask(id: "c3", status: .completed, parent: "p1")
        ]
        let parent = TaskHierarchy.entries(for: tasks).first(where: { $0.id == "p1" })
        XCTAssertEqual(parent?.totalSubtasks, 3)
        XCTAssertEqual(parent?.completedSubtasks, 2)
        XCTAssertTrue(parent?.hasSubtasks ?? false)
    }

    func testParentCycleDoesNotInfiniteLoop() {
        // Defensive guard: a malformed cache could in theory link two
        // tasks at each other. The depth computation must terminate.
        let tasks = [
            makeTask(id: "a", parent: "b"),
            makeTask(id: "b", parent: "a")
        ]
        let entries = TaskHierarchy.entries(for: tasks)
        XCTAssertEqual(entries.count, 2)
        for entry in entries {
            XCTAssertLessThanOrEqual(entry.depth, 1)
        }
    }

    private func makeTask(
        id: String,
        status: TaskStatus = .needsAction,
        parent: String? = nil
    ) -> TaskItem {
        TaskItem(
            id: id,
            title: id.uppercased(),
            status: status,
            position: id,
            parent: parent
        )
    }
}
