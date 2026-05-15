import Core
import Foundation

/// Persists the user-chosen hotkey combo in `UserDefaults`.
///
/// The "real" preferences UI ships in P7; until then we just need a stable place
/// to write the value so the rest of P1 can pretend it is configurable.
enum HotKeyStore {
    private static let key = "LifeView.PanelToggleHotKey"

    /// Loads the stored combo, falling back to ``HotKeyCombo/default`` if the
    /// payload is missing or corrupted (which can happen if the schema changes).
    static func load(defaults: UserDefaults = .standard) -> HotKeyCombo {
        guard
            let data = defaults.data(forKey: key),
            let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data)
        else {
            return .default
        }
        return combo
    }

    static func save(_ combo: HotKeyCombo, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }
}
