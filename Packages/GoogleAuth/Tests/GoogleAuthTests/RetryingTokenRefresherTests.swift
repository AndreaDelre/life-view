import XCTest
@testable import GoogleAuth

final class RetryingTokenRefresherTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func token() -> RefreshedAccessToken {
        RefreshedAccessToken(accessToken: "fresh", expiresAt: now.addingTimeInterval(3_600))
    }

    func testReturnsImmediatelyOnSuccess() async throws {
        let inner = StubTokenRefresher(.success(token()))
        let recorder = SleepRecorder()
        let refresher = RetryingTokenRefresher(
            wrapping: inner,
            maxAttempts: 3,
            baseDelay: .milliseconds(10),
            sleeper: recorder.sleep(_:)
        )

        let result = try await refresher.refresh(refreshToken: "r")

        XCTAssertEqual(result.accessToken, "fresh")
        XCTAssertEqual(inner.calls.count, 1)
        XCTAssertEqual(recorder.delays, [], "no sleep on first-try success")
    }

    func testRetriesOnTransientHTTPThenSucceeds() async throws {
        let inner = StubTokenRefresher(responses: [
            .failure(GoogleOAuthError.http(statusCode: 503)),
            .failure(GoogleOAuthError.http(statusCode: 502)),
            .success(token())
        ])
        let recorder = SleepRecorder()
        let refresher = RetryingTokenRefresher(
            wrapping: inner,
            maxAttempts: 4,
            baseDelay: .milliseconds(10),
            sleeper: recorder.sleep(_:)
        )

        let result = try await refresher.refresh(refreshToken: "r")

        XCTAssertEqual(result.accessToken, "fresh")
        XCTAssertEqual(inner.calls.count, 3)
        // 10ms, then 20ms — exponential, base * 2^(attempt-1).
        XCTAssertEqual(recorder.delays, [.milliseconds(10), .milliseconds(20)])
    }

    func testSurfaces4xxImmediately() async throws {
        let inner = StubTokenRefresher(.failure(GoogleOAuthError.http(statusCode: 401)))
        let recorder = SleepRecorder()
        let refresher = RetryingTokenRefresher(
            wrapping: inner,
            maxAttempts: 3,
            baseDelay: .milliseconds(10),
            sleeper: recorder.sleep(_:)
        )

        do {
            _ = try await refresher.refresh(refreshToken: "r")
            XCTFail("expected error")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .http(statusCode: 401))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(inner.calls.count, 1, "4xx must not retry")
        XCTAssertEqual(recorder.delays, [])
    }

    func testGivesUpAfterMaxAttempts() async throws {
        let inner = StubTokenRefresher(.failure(GoogleOAuthError.http(statusCode: 500)))
        let recorder = SleepRecorder()
        let refresher = RetryingTokenRefresher(
            wrapping: inner,
            maxAttempts: 3,
            baseDelay: .milliseconds(10),
            sleeper: recorder.sleep(_:)
        )

        do {
            _ = try await refresher.refresh(refreshToken: "r")
            XCTFail("expected error")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .http(statusCode: 500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(inner.calls.count, 3)
        XCTAssertEqual(recorder.delays.count, 2, "N-1 sleeps for N attempts")
    }

    func testTransportErrorIsTreatedAsTransient() async throws {
        struct DummyError: Error {}
        let inner = StubTokenRefresher(responses: [
            .failure(DummyError()),
            .success(token())
        ])
        let recorder = SleepRecorder()
        let refresher = RetryingTokenRefresher(
            wrapping: inner,
            maxAttempts: 3,
            baseDelay: .milliseconds(10),
            sleeper: recorder.sleep(_:)
        )

        let result = try await refresher.refresh(refreshToken: "r")
        XCTAssertEqual(result.accessToken, "fresh")
        XCTAssertEqual(inner.calls.count, 2)
    }
}

/// Records sleep durations rather than actually waiting — keeps tests fast
/// and deterministic.
private final class SleepRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SleepRecorder")
    private var _delays: [Duration] = []

    var delays: [Duration] { queue.sync { _delays } }

    func sleep(_ duration: Duration) async throws {
        queue.sync { _delays.append(duration) }
    }
}
