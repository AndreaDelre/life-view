import Foundation

/// Public-facing account aggregate: identity + profile.
///
/// Tokens are *not* part of `Account` on purpose. They live in the Keychain
/// behind ``GoogleAccountStore``, never crossing into UI state. This keeps
/// the view layer trivially `Sendable` and incapable of leaking secrets.
public struct Account: Sendable, Equatable, Identifiable {
    public let id: AccountID
    public var profile: AccountProfile

    public init(id: AccountID, profile: AccountProfile) {
        self.id = id
        self.profile = profile
    }

    /// Convenience accessor for the Google OpenID `subject`, the only field
    /// stable enough to dedupe accounts across re-connects. Optional so
    /// legacy profiles that predate the field still type-check.
    public var subject: String? { profile.subject }
}
