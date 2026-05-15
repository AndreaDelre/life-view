import Foundation

/// Ordered roster of connected accounts plus the one currently selected.
///
/// Pure value type — the *authoritative shape* of what gets persisted in
/// `UserDefaults`. Two reasons we don't enumerate the Keychain to derive
/// the same information:
///
/// 1. Keychain enumeration doesn't preserve insertion order, and the user-
///    visible avatar strip in the panel must keep a stable ordering across
///    launches.
/// 2. The Keychain ends up holding any number of leftover items the user
///    might revoke from outside the app (e.g. via Keychain Access). Driving
///    the UI off a curated index is more robust than mixing those in.
public struct AccountIndex: Sendable, Codable, Equatable {
    public var orderedIDs: [AccountID]
    public var selectedID: AccountID?

    public init(orderedIDs: [AccountID] = [], selectedID: AccountID? = nil) {
        self.orderedIDs = orderedIDs
        self.selectedID = selectedID
    }

    public static let empty = AccountIndex()
}
