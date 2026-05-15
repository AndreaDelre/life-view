import Foundation

/// Convenience factory that wires the GoogleAuth pieces together with sane
/// production defaults: real Keychain, real `URLSession`, real
/// `UserDefaults`, retry-wrapped refresher. Tests inject their own
/// collaborators directly instead of going through this entry point.
public enum GoogleAuthAssembly {
    public static func makeAccountStore(clientID: String) -> AccountStore {
        let keychain = KeychainStore()
        let refresher = RetryingTokenRefresher(
            wrapping: GoogleTokenRefresher(clientID: clientID)
        )
        let migration = MonoAccountMigration(
            keychain: keychain,
            legacy: UserDefaultsLegacyMonoAccountPointer()
        )
        return AccountStore(
            keychain: keychain,
            indexStorage: UserDefaultsAccountIndexStorage(),
            refresher: refresher,
            revoker: GoogleTokenRevoker(),
            migrator: migration
        )
    }
}
