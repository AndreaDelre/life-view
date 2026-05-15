import Foundation

/// Wraps another ``TokenRefreshing`` with an exponential-backoff retry loop
/// on **transient** failures only (HTTP 5xx + network/transport errors).
///
/// Permanent errors — primarily HTTP 4xx, which on the refresh endpoint
/// means the refresh token has been revoked or invalidated server-side —
/// surface immediately. Retrying those would only delay the moment we
/// kick the user back to a sign-in prompt.
///
/// The wrapper is stateless: each call runs its own retry loop, which
/// is the property the issue calls out as "refresh indépendant par
/// compte" — N accounts hitting the wrapper concurrently each get their
/// own independent timing.
public struct RetryingTokenRefresher: TokenRefreshing {
    private let inner: TokenRefreshing
    private let maxAttempts: Int
    private let baseDelay: Duration
    private let sleeper: @Sendable (Duration) async throws -> Void

    public init(
        wrapping inner: TokenRefreshing,
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(500),
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        precondition(maxAttempts >= 1, "maxAttempts must be at least 1")
        self.inner = inner
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.sleeper = sleeper
    }

    public func refresh(refreshToken: String) async throws -> RefreshedAccessToken {
        var attempt = 1
        while true {
            do {
                return try await inner.refresh(refreshToken: refreshToken)
            } catch {
                guard Self.isTransient(error), attempt < maxAttempts else {
                    throw error
                }
                // Exponential: base * 2^(attempt-1), so 500ms, 1s, 2s…
                let delay = baseDelay * (1 << (attempt - 1))
                try await sleeper(delay)
                attempt += 1
            }
        }
    }

    /// 5xx = "Google blipped, try again". 4xx = "token's dead, stop trying".
    /// Anything not ``GoogleOAuthError`` is treated as a transport blip —
    /// `URLSession` surfacing a connection drop, a DNS failure, etc. —
    /// which is also worth retrying.
    private static func isTransient(_ error: Error) -> Bool {
        guard let oauth = error as? GoogleOAuthError else { return true }
        switch oauth {
        case .http(let status):
            return (500..<600).contains(status)
        case .decodingFailed:
            // The server answered with HTTP success but a body we don't
            // recognise. Treat as a temporary glitch — Google rolling out
            // a bad response shape is plausible and retrying costs ms.
            return true
        case .userCancelled, .incompleteResponse, .noAccount:
            return false
        }
    }
}
