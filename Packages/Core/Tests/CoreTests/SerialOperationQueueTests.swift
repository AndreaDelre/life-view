@testable import Core
import XCTest

final class SerialOperationQueueTests: XCTestCase {
    func testReturnsOperationResult() async throws {
        let queue = SerialOperationQueue<String>()
        let value = try await queue.enqueue(for: "k") { 42 }
        XCTAssertEqual(value, 42)
    }

    func testPropagatesOperationError() async {
        let queue = SerialOperationQueue<String>()
        do {
            _ = try await queue.enqueue(for: "k") {
                throw SampleError.boom
            } as Void
            XCTFail("expected throw")
        } catch SampleError.boom {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSerialisesSameKeyInFIFOOrder() async throws {
        let queue = SerialOperationQueue<String>()
        let recorder = OrderRecorder()
        // Barrier: the first op signals once it has actually started.
        // The test only enqueues the second op after that signal, so
        // the queue's `tails[key]` is guaranteed to be populated and
        // the second op chains behind. Without this, `async let` does
        // not commit to a Task-start order, and the second op can win
        // the actor entry race.
        let started = AsyncStream<Void>.makeStream()

        let firstTask: Task<String, Error> = Task {
            try await queue.enqueue(for: "k") {
                await recorder.append("a-start")
                started.continuation.yield(())
                started.continuation.finish()
                try? await Task.sleep(nanoseconds: 50_000_000)
                await recorder.append("a-end")
                return "a"
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()

        let second = try await queue.enqueue(for: "k") {
            await recorder.append("b")
            return "b"
        }
        let first = try await firstTask.value
        XCTAssertEqual(first, "a")
        XCTAssertEqual(second, "b")

        let log = await recorder.snapshot()
        XCTAssertEqual(log, ["a-start", "a-end", "b"], "second op must wait for first to finish")
    }

    func testKeysAreIndependent() async {
        // If different-key ops were serialised, the second op's body
        // would never run while the first holds the chain. Both ops
        // here wait on a two-party barrier — they can only complete
        // if scheduled concurrently. Race against a watchdog timeout
        // so a regression surfaces as a clean assertion failure
        // instead of a hung test runner.
        //
        // Avoids the earlier wall-clock comparison which flaked on
        // slower CI runners where scheduling overhead pushed
        // "parallel" elapsed past the threshold.
        let queue = SerialOperationQueue<String>()
        let barrier = TwoPartyBarrier()

        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    async let aDone: Void = queue.enqueue(for: "A") { await barrier.arriveAndWait() }
                    async let bDone: Void = queue.enqueue(for: "B") { await barrier.arriveAndWait() }
                    _ = try await (aDone, bDone)
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        XCTAssertTrue(completed, "different-key ops must run concurrently; the barrier would deadlock otherwise")
    }

    func testFailingOperationDoesNotBreakChain() async throws {
        let queue = SerialOperationQueue<String>()
        let recorder = OrderRecorder()

        // Op A throws — await it sequentially so the tail is set to a
        // completed-with-failure wrapper before op B is submitted.
        do {
            try await queue.enqueue(for: "k") {
                await recorder.append("a-start")
                throw SampleError.boom
            } as Void
        } catch {
            await recorder.append("a-failed")
        }

        // Op B must still run despite the predecessor having thrown.
        // If the failure had poisoned the chain, this `await` would
        // either throw or never resume.
        let result = try await queue.enqueue(for: "k") {
            await recorder.append("b")
            return "b"
        }
        XCTAssertEqual(result, "b")

        let log = await recorder.snapshot()
        XCTAssertEqual(log, ["a-start", "a-failed", "b"], "subsequent op must still run after a failure")
    }

    // MARK: - Support

    private enum SampleError: Error { case boom }

    private actor OrderRecorder {
        private var log: [String] = []
        func append(_ entry: String) {
            log.append(entry)
        }

        func snapshot() -> [String] {
            log
        }
    }

    /// 2-party rendezvous: each caller blocks in `arriveAndWait`
    /// until two parties have arrived, at which point both resume.
    /// Used by ``testKeysAreIndependent`` to assert non-serial
    /// scheduling without relying on wall-clock timing.
    private actor TwoPartyBarrier {
        private var arrived = 0
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func arriveAndWait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                continuations.append(continuation)
                arrived += 1
                guard arrived >= 2 else { return }
                let toResume = continuations
                continuations.removeAll()
                for resumer in toResume {
                    resumer.resume()
                }
            }
        }
    }
}
