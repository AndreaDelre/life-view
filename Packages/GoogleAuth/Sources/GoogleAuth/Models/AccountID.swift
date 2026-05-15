import Foundation

/// Stable identifier for a Google account.
///
/// Backed by the OpenID Connect ``sub`` claim returned by Google. The value
/// is stable across renames and avatar changes, which makes it the right key
/// for indexing Keychain items and persistent state.
public struct AccountID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension AccountID: CustomStringConvertible {
    public var description: String { rawValue }
}
