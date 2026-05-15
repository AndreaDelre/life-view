import Foundation

/// Stable, **local** identifier for an account record.
///
/// Backed by a locally-generated UUID — *not* the Google ``sub`` claim. Keeping
/// the id non-PII and process-local matters for multi-account: it survives a
/// user revoking access from `myaccount.google.com` and re-granting it (which
/// keeps the same `sub`), without us carrying around a Google-side identifier
/// in our own data model. The Google subject is preserved separately on
/// ``AccountProfile/subject`` so we can still recognise "this is the account
/// you already had connected" and update its tokens in place rather than
/// creating a duplicate row.
///
/// `RawRepresentable<String>` because the raw value is used as
/// `kSecAttrAccount` in the Keychain and as an array element in the persisted
/// `AccountIndex`. Codable falls out of `RawRepresentable<String>`.
public struct AccountID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Generates a fresh identifier for a newly added account.
    public static func make() -> AccountID {
        AccountID(UUID().uuidString)
    }
}

extension AccountID: CustomStringConvertible {
    public var description: String { rawValue }
}
