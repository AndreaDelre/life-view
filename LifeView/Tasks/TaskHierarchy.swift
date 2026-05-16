import Core

/// One row of a flattened hierarchy: the task plus the view-only context
/// the row needs to render itself (indentation depth + sub-task counts
/// when the row is a parent).
///
/// `depth == 0` means top-level; `1` means a direct sub-task; deeper
/// values exist defensively because Google Tasks could conceivably
/// return a parent chain longer than the one level the API officially
/// supports, and we'd rather indent than drop rows.
struct TaskHierarchyEntry: Equatable, Identifiable {
    let task: TaskItem
    let depth: Int
    let totalSubtasks: Int
    let completedSubtasks: Int

    var id: String { task.id }

    /// True when this row owns at least one sub-task. Used by the view
    /// to decide whether to render the `X/Y` counter.
    var hasSubtasks: Bool { totalSubtasks > 0 }
}

/// Flat-to-hierarchical adapter for the task list.
///
/// Google Tasks returns sub-tasks interleaved with their parent in the
/// order they should appear on screen (the `position` string ordering
/// already places each child between its parent and the next sibling),
/// so we **preserve the input order** and only annotate each task with
/// the depth + sub-task-count metadata the view needs.
///
/// Tasks whose `parent` ID is not present in the input collection are
/// promoted to depth 0 — that handles the legitimate case where the
/// user has filtered out completed parents (sub-tasks would otherwise
/// disappear from view), and the malformed-input case where the parent
/// ID is bogus.
enum TaskHierarchy {
    static func entries(for tasks: [TaskItem]) -> [TaskHierarchyEntry] {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Pre-compute sub-task counts in one pass. Counting later inside
        // the depth loop would be O(n²) on lists with many children.
        var totalByParent: [String: Int] = [:]
        var completedByParent: [String: Int] = [:]
        for task in tasks {
            guard let parentID = task.parent, byID[parentID] != nil else { continue }
            totalByParent[parentID, default: 0] += 1
            if task.status == .completed {
                completedByParent[parentID, default: 0] += 1
            }
        }

        return tasks.map { task in
            TaskHierarchyEntry(
                task: task,
                depth: depth(of: task, in: byID),
                totalSubtasks: totalByParent[task.id] ?? 0,
                completedSubtasks: completedByParent[task.id] ?? 0
            )
        }
    }

    /// Walks up the parent chain to compute the indentation depth. The
    /// visited-set guards against accidental cycles (Google Tasks should
    /// never emit one, but a malformed cache + race could produce one
    /// and we'd rather cap than spin).
    private static func depth(of task: TaskItem, in byID: [String: TaskItem]) -> Int {
        var depth = 0
        var cursor = task
        var visited: Set<String> = [task.id]
        while let parentID = cursor.parent, let parent = byID[parentID], !visited.contains(parentID) {
            depth += 1
            visited.insert(parentID)
            cursor = parent
        }
        return depth
    }
}
