import Core
import Foundation
import GoogleAuth
import GoogleTasksClient

/// P5 write API: optimistic local mutation + serial per-account write
/// queue + rollback on failure. Implemented as an extension in its own
/// file so ``TasksViewModel`` stays under the SwiftLint per-file and
/// per-type body length budgets — the rest of the view-model is the
/// already-substantial P3/P4 read path.
///
/// Every mutation follows the same shape:
///
/// 1. Validate inputs / required state. Bail out silently when the
///    pre-conditions don't hold (e.g. mutating a `local-` ID before the
///    server has assigned a real one).
/// 2. Capture the pre-mutation task so a rollback knows what to restore.
/// 3. Apply the optimistic change via ``TasksViewModel/mutateTaskList``.
/// 4. Enqueue the network call on ``writeQueue`` keyed by `accountID`
///    so concurrent edits to the same account run in order.
/// 5. On success, swap the optimistic row for the server's canonical
///    representation. On failure, restore the pre-mutation task and
///    surface a localised message via ``lastError``.
extension TasksViewModel {
    /// True while a mutation for `taskID` is in flight. Views read this
    /// to render a pending indicator. A task whose ID starts with
    /// `local-` is always pending (creation hasn't yet returned).
    func isPending(taskID: String) -> Bool {
        pendingTaskIDs.contains(taskID)
    }

    /// Clears the latest mutation error after the toast has shown it.
    func dismissError() {
        lastError = nil
    }

    /// Creates a new task in the currently-selected list. Single mode
    /// only — aggregated mode does not have a target list, by design.
    /// Returns `false` when not in single mode, when no list is
    /// selected, or when `title` is empty after trimming.
    @discardableResult
    func createTask(title: String, due: Date? = nil) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard case let .single(accountID) = selection else { return false }
        guard case let .singleLoaded(payload) = state,
              let listID = payload.selectedListID else { return false }

        let draft = TaskDraft(title: trimmed, notes: nil, due: due)
        // Sentinel ID prefix used so the UI can distinguish a pending
        // local insert (whose ID is not yet a server ID) from a synced
        // task. The empty `position` sorts the optimistic row above
        // every server-assigned position string.
        let localID = "local-" + UUID().uuidString
        let optimistic = TaskItem(
            id: localID,
            title: trimmed,
            notes: nil,
            status: .needsAction,
            due: due,
            position: ""
        )

        mutateTaskList(accountID: accountID, listID: listID) { items in
            items.insert(optimistic, at: 0)
        }
        pendingTaskIDs.insert(localID)

