import Foundation

/// Failure modes for the OAuth pipeline (sign-in, refresh, revoke).
public enum GoogleOAuthError: Error, Sendable, Equatable {
    /// The Google response was not HTTP-shaped or had an unexpected status.
    case http(statusCode: Int)
    /// The Google response body could not be decoded as the expected JSON
    /// shape. The body is intentionally *not* attached: it may contain
    /// tokens, and the issue forbids logging them anywhere.
    case decodingFailed
    /// The user explicitly cancelled the consent screen.
    case userCancelled
    /// `signIn` succeeded but the Google response was missing fields LifeView
    /// requires (userID, refresh token, email…).
    case incompleteResponse
    /// `validAccessToken` / `loadAccount` was called but no account is
    /// persisted.
    case noAccount
}
