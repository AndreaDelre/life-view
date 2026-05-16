import Foundation

/// Sorting helpers for the parent/child layout of a Google Tasks list.
///
/// Why this exists: ``TaskItem/position`` is **scoped to siblings** —
/// a sub-task's position string sits in its parent's space, not the
/// global list. A naive `sort { $0.position < $1.position }` over the
/// whole array therefore interleaves sub-tasks of different parents in
/// nonsensical ways, which the UI then renders as "wrong parent" rows.
///
/// ``hierarchicallySorted(_:)`` walks the parent/child graph instead:
/// each top-level task is emitted in position order, immediately
/// followed by its children in their own position order. The output
/// matches what Google's web/mobile clients (and Todoist) show.
public extension TaskItem {
    /// Returns `tasks` rearranged so each top-level task is immediately
    /// followed by its sub-tasks (in their own sibling-local position
    /// order). Orphaned children — those whose `parent` ID is missing
    /// from the input — are promoted to top-level so they don't vanish
    /// from the result (matches the view-side fallback used by
    /// `TaskHierarchy.entries`).
    static func hierarchicallySorted(_ tasks: [TaskItem]) -> [TaskItem] {
        // No work to do for the degenerate case — also avoids paying
        // the dictionary build on the hot single-task path used by
        // optimistic-insert reconciliation.
        if tasks.count < 2 { return tasks }

        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        var topLevel: [TaskItem] = []
        var childrenByParent: [String: [TaskItem]] = [:]
        for task in tasks {
            if let parentID = task.parent, byID[parentID] != nil {
                childrenByParent[parentID, default: []].append(task)
            } else {
                topLevel.append(task)
            }
        }

        topLevel.sort { $0.position < $1.position }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort { $0.position < $1.position }
        }

        var result: [TaskItem] = []
        var emitted: Set<String> = []
        result.reserveCapacity(tasks.count)
        // Google Tasks only supports a single nesting level today, but
        // the walk is written recursively so a deeper hierarchy on the
        // wire (or a future API expansion) would still round-trip. The
        // `emitted` guard keeps a malformed parent-cycle from blowing
        // the stack — we surface each task at most once.
        func emit(_ task: TaskItem) {
            guard emitted.insert(task.id).inserted else { return }
            result.append(task)
            for child in childrenByParent[task.id] ?? [] {
                emit(child)
            }
        }
        for top in topLevel {
            emit(top)
        }
        // Defensive fallback: any task that wasn't reached from a
        // top-level root (e.g. members of a parent cycle, where every
        // task has a parent that's in the map) still has to surface in
        // the output — losing rows silently is a worse bug than a
        // visually flat hierarchy.
        for task in tasks where !emitted.contains(task.id) {
            emit(task)
        }
        return result
    }
}
