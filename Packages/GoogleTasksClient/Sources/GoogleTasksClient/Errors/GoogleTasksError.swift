import Foundation

/// Public error surface of ``GoogleTasksClient``.
///
/// Intentionally narrow — UI code maps these to localized messages and we
/// don't want to leak Google's internal error shape (which includes URLs,
/// retry hints, and sometimes user-identifying data).
public enum GoogleTasksError: Error, Sendable, Equatable {
    /// Google answered `401 Unauthorized` even after a forced refresh.
    /// Typically means the user revoked the grant from their Google
    /// account or the refresh token itself is no longer valid — either
    /// way, the right reaction in the UI is to send the user back through
    /// the sign-in flow.
    case unauthorized
    /// Any other non-2xx HTTP status.
    case http(statusCode: Int)
    /// JSON body did not decode as the expected shape.
    case decodingFailed
    /// Transport-level failure (DNS, TLS, connectivity…). The message is
    /// safe to surface but does not include user data.
    case transport(message: String)
    /// A mutation was requested with no fields to change. The view-model
    /// short-circuits empty patches; this guards against bugs where an
    /// empty patch reaches the client (which Google would reject with
    /// `400 Bad Request` anyway).
    case emptyPatch
}
