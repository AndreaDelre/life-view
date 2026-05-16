import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
import OfflineCache

/// P6.6 offline glue for ``TasksViewModel``.
///
/// Lives in its own extension so the read (`+Loading`) and write
/// (`+Mutations`) extensions stay focused. Three responsibilities:
///
/// 1. Persist successful network reads to the disk cache.
/// 2. Persist successful network mutations to the disk cache (so the
///    next launch reflects them even when offline).
/// 3. Detect mutations that failed for transport reasons and convert
///    them into a queued ``PendingWrite`` for the drainer.
extension TasksViewModel {
    // MARK: - Read-side persistence

    /// Persists a freshly-fetched set of lists for one account.
    /// Fire-and-forget — a cache write failure is logged but never
    /// blocks the UI: the in-memory state is the source of truth and
    /// the next sync will re-attempt the persist.
    func persistLists(_ lists: [TaskList], accountID: AccountID) {
        guard let cache else { return }
        Task.detached(priority: .utility) {
            try? await cache.saveLists(lists, accountID: accountID)
        }
    }

    /// Persists a freshly-fetched set of tasks for one list.
    func persistTasks(_ tasks: [TaskItem], listID: String, accountID: AccountID) {
        guard let cache else { return }
        Task.detached(priority: .utility) {
            try? await cache.saveTasks(tasks, listID: listID, accountID: accountID)
        }
    }

    /// Upserts a single task into the cache after a successful create /
    /// update / move so a subsequent launch sees the freshest state
    /// even before the next list-level refresh runs.
    func persistTaskUpsert(_ task: TaskItem, listID: String, accountID: AccountID) {
        guard let cache else { return }
        Task.detached(priority: .utility) {
            try? await cache.upsertTask(task, listID: listID, accountID: accountID)
        }
    }

    func persistTaskDelete(taskID: String, listID: String, accountID: AccountID) {
        guard let cache else { return }
        Task.detached(priority: .utility) {
            try? await cache.deleteTask(taskID: taskID, listID: listID, accountID: accountID)
        }
    }

    func persistListUpsert(_ list: TaskList, accountID: AccountID) {
        guard let cache else { return }
        Task.detached(priority: .utility) {
            try? await cache.upsertList(list, accountID: accountID)
        }
    }

    func persistListDelete(listID: String, accountID: AccountID) {
        guard let cache else { return }
        Task.detached(priority: .utility) {
            try? await cache.deleteList(listID: listID, accountID: accountID)
        }
    }

    // MARK: - Mutation enqueue (transport failures)

    /// Returns `true` when a mutation failure is "transport-shaped" —
    /// meaning the request never reached the server in a meaningful
    /// way, so re-queueing it for the drainer is safe.
    ///
    /// Permanent 4xx errors (`http(400…499)` except `408`/`429`) are
    /// *not* queued: replaying them would just fail again. The
    /// caller's existing rollback path stands.
    static func isTransportFailure(_ error: Error) -> Bool {
        guard let tasksError = error as? GoogleTasksError else { return false }
        switch tasksError {
        case .transport: return true
        case let .http(status):
            // 408 Request Timeout & 429 Rate Limited are transient by
            // design — Google retries hints. 5xx is always retryable.
            return status >= 500 || status == 408 || status == 429
        case .unauthorized, .decodingFailed, .emptyPatch:
            return false
        }
    }

    /// Persists `payload` to the disk queue and pings the coordinator
    /// so the drainer picks it up as soon as the network comes back.
    /// Fire-and-forget; cache write errors are logged.
    func enqueuePending(_ payload: PendingWritePayload, accountID: AccountID) {
        guard let cache else { return }
        let coordinator = syncCoordinator
        Task.detached(priority: .utility) {
            _ = try? await cache.enqueueWrite(accountID: accountID, payload: payload)
            await coordinator?.requestDrain(accountID: accountID)
        }
    }

    /// Awaitable variant of ``enqueuePending``. Used by ``createTask``'s
    /// offline branch so a subsequent toggle/rename/delete on the local
    /// row can be sure to find the queued entry when it walks the queue
    /// to collapse it. Returns silently when the cache is absent.
    func enqueuePendingAwait(_ payload: PendingWritePayload, accountID: AccountID) async {
        guard let cache else { return }
        _ = try? await cache.enqueueWrite(accountID: accountID, payload: payload)
        await syncCoordinator?.requestDrain(accountID: accountID)
    }

    // MARK: - Collapse helpers (offline local-ID mutations)

    /// Mutes the queued `.createTask` payload for `localID` so the user's
    /// toggle is folded into the eventual server insert. No-op when no
    /// queued entry is found (drainer already flushed, or no cache).
    /// Returns `true` when the collapse happened.
    @discardableResult
    func collapseCreateStatus(
        localID: String,
        isCompleted: Bool,
        accountID: AccountID
    ) async -> Bool {
        guard let cache else { return false }
        guard let entry = try? await cache.findCreateTask(
            accountID: accountID,
            clientTaskID: localID
        ) else { return false }
        let nextStatus: TaskStatus = isCompleted ? .completed : .needsAction
        _ = try? await cache.mutatePendingWrite(id: entry.id) { payload in
            guard case var .createTask(listID, clientID, draft) = payload else { return payload }
            draft.status = nextStatus
            return .createTask(listID: listID, clientTaskID: clientID, draft: draft)
        }
        return true
    }

    /// Mutes the queued `.createTask` payload's `title` for `localID`.
    /// Same pattern as ``collapseCreateStatus``.
    @discardableResult
    func collapseCreateTitle(
        localID: String,
        newTitle: String,
        accountID: AccountID
    ) async -> Bool {
        guard let cache else { return false }
        guard let entry = try? await cache.findCreateTask(
            accountID: accountID,
            clientTaskID: localID
        ) else { return false }
        _ = try? await cache.mutatePendingWrite(id: entry.id) { payload in
            guard case var .createTask(listID, clientID, draft) = payload else { return payload }
            draft.title = newTitle
            return .createTask(listID: listID, clientTaskID: clientID, draft: draft)
        }
        return true
    }

    /// Drops the queued `.createTask` entry for `localID`. The local
    /// row vanishes synchronously elsewhere; the queue removal here
    /// ensures the drainer doesn't resurrect the task on reconnect.
    /// Returns `true` when an entry was removed.
    @discardableResult
    func collapseCreateDelete(
        localID: String,
        accountID: AccountID
    ) async -> Bool {
        guard let cache else { return false }
        guard let entry = try? await cache.findCreateTask(
            accountID: accountID,
            clientTaskID: localID
        ) else { return false }
        try? await cache.removeWrite(id: entry.id)
        return true
    }

    // MARK: - Patch → payload mapping

    /// Picks the most specific ``PendingWritePayload`` variant for a
    /// ``TaskPatch``. A pure status flip becomes a
    /// ``PendingWritePayload/completeTask`` so the drainer can
    /// short-circuit stale toggles; anything else falls through to the
    /// generic ``PendingWritePayload/updateTask``.
    static func payload(
        for patch: TaskPatch,
        listID: String,
        taskID: String
    ) -> PendingWritePayload {
        if case let .set(value) = patch.status,
           let status = value,
           isUnchanged(patch.title),
           isUnchanged(patch.notes),
           isUnchanged(patch.due) {
            return .completeTask(listID: listID, taskID: taskID, isCompleted: status == .completed)
        }
        return .updateTask(listID: listID, taskID: taskID, patch: PendingTaskPatch(patch: patch))
    }

    private static func isUnchanged<T>(_ patch: Patch<T>) -> Bool {
        if case .unchanged = patch { return true }
        return false
    }
}
