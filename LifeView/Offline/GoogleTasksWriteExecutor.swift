import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
import OfflineCache

/// Concrete ``PendingWriteExecutor`` that bridges the persistent queue
/// to the live ``GoogleTasksClient`` for the account at hand.
///
/// Routes via the same ``AccountSessionRegistry`` the read path uses so
/// each replay benefits from the per-account client (and its in-memory
/// cache). Maps every thrown ``GoogleTasksError`` to a typed
/// ``PendingWriteExecutionError`` so the drainer can apply the right
/// retry-vs-drop policy.
///
/// `nonisolated` because the registry's `client(for:)` is `MainActor`,
/// not Sendable — we hop to the main actor inside ``execute`` rather
/// than capturing the registry across actor boundaries.
struct GoogleTasksWriteExecutor: PendingWriteExecutor {
    /// Returns the client for an account on the main actor. The closure
    /// is `Sendable` so it can be stored in this struct.
    let clientLookup: @MainActor @Sendable (AccountID) -> GoogleTasksClient

    func execute(_ write: PendingWrite) async throws {
        let client = await MainActor.run { clientLookup(write.accountID) }
        do {
            try await replay(write.payload, on: client)
        } catch let error as GoogleTasksError {
            throw Self.classify(error)
        } catch {
            // Anything else (cancellation, programming bug, …) is
            // unsafely treated as transient — the drainer's safer
            // default than dropping user data on an unknown error.
            throw PendingWriteExecutionError(
                classification: .transient,
                message: (error as NSError).localizedDescription
            )
        }
    }

    private func replay(_ payload: PendingWritePayload, on client: GoogleTasksClient) async throws {
        switch payload {
        case let .createTask(listID, _, draft):
            _ = try await client.insertTask(in: listID, draft: draft.asDraft)
        case let .updateTask(listID, taskID, patch):
            _ = try await client.updateTask(in: listID, taskID: taskID, patch: patch.asPatch)
        case let .completeTask(listID, taskID, isCompleted):
            let patch = TaskPatch(status: .set(isCompleted ? .completed : .needsAction))
            _ = try await client.updateTask(in: listID, taskID: taskID, patch: patch)
        case let .deleteTask(listID, taskID):
            try await client.deleteTask(in: listID, taskID: taskID)
        case let .moveTask(listID, taskID, previousTaskID):
            _ = try await client.moveTask(in: listID, taskID: taskID, previous: previousTaskID)
        case let .createList(_, title):
            _ = try await client.insertTaskList(title: title)
        case let .renameList(listID, title):
            _ = try await client.renameTaskList(listID: listID, title: title)
        case let .deleteList(listID):
            try await client.deleteTaskList(listID: listID)
        }
    }

    private static func classify(_ error: GoogleTasksError) -> PendingWriteExecutionError {
        switch error {
        case .unauthorized:
            PendingWriteExecutionError(classification: .authentication, message: "unauthorized")
        case let .http(status):
            if (400 ..< 500).contains(status), status != 408, status != 429 {
                PendingWriteExecutionError(classification: .permanent, message: "HTTP \(status)")
            } else {
                PendingWriteExecutionError(classification: .transient, message: "HTTP \(status)")
            }
        case .decodingFailed:
            PendingWriteExecutionError(classification: .permanent, message: "decoding failed")
        case let .transport(message):
            PendingWriteExecutionError(classification: .transient, message: message)
        case .emptyPatch:
            // An empty patch in the queue is a bug, not user data —
            // drop it so the drainer doesn't get stuck.
            PendingWriteExecutionError(classification: .permanent, message: "empty patch")
        }
    }
}
