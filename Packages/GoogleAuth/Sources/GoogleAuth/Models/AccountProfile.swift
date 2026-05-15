import Foundation

/// Minimal user-facing profile shown in the panel header.
///
/// Intentionally narrow: only the fields LifeView renders, plus the Google
/// `subject` (OpenID `sub`) which is never displayed but is the only stable
/// way to recognise that an OAuth flow returned an account the user has
/// already connected — and therefore to update tokens in place rather than
/// creating a duplicate row in the multi-account list.
///
/// `subject` is optional because legacy mono-account profiles (P2) did not
/// store it separately: the ``AccountID`` *was* the subject. The migration
/// to P4 backfills the field from that legacy id, but we keep the type
/// optional in case a future test fixture or sign-in path produces a
/// profile without it.
public struct AccountProfile: Sendable, Codable, Equatable {
    public let subject: String?
    public let email: String
    public var displayName: String?
    public let avatarURL: URL?

    public init(
        subject: String?,
        email: String,
        displayName: String?,
        avatarURL: URL?
    ) {
        self.subject = subject
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}
