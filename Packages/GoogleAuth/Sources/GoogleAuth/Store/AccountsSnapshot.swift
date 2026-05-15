import Foundation

/// Immutable view of the account roster published by ``AccountStore``.
///
/// Used both as the return value of the mutating store methods and as the
/// element of the ``AccountStore/snapshots`` async stream consumed by the
/// `AccountsViewModel`. Carries everything the UI needs in one struct so a
/// subscriber receives a complete, internally-consistent state on each
/// tick — no risk of seeing an updated `accounts` list with a stale
/// `selectedID`.
public struct AccountsSnapshot: Sendable, Equatable {
    /// Accounts in user-facing display order.
    public let accounts: [Account]
    /// `nil` only when ``accounts`` is empty (no account is connected).
    public let selectedID: AccountID?

    public init(accounts: [Account], selectedID: AccountID?) {
        self.accounts = accounts
        self.selectedID = selectedID
    }

    public static let empty = AccountsSnapshot(accounts: [], selectedID: nil)

    public var isEmpty: Bool { accounts.isEmpty }

    /// Convenience: the currently-selected account, when there is one.
    public var selectedAccount: Account? {
        guard let selectedID else { return nil }
        return accounts.first(where: { $0.id == selectedID })
    }
}
