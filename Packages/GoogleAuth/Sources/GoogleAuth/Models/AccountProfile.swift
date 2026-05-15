import Foundation

/// Minimal user-facing profile shown in the panel header.
///
/// Intentionally narrow: only the fields LifeView renders. Anything else
/// (locale, verified email, etc.) lives on the raw Google response and is
/// discarded at the parse boundary.
public struct AccountProfile: Sendable, Codable, Equatable {
    public let email: String
    public let displayName: String?
    public let avatarURL: URL?

    public init(email: String, displayName: String?, avatarURL: URL?) {
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}
