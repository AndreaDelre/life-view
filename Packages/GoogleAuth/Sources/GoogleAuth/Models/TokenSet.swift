import Foundation

/// OAuth credentials for a single Google account.
///
/// `description` / `debugDescription` are intentionally redacted so the type
/// is safe to print, log, or include in error messages: the issue explicitly
/// forbids leaking tokens.
public struct TokenSet: Sendable, Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresAt: Date

    public init(accessToken: String, refreshToken: String, accessTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    /// Returns `true` when the access token is expired or about to expire.
    ///
    /// `safetyMargin` lets callers refresh slightly ahead of the real expiry
    /// to avoid losing a race against in-flight HTTP requests. 60 s mirrors
    /// what most Google SDKs use as the default skew.
    public func isAccessTokenExpired(now: Date = Date(), safetyMargin: TimeInterval = 60) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) <= safetyMargin
    }
}

extension TokenSet: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "TokenSet(<redacted>)" }
    public var debugDescription: String { "TokenSet(<redacted>)" }
}