        let client = sessions.client(for: accountID)
        let queue = writeQueue
        Task { @MainActor [weak self] in
            do {
                let inserted = try await queue.enqueue(for: accountID) {
                    try await client.insertTask(in: listID, draft: draft)
                }
                guard let self else { return }
                pendingTaskIDs.remove(localID)
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    if let idx = items.firstIndex(where: { $0.id == localID }) {
                        items[idx] = inserted
                        items.sort { $0.position < $1.position }
                    }
                }
            } catch {
                guard let self else { return }
                pendingTaskIDs.remove(localID)
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    items.removeAll { $0.id == localID }
                }
                lastError = Self.messageFor(error)
            }
        }
        return true
    }

    /// Toggles a task's completion. Optimistically updates the local
    /// state; on failure, the task is restored to its pre-mutation
    /// state and ``lastError`` is set.
    func setCompletion(
        _ isCompleted: Bool,
        for taskID: String,
        in listID: String,
        account accountID: AccountID
    ) {
        // Pending local inserts can't be toggled until the server has
        // assigned them a real ID — keep the UI for that operation
        // simple by silently ignoring.
        guard !taskID.hasPrefix("local-") else { return }

        var beforeTask: TaskItem?
        let hideOnComplete = !showsCompleted
        mutateTaskList(accountID: accountID, listID: listID) { items in
            guard let idx = items.firstIndex(where: { $0.id == taskID }) else { return }
            beforeTask = items[idx]
            items[idx].status = isCompleted ? .completed : .needsAction
            // Match the user's "afficher complétées" preference: a task
            // ticked-complete in needsAction-only view should disappear.
            if hideOnComplete, isCompleted {
                items.remove(at: idx)
            }
        }
        guard let beforeTask else { return }

        pendingTaskIDs.insert(taskID)
        enqueueTaskPatch(
            patch: TaskPatch(status: .set(isCompleted ? .completed : .needsAction)),
            taskID: taskID,
            listID: listID,
            accountID: accountID,
            originalTask: beforeTask
        )
    }

    /// Renames a task (inline edit). No-op if the trimmed title is
    /// empty or unchanged.
    func editTaskTitle(
        _ newTitle: String,
        for taskID: String,
        in listID: String,
        account accountID: AccountID
    ) {
        guard !taskID.hasPrefix("local-") else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var beforeTask: TaskItem?
        var didChange = false
        mutateTaskList(accountID: accountID, listID: listID) { items in
            guard let idx = items.firstIndex(where: { $0.id == taskID }) else { return }
            beforeTask = items[idx]
            guard items[idx].title != trimmed else { return }
            items[idx].title = trimmed
            didChange = true
        }
        guard didChange, let beforeTask else { return }

        pendingTaskIDs.insert(taskID)
        enqueueTaskPatch(
            patch: TaskPatch(title: .set(trimmed)),
            taskID: taskID,
            listID: listID,
            accountID: accountID,
            originalTask: beforeTask
        )
    }

    /// Deletes a task. The row vanishes immediately; on failure it
    /// reappears at its original position and ``lastError`` is set.
    func deleteTask(taskID: String, in listID: String, account accountID: AccountID) {
        guard !taskID.hasPrefix("local-") else { return }

        var beforeTask: TaskItem?
        var beforeIndex: Int?
        mutateTaskList(accountID: accountID, listID: listID) { items in
            guard let idx = items.firstIndex(where: { $0.id == taskID }) else { return }
            beforeTask = items[idx]
            beforeIndex = idx
            items.remove(at: idx)
        }
        guard let beforeTask, let beforeIndex else { return }

        let client = sessions.client(for: accountID)
        let queue = writeQueue
        Task { @MainActor [weak self] in
            do {
                try await queue.enqueue(for: accountID) {
                    try await client.deleteTask(in: listID, taskID: taskID)
                }
                // Optimistic remove already applied; nothing to do.
            } catch {
                guard let self else { return }
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    let insertAt = min(beforeIndex, items.count)
                    items.insert(beforeTask, at: insertAt)
                    items.sort { $0.position < $1.position }
                }
                lastError = Self.messageFor(error)
            }
        }
    }

    /// Reorders a task to `newIndex` within `listID` (single-mode drag &
    /// drop). Applies the move optimistically — the local array is
    /// reordered immediately and views animate the swap — then enqueues
    /// a `POST .../tasks/move` keyed by `accountID`. On failure the
    /// original order is restored and ``lastError`` is set.
    ///
    /// `newIndex` follows the same convention as `IndexSet.onMove`'s
    /// destination: it is the index that the *moved* task occupies in
    /// the new array. The previous-sibling sent to Google is read off
    /// the mutated array (`newIndex - 1`) so we don't have to reason
    /// about whether the user dragged up or down — that's the whole
    /// pitch of doing the local mutation first.
    ///
    /// Notes on local ordering & `position`:
    /// The local source of truth for sort order after a drag is the
    /// array index, not ``TaskItem/position`` — Google assigns new
    /// position strings server-side, and the next ``refresh()`` will
    /// re-sync them. Until then we deliberately let the array order
    /// drift away from the (stale) position strings: re-sorting locally
    /// would undo the user's drag.
    func moveTask(
        from sourceIndex: Int,
        to newIndex: Int,
        in listID: String,
        account accountID: AccountID
    ) {
        // Capture pre-mutation order for rollback. The optimistic move
        // is applied through `mutateTaskList`, then we read the new
        // neighbour off the mutated array.
        var beforeOrder: [TaskItem]?
        var movedTaskID: String?
        var previousID: String?
        var resolvedNewIndex: Int?

        mutateTaskList(accountID: accountID, listID: listID) { items in
            guard sourceIndex >= 0, sourceIndex < items.count else { return }
            beforeOrder = items
            let moved = items.remove(at: sourceIndex)
            // `IndexSet.onMove` hands a destination computed against the
            // *original* array: a drop just after the item at position N
            // arrives as `newIndex == N + 1`. Once we've removed the
            // dragged row, the insertion index for items dropped further
            // down has to be shifted by one. Clamp at both ends to be
            // safe against an out-of-range destination.
            let target: Int
            if newIndex > sourceIndex {
                target = max(0, min(items.count, newIndex - 1))
            } else {
                target = max(0, min(items.count, newIndex))
            }
            items.insert(moved, at: target)
            movedTaskID = moved.id
            resolvedNewIndex = target
            previousID = target == 0 ? nil : items[target - 1].id
        }

        guard let beforeOrder, let movedTaskID, let resolvedNewIndex else { return }
        // No-op moves (drop on the same spot) avoid a needless network
        // call — Google would happily accept it but the round-trip is
        // wasted work.
        guard resolvedNewIndex != sourceIndex else { return }
        // Pending local inserts can't be moved server-side until they've
        // been assigned a real ID. Rollback the optimistic reorder so
        // the user's drag is silently undone rather than appearing to
        // succeed and then snapping back on refresh.
        guard !movedTaskID.hasPrefix("local-") else {
            mutateTaskList(accountID: accountID, listID: listID) { items in
                items = beforeOrder
            }
            return
        }

        pendingTaskIDs.insert(movedTaskID)
        let client = sessions.client(for: accountID)
        let queue = writeQueue
        let capturedPrevious = previousID
        Task { @MainActor [weak self] in
            do {
                let moved = try await queue.enqueue(for: accountID) {
                    try await client.moveTask(
                        in: listID,
                        taskID: movedTaskID,
                        previous: capturedPrevious
                    )
                }
                guard let self else { return }
                pendingTaskIDs.remove(movedTaskID)
                // Patch the moved row in-place with the server's
                // canonical representation (its `position` is now
                // up-to-date) without re-sorting: the user-driven
                // array order is the source of truth here.
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    if let idx = items.firstIndex(where: { $0.id == movedTaskID }) {
                        items[idx] = moved
                    }
                }
            } catch {
                guard let self else { return }
                pendingTaskIDs.remove(movedTaskID)
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    items = beforeOrder
                }
                lastError = Self.messageFor(error)
            }
        }
    }

    // MARK: - Lists

    /// Creates a new task list under the currently-selected account.
    /// Single mode only — aggregated mode does not have a target
    /// account when triggered from the panel header. Returns `false`
    /// when out of single mode or `title` is empty after trimming.
    @discardableResult
    func createList(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard case let .single(accountID) = selection else { return false }
        guard case .singleLoaded = state else { return false }

        // Sentinel ID prefix: views key off the "local-list-" prefix to
        // disable rename/delete/select on a list whose server ID is not
        // yet known.
        let localID = "local-list-" + UUID().uuidString
        let optimistic = TaskList(id: localID, title: trimmed, updatedAt: Date())

        mutateAccountLists(accountID: accountID) { lists in
            lists.append(optimistic)
        }

        let client = sessions.client(for: accountID)
        let queue = writeQueue
        Task { @MainActor [weak self] in
            do {
                let inserted = try await queue.enqueue(for: accountID) {
                    try await client.insertTaskList(title: trimmed)
                }
                guard let self else { return }
                mutateAccountLists(accountID: accountID) { lists in
                    if let idx = lists.firstIndex(where: { $0.id == localID }) {
                        lists[idx] = inserted
                    }
                }
            } catch {
                guard let self else { return }
                mutateAccountLists(accountID: accountID) { lists in
                    lists.removeAll { $0.id == localID }
                }
                lastError = Self.messageFor(error)
            }
        }
        return true
    }

    /// Renames a list. No-op on a pending local insert (the server has
    /// not assigned an ID yet) or when the trimmed title is empty /
    /// unchanged.
    func renameList(listID: String, to newTitle: String, account accountID: AccountID) {
        guard !listID.hasPrefix("local-list-") else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var beforeList: TaskList?
        mutateAccountLists(accountID: accountID) { lists in
            guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
            beforeList = lists[idx]
            lists[idx].title = trimmed
        }
        guard let beforeList, beforeList.title != trimmed else { return }

        let client = sessions.client(for: accountID)
        let queue = writeQueue
        Task { @MainActor [weak self] in
            do {
                let renamed = try await queue.enqueue(for: accountID) {
                    try await client.renameTaskList(listID: listID, title: trimmed)
                }
                guard let self else { return }
                mutateAccountLists(accountID: accountID) { lists in
                    if let idx = lists.firstIndex(where: { $0.id == listID }) {
                        lists[idx] = renamed
                    }
                }
            } catch {
                guard let self else { return }
                mutateAccountLists(accountID: accountID) { lists in
                    if let idx = lists.firstIndex(where: { $0.id == listID }) {
                        lists[idx] = beforeList
                    }
                }
                lastError = Self.messageFor(error)
            }
        }
    }

    /// Deletes a list (and cascades every task it contains). On
    /// failure the list is restored to its original index — but note
    /// that the *tasks* inside it stay gone locally until the next
    /// reload re-fetches them from Google.
    func deleteList(listID: String, account accountID: AccountID) {
        guard !listID.hasPrefix("local-list-") else { return }

        var beforeList: TaskList?
        var beforeIndex: Int?
        mutateAccountLists(accountID: accountID) { lists in
            guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
            beforeList = lists[idx]
            beforeIndex = idx
            lists.remove(at: idx)
        }
        guard let beforeList, let beforeIndex else { return }

        let client = sessions.client(for: accountID)
        let queue = writeQueue
        Task { @MainActor [weak self] in
            do {
                try await queue.enqueue(for: accountID) {
                    try await client.deleteTaskList(listID: listID)
                }
            } catch {
                guard let self else { return }
                mutateAccountLists(accountID: accountID) { lists in
                    let insertAt = min(beforeIndex, lists.count)
                    lists.insert(beforeList, at: insertAt)
                }
                lastError = Self.messageFor(error)
            }
        }
    }

    // MARK: - Mutations — internals

    private func enqueueTaskPatch(
        patch: TaskPatch,
        taskID: String,
        listID: String,
        accountID: AccountID,
        originalTask: TaskItem
    ) {
        let client = sessions.client(for: accountID)
        let queue = writeQueue
        let showsCompletedAtCall = showsCompleted
        Task { @MainActor [weak self] in
            do {
                let updated = try await queue.enqueue(for: accountID) {
                    try await client.updateTask(in: listID, taskID: taskID, patch: patch)
                }
                guard let self else { return }
                pendingTaskIDs.remove(taskID)
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    if let idx = items.firstIndex(where: { $0.id == taskID }) {
                        items[idx] = updated
                    } else if showsCompletedAtCall || updated.status == .needsAction {
                        // Task had been hidden by an optimistic toggle but
                        // ended up in a view that should display it — put
                        // it back in position order.
                        items.append(updated)
                        items.sort { $0.position < $1.position }
                    }
                }
            } catch {
                guard let self else { return }
                pendingTaskIDs.remove(taskID)
                mutateTaskList(accountID: accountID, listID: listID) { items in
                    if let idx = items.firstIndex(where: { $0.id == taskID }) {
                        items[idx] = originalTask
                    } else {
                        items.append(originalTask)
                        items.sort { $0.position < $1.position }
                    }
                }
                lastError = Self.messageFor(error)
            }
        }
    }
}
