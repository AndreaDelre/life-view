import Foundation

/// Hooks the P2 → P4 single-account migration into ``AccountStore``.
///
/// Defined as a protocol so the store has no compile-time dependency on the
/// migration's collaborators (legacy `UserDefaults` key, legacy Keychain id
/// shape, clock) — tests pass either no migrator at all or a fake that
/// returns a stubbed result. The real implementation lives in
/// ``MonoAccountMigration``.
public protocol MonoAccountMigrating: Sendable {
    /// Runs the migration if a legacy single-account record is on disk.
    /// Returns the freshly-migrated account record on success, `nil` when
    /// there is nothing to migrate (already migrated, or never had a P2
    /// account). Throws only on the kind of hard I/O failure that warrants
    /// surfacing — a missing legacy item is *not* an error.
    func runIfNeeded() throws -> MigratedAccount?
}

/// Result of a successful one-shot migration.
public struct MigratedAccount: Sendable, Equatable {
    public let account: Account
    public let tokens: TokenSet

    public init(account: Account, tokens: TokenSet) {
        self.account = account
        self.tokens = tokens
    }
}
