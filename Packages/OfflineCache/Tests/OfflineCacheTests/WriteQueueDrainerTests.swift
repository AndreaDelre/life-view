import Core
import Foundation
import GoogleAuth
@testable import OfflineCache
import XCTest

final class WriteQueueDrainerTests: XCTestCase {
    private let accountA = AccountID("acct-A")

    // MARK: - Helpers

    /// Executor stub keyed by the `write.id` so individual entries can
    /// be scripted to succeed, fail-transient or fail-permanent.
    private final class StubExecutor: PendingWriteExecutor, @unchecked Sendable {
        enum Outcome {
            case success
            case transient
            case permanent
            case authentication
        }

        private let queue = DispatchQueue(label: "StubExecutor")
        private var scripted: [String: [Outcome]] = [:]
        private var defaultOutcome: Outcome = .success
        private(set) var calls: [String] = []

        func script(_ outcomes: [Outcome], for id: String) {
            queue.sync { scripted[id] = outcomes }
        }

        func setDefault(_ outcome: Outcome) {
            queue.sync { defaultOutcome = outcome }
        }

        func execute(_ write: PendingWrite) async throws {
            let outcome: Outcome = queue.sync {
                calls.append(write.id)
                if var queued = scripted[write.id], !queued.isEmpty {
                    let next = queued.removeFirst()
                    scripted[write.id] = queued
                    return next
                }
                return defaultOutcome
            }
            switch outcome {
            case .success: return
            case .transient:
                throw PendingWriteExecutionError(classification: .transient, message: "boom")
            case .permanent:
                throw PendingWriteExecutionError(classification: .permanent, message: "nope")
            case .authentication:
                throw PendingWriteExecutionError(classification: .authentication, message: "401")
            }
        }
    }

    private struct InstantClock: DrainerClock {
        func sleep(for _: Duration) async throws {}
    }

    // MARK: - Tests

    func test_drain_processesAllInOrder() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let executor = StubExecutor()
        let drainer = WriteQueueDrainer(cache: cache, executor: executor, clock: InstantClock())

        let now = Date()
        for index in 0 ..< 5 {
            _ = try await cache.enqueueWrite(
                accountID: accountA,
                payload: .deleteTask(listID: "l", taskID: "t\(index)"),
                at: now.addingTimeInterval(Double(index))
            )
        }

        let outcome = await drainer.drain(accountID: accountA)
        XCTAssertEqual(outcome, .completed(processed: 5, dropped: 0))
        let remaining = try await cache.pendingWrites(accountID: accountA)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(executor.calls.count, 5)
    }

    func test_drain_droppedOnPermanentError() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let executor = StubExecutor()
        let drainer = WriteQueueDrainer(cache: cache, executor: executor, clock: InstantClock())

        let write = try await cache.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l", taskID: "t1")
        )
        executor.script([.permanent], for: write.id)

        let outcome = await drainer.drain(accountID: accountA)
        XCTAssertEqual(outcome, .completed(processed: 0, dropped: 1))
        let remaining = try await cache.pendingWrites(accountID: accountA)
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_drain_stopsOnAuthError_andKeepsWrite() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let executor = StubExecutor()
        let drainer = WriteQueueDrainer(cache: cache, executor: executor, clock: InstantClock())

        _ = try await cache.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l", taskID: "t1")
        )
        executor.setDefault(.authentication)

        let outcome = await drainer.drain(accountID: accountA)
        XCTAssertEqual(outcome, .stoppedOnAuthentication(processed: 0))
        let remaining = try await cache.pendingWrites(accountID: accountA)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.attemptCount, 1)
    }

    func test_drain_retriesTransientThenSucceeds() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let executor = StubExecutor()
        let drainer = WriteQueueDrainer(cache: cache, executor: executor, clock: InstantClock())

        let write = try await cache.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l", taskID: "t1")
        )
        executor.script([.transient, .transient, .success], for: write.id)

        let outcome = await drainer.drain(accountID: accountA)
        XCTAssertEqual(outcome, .completed(processed: 1, dropped: 0))
        let remaining = try await cache.pendingWrites(accountID: accountA)
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_drain_doublePassIsIdempotent() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let executor = StubExecutor()
        let drainer = WriteQueueDrainer(cache: cache, executor: executor, clock: InstantClock())

        _ = try await cache.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l", taskID: "t1")
        )
        _ = await drainer.drain(accountID: accountA)
        // Replaying the drain on an empty queue is a no-op completion.
        let outcome = await drainer.drain(accountID: accountA)
        XCTAssertEqual(outcome, .completed(processed: 0, dropped: 0))
    }

    func test_drain_concurrentCallsAreCoalesced() async throws {
        let cache = try OfflineCacheStore.inMemory()
        let executor = StubExecutor()
        let drainer = WriteQueueDrainer(cache: cache, executor: executor, clock: InstantClock())
        // Locally-scoped Sendable copy so the async-let captures stay
        // off `self` (XCTestCase is not Sendable).
        let account = accountA

        _ = try await cache.enqueueWrite(
            accountID: account,
            payload: .deleteTask(listID: "l", taskID: "t1")
        )

        async let first = drainer.drain(accountID: account)
        async let second = drainer.drain(accountID: account)
        let results = await [first, second]
        // Exactly one of the two saw the queue work; the other was
        // coalesced into a "already draining" no-op.
        let completed = results.filter { $0 == .completed(processed: 1, dropped: 0) }.count
        let skipped = results.filter { $0 == .skippedAlreadyDraining }.count
        XCTAssertEqual(completed + skipped, 2)
        XCTAssertEqual(completed, 1)
    }
}
