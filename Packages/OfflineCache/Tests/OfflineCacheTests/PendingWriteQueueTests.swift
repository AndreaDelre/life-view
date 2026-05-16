import Core
import Foundation
import GoogleAuth
@testable import OfflineCache
import XCTest

final class PendingWriteQueueTests: XCTestCase {
    private let accountA = AccountID("acct-A")
    private let accountB = AccountID("acct-B")

    // MARK: - Round-trip

    func test_enqueueAndRead_roundTripsPayload() async throws {
        let store = try OfflineCacheStore.inMemory()
        let payload = PendingWritePayload.createTask(
            listID: "list-1",
            clientTaskID: "local-1",
            draft: PendingTaskDraft(title: "Buy milk")
        )
        _ = try await store.enqueueWrite(accountID: accountA, payload: payload)
        let queued = try await store.pendingWrites(accountID: accountA)
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.payload, payload)
        XCTAssertEqual(queued.first?.attemptCount, 0)
    }

    func test_enqueue_preservesCreationOrder() async throws {
        let store = try OfflineCacheStore.inMemory()
        let now = Date()
        _ = try await store.enqueueWrite(
            accountID: accountA,
            payload: .completeTask(listID: "l1", taskID: "t1", isCompleted: true),
            at: now
        )
        _ = try await store.enqueueWrite(
            accountID: accountA,
            payload: .completeTask(listID: "l1", taskID: "t2", isCompleted: true),
            at: now.addingTimeInterval(0.5)
        )
        _ = try await store.enqueueWrite(
            accountID: accountA,
            payload: .completeTask(listID: "l1", taskID: "t3", isCompleted: true),
            at: now.addingTimeInterval(1)
        )
        let queued = try await store.pendingWrites(accountID: accountA)
        XCTAssertEqual(queued.map { write -> String in
            if case let .completeTask(_, taskID, _) = write.payload { return taskID }
            return ""
        }, ["t1", "t2", "t3"])
    }

    func test_pendingWrites_scopedByAccount() async throws {
        let store = try OfflineCacheStore.inMemory()
        _ = try await store.enqueueWrite(accountID: accountA, payload: .deleteTask(listID: "l", taskID: "tA"))
        _ = try await store.enqueueWrite(accountID: accountB, payload: .deleteTask(listID: "l", taskID: "tB"))
        let aWrites = try await store.pendingWrites(accountID: accountA)
        let bWrites = try await store.pendingWrites(accountID: accountB)
        XCTAssertEqual(aWrites.count, 1)
        XCTAssertEqual(bWrites.count, 1)
    }

    func test_removeWrite_dropsEntry() async throws {
        let store = try OfflineCacheStore.inMemory()
        let write = try await store.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l", taskID: "t")
        )
        try await store.removeWrite(id: write.id)
        let queued = try await store.pendingWrites(accountID: accountA)
        XCTAssertTrue(queued.isEmpty)
    }

    func test_bumpAttempt_incrementsCounter() async throws {
        let store = try OfflineCacheStore.inMemory()
        let write = try await store.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l", taskID: "t")
        )
        try await store.bumpAttempt(id: write.id)
        try await store.bumpAttempt(id: write.id)
        let queued = try await store.pendingWrites(accountID: accountA)
        XCTAssertEqual(queued.first?.attemptCount, 2)
    }

    // MARK: - Payload encoding

    func test_pendingTaskPatch_roundTripsThroughCore() {
        let original = TaskPatch(
            title: .set("Hello"),
            notes: .clear,
            due: .unchanged,
            status: .set(.completed)
        )
        let pending = PendingTaskPatch(patch: original)
        let restored = pending.asPatch
        XCTAssertEqual(restored, original)
    }

    func test_payload_codable() throws {
        let payloads: [PendingWritePayload] = [
            .createTask(listID: "l", clientTaskID: "c", draft: PendingTaskDraft(title: "T")),
            .updateTask(listID: "l", taskID: "t", patch: PendingTaskPatch(title: .set("New"))),
            .completeTask(listID: "l", taskID: "t", isCompleted: true),
            .deleteTask(listID: "l", taskID: "t"),
            .moveTask(listID: "l", taskID: "t", previousTaskID: "prev"),
            .createList(clientListID: "cl", title: "Lists"),
            .renameList(listID: "l", title: "Renamed"),
            .deleteList(listID: "l")
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for payload in payloads {
            let data = try encoder.encode(payload)
            let decoded = try decoder.decode(PendingWritePayload.self, from: data)
            XCTAssertEqual(decoded, payload)
        }
    }
}
