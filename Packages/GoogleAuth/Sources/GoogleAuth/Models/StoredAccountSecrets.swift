import Foundation

/// Internal blob persisted in the Keychain for a given ``AccountID``.
///
/// Keeping profile and tokens in a single Keychain item (one
/// `kSecAttrAccount = accountID` entry) means a single atomic read/write per
/// account and matches the schema described in issue #3.
struct StoredAccountSecrets: Codable, Sendable, Equatable {
    let profile: AccountProfile
    var tokens: TokenSet
}
