import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
@testable import LifeView
import OfflineCache
import XCTest

/// Verifies the bridge between the persistent queue and the live
/// ``GoogleTasksClient`` honours the extra ``PendingTaskDraft.status``
/// field that the view-model's "collapse" path stamps on a queued
/// `.createTask` when the user toggles a not-yet-flushed local task.
@MainActor
final class GoogleTasksWriteExecutorTests: XCTestCase {
    private let accountID = AccountID("test-account")
    private let listID = "list-1"

    func testReplayCreateTask_chainsStatusUpdate_whenDraftIsCompleted() async throws {
        let http = StubTasksHTTPClient([
            // The replay calls `insertTask` first — return the
            // server-assigned row.
            .success(
                statusCode: 200,
                body: Data(
                    #"{"id":"server-1","title":"OK","status":"needsAction","position":"p"}"#.utf8
                )
            ),
            // Then a follow-up `updateTask` to flip the status. The
            // executor must issue it because `draft.status == .completed`.
            .success(
                statusCode: 200,
                body: Data(
                    #"{"id":"server-1","title":"OK","status":"completed","position":"p"}"#.utf8
                )
            )
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)
        let executor = GoogleTasksWriteExecutor(clientLookup: { _ in client })

        let write = PendingWrite(
            id: "w1",
            accountID: accountID,
            payload: .createTask(
                listID: listID,
                clientTaskID: "local-1",
                draft: PendingTaskDraft(title: "OK", status: .completed)
            ),
            createdAt: Date(),
            attemptCount: 0
        )
        try await executor.execute(write)

        // Two HTTP calls: POST tasks, then PATCH/PUT tasks/server-1.
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(
            http.requests.last?.url?.absoluteString.contains("server-1"),
            true,
            "follow-up update must target the just-created task"
        )
    }

    func testReplayCreateTask_noFollowUp_whenStatusIsNil() async throws {
        let http = StubTasksHTTPClient([
            .success(
                statusCode: 200,
                body: Data(
                    #"{"id":"server-2","title":"OK","status":"needsAction","position":"p"}"#.utf8
                )
            )
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)
        let executor = GoogleTasksWriteExecutor(clientLookup: { _ in client })

        let write = PendingWrite(
            id: "w2",
            accountID: accountID,
            payload: .createTask(
                listID: listID,
                clientTaskID: "local-2",
                draft: PendingTaskDraft(title: "OK")
            ),
            createdAt: Date(),
            attemptCount: 0
        )
        try await executor.execute(write)
        XCTAssertEqual(http.requests.count, 1, "no follow-up when draft.status is nil")
    }
}
