import Core
import Foundation

/// P6.3 `tasks.move` endpoint. Lives in its own file so the main
/// ``GoogleTasksClient`` actor stays under the SwiftLint file-length
/// and actor-body budgets — the rest of the actor is the read path
/// plus the P5 CRUD mutations, already at the limit.
public extension GoogleTasksClient {
    /// Reorders a task within `listID`.
    ///
    /// - Parameters:
    ///   - listID: List that owns the task.
    ///   - taskID: Task to move.
    ///   - previous: ID of the task that should sit immediately *before*
    ///     `taskID` once the move is applied. `nil` moves `taskID` to the
    ///     top of the list.
    ///   - parent: Parent task ID for sub-tasks. `nil` keeps the task at
    ///     root level. P6.3 only exercises root-level reordering — the
    ///     parameter is exposed for symmetry with the REST endpoint and
    ///     to keep the door open for sub-task drags in a later phase.
    ///
    /// On success, the moved task's row in every cached `(listID, *)`
    /// view is replaced with the server's canonical representation
    /// (whose `position` reflects the new ordering) and the cache is
    /// re-sorted.
    @discardableResult
    func moveTask(
        in listID: String,
        taskID: String,
        previous: String?,
        parent: String? = nil
    ) async throws -> TaskItem {
        let url = GoogleTasksEndpoints.moveTask(
            in: listID,
            taskID: taskID,
            parent: parent,
            previous: previous
        )
        let remote: RemoteTask = try await performMutation(
            description: "POST tasks/move",
            method: "POST",
            url: url,
            body: nil
        )
        guard let moved = remote.toDomain() else {
            throw GoogleTasksError.decodingFailed
        }
        applyUpdateToCache(moved, listID: listID)
        logger.debug("Moved task in list")
        return moved
    }
}
