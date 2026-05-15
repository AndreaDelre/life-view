import Foundation

/// Tracks which account is currently active.
///
/// In P2 there is at most one account at a time. The pointer lives in
/// `UserDefaults` because losing it on a Keychain wipe is fine (worst case:
/// the user reconnects). When P4 adds multi-account we'll generalise this
/// into an ordered set, but the data shape stays compatible.
public protocol ActiveAccountStorage: Sendable {
    func read() -> AccountID?
    func write(_ accountID: AccountID?)
}

public struct UserDefaultsActiveAccountStorage: ActiveAccountStorage, @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe but not yet annotated
    // `Sendable` in the SDK; ``@unchecked Sendable`` reflects that contract.
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "fr.andreadelre.LifeView.activeAccountID"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func read() -> AccountID? {
        guard let raw = defaults.string(forKey: key), !raw.isEmpty else { return nil }
        return AccountID(raw)
    }

    public func write(_ accountID: AccountID?) {
        if let accountID {
            defaults.set(accountID.rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
