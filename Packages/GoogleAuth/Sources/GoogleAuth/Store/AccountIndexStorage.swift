import Foundation

/// Persists the ordered list of connected accounts and the selected one.
///
/// Defined as a protocol so tests can substitute an in-memory implementation
/// without touching real `UserDefaults` — both because tests run sandboxed
/// and because the standard suite is shared with anything else that uses
/// `UserDefaults.standard` in the test runner.
public protocol AccountIndexStorage: Sendable {
    func read() -> AccountIndex
    func write(_ index: AccountIndex)
}

/// `UserDefaults`-backed implementation.
///
/// We store the whole ``AccountIndex`` as a JSON blob under a single key
/// rather than splitting it into multiple keys. That keeps writes atomic
/// (`UserDefaults` doesn't batch multi-key updates), so a crash between
/// "ids written, selection not yet" cannot leave the app pointing at a
/// dangling selection.
public struct UserDefaultsAccountIndexStorage: AccountIndexStorage, @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe but not yet annotated
    // `Sendable` by the SDK; ``@unchecked Sendable`` reflects that contract.
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "fr.andreadelre.LifeView.accountIndex"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func read() -> AccountIndex {
        guard let data = defaults.data(forKey: key) else { return .empty }
        return (try? JSONDecoder().decode(AccountIndex.self, from: data)) ?? .empty
    }

    public func write(_ index: AccountIndex) {
        if index.orderedIDs.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(index) else { return }
        defaults.set(data, forKey: key)
    }
}
