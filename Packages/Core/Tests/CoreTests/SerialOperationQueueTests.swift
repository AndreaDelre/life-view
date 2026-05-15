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

        async let first = queue.enqueue(for: "k") {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await recorder.append("a")
            return "a"
        }
        async let second = queue.enqueue(for: "k") {
            await recorder.append("b")
            return "b"
        }

        _ = try await (first, second)

        let log = await recorder.snapshot()
        XCTAssertEqual(log, ["a", "b"], "second op must wait for first despite being faster")
    }

    func testKeysAreIndependent() async throws {
        // Two long ops on the same key would serialise; on different
        // keys they should overlap. We assert overlap by checking the
        // wall-clock time is closer to one op duration than two.
        let queue = SerialOperationQueue<String>()
        let opDuration: UInt64 = 100_000_000 // 100ms

        let start = Date()
        async let opA = queue.enqueue(for: "A") {
            try? await Task.sleep(nanoseconds: opDuration)
        }
        async let opB = queue.enqueue(for: "B") {
            try? await Task.sleep(nanoseconds: opDuration)
        }
        _ = try await (opA, opB)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.18, "different-key ops must run in parallel (≈100ms each)")
    }

    func testFailingOperationDoesNotBreakChain() async throws {
        let queue = SerialOperationQueue<String>()
        let recorder = OrderRecorder()

        async let first: Void = {
            do {
                try await queue.enqueue(for: "k") {
                    await recorder.append("a-start")
                    throw SampleError.boom
                } as Void
            } catch {
                await recorder.append("a-failed")
            }
        }()
        async let second = queue.enqueue(for: "k") {
            await recorder.append("b")
            return "b"
        }

        _ = try await (first, second)

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
}
