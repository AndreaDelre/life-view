import Core
import Foundation
import GoogleAuth

/// Synchronous read view over a single account's cached data.
///
/// Built once on the calling thread by ``OfflineCacheStore/snapshot``
/// so the `TasksViewModel` (main-actor) can render its initial state
/// **without** crossing an actor boundary — the very first paint of
/// the panel is the most latency-sensitive interaction in the app.
///
/// Snapshots are immutable; they capture the cache at a point in time.
/// Subsequent reads through the actor's async API return fresher data.
public struct OfflineCacheSnapshot: Sendable, Equatable {
    /// Lists for the account, unsorted (callers apply their own
    /// ordering — typically by `id` for stable cross-launch order).
    public let lists: [TaskList]

    /// Tasks keyed by `listID`. Each value is already sorted by
    /// `position` so the caller can hand the array straight to the UI.
    public let tasksByList: [String: [TaskItem]]

    public init(lists: [TaskList] = [], tasksByList: [String: [TaskItem]] = [:]) {
        self.lists = lists
        self.tasksByList = tasksByList
    }

    /// Empty snapshot — used when no row exists yet for the account.
    public static let empty = OfflineCacheSnapshot()

    /// Convenience accessor: tasks for `listID`, empty array if absent.
    public func tasks(for listID: String) -> [TaskItem] {
        tasksByList[listID] ?? []
    }
}
