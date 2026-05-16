import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
import OfflineCache

/// P5 list-CRUD: same optimistic + per-account write-queue + rollback
/// shape as the task-CRUD in ``TasksViewModel+Mutations``. Extracted
/// to its own extension file so the main mutations file stays under
/// the SwiftLint per-file budget.
extension TasksViewModel {
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
                persistListUpsert(inserted, accountID: accountID)
            } catch {
                guard let self else { return }
                if Self.isTransportFailure(error) {
                    enqueuePending(
                        .createList(clientListID: localID, title: trimmed),
                        accountID: accountID
                    )
                    return
                }
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
                persistListUpsert(renamed, accountID: accountID)
            } catch {
                guard let self else { return }
                if Self.isTransportFailure(error) {
                    enqueuePending(.renameList(listID: listID, title: trimmed), accountID: accountID)
                    return
                }
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
                guard let self else { return }
                persistListDelete(listID: listID, accountID: accountID)
            } catch {
                guard let self else { return }
                if Self.isTransportFailure(error) {
                    enqueuePending(.deleteList(listID: listID), accountID: accountID)
                    return
                }
                mutateAccountLists(accountID: accountID) { lists in
                    let insertAt = min(beforeIndex, lists.count)
                    lists.insert(beforeList, at: insertAt)
                }
                lastError = Self.messageFor(error)
            }
        }
    }
}
