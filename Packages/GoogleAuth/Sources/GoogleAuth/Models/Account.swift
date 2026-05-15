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
}
