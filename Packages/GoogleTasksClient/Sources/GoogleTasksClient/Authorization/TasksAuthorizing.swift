import Foundation

/// Token-vending seam between ``GoogleTasksClient`` and the auth layer.
///
/// The client never knows about `GoogleAccountStore` (or `GoogleAuth` at
/// all) — it only asks for an access token, and asks for a fresh one when
/// Google answers `401`. The concrete adapter that bridges this protocol
/// onto `GoogleAccountStore` lives in the app target.
///
/// Both methods are async because the auth layer may need to perform a
/// network round-trip (the OAuth refresh flow) to satisfy the request.
public protocol TasksAuthorizing: Sendable {
    /// Returns a currently-valid access token. May refresh transparently
    /// if the cached one is expired.
    func accessToken() async throws -> String

    /// Forces an OAuth refresh and returns the resulting token. Called by
    /// the client at most once per request, after a `401` response, to
    /// recover from server-side token revocation or rotation that the
    /// local clock didn't anticipate.
    func refreshedAccessToken() async throws -> String
}
