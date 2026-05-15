import Foundation

/// Reads the legacy P2 single-account record (UserDefaults pointer +
/// Keychain item keyed by the Google `sub`) and produces the data
/// needed by ``AccountStore`` to rewrite it under the P4 shape
/// (local UUID id + `subject` field on the profile).
///
/// The migration **only reads** here; the actual rewrite lives in
/// ``AccountStore/loadAll()`` so that index + Keychain mutations stay
/// behind the actor and a single atomic write path. Idempotency falls
/// out of that arrangement: once the legacy pointer is cleared, this
/// returns `nil` forever.
public struct MonoAccountMigration: MonoAccountMigrating {
    private let keychain: KeychainStoring
    private let legacy: LegacyMonoAccountPointer

    public init(keychain: KeychainStoring, legacy: LegacyMonoAccountPointer) {
        self.keychain = keychain
        self.legacy = legacy
    }

    public func runIfNeeded() throws -> MigratedAccount? {
        guard let legacyID = legacy.read(), !legacyID.isEmpty else { return nil }

        // The legacy id was the Google `sub`. It now serves both as the
        // Keychain lookup key (to find the existing record) and as the
        // `subject` field on the migrated profile.
        guard let secrets: StoredAccountSecrets = try keychain.read(StoredAccountSecrets.self, key: legacyID) else {
            // Pointer without a backing Keychain item: bogus state, just
            // clear the pointer so we stop trying every launch.
            legacy.clear()
            return nil
        }

        let newID = AccountID.make()
        let migratedProfile = AccountProfile(
            subject: secrets.profile.subject ?? legacyID,
            email: secrets.profile.email,
            displayName: secrets.profile.displayName,
            avatarURL: secrets.profile.avatarURL
        )
        let migrated = MigratedAccount(
            account: Account(id: newID, profile: migratedProfile),
            tokens: secrets.tokens
        )

        // Caller persists the new record before we clear the legacy entry
        // — but the legacy Keychain item still lives at `legacyID`. Wipe
        // it now so we don't leave a redundant copy behind.
        try keychain.delete(key: legacyID)
        legacy.clear()
        return migrated
    }
}

/// Reads / clears the legacy P2 `activeAccountID` pointer in UserDefaults.
public protocol LegacyMonoAccountPointer: Sendable {
    func read() -> String?
    func clear()
}

/// `UserDefaults`-backed pointer at the P2 key.
public struct UserDefaultsLegacyMonoAccountPointer: LegacyMonoAccountPointer, @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe but not yet annotated
    // `Sendable` by the SDK.
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "fr.andreadelre.LifeView.activeAccountID"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func read() -> String? { defaults.string(forKey: key) }
    public func clear() { defaults.removeObject(forKey: key) }
}
