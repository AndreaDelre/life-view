import Foundation

/// Convenience factory that wires the GoogleAuth pieces together with sane
/// production defaults: real Keychain, real `URLSession`, real
/// `UserDefaults`. Tests inject their own collaborators directly instead of
/// going through this entry point.
public enum GoogleAuthAssembly {
    public static func makeAccountStore(clientID: String) -> GoogleAccountStore {
        GoogleAccountStore(
            keychain: KeychainStore(),
            activeAccount: UserDefaultsActiveAccountStorage(),
            refresher: GoogleTokenRefresher(clientID: clientID),
            revoker: GoogleTokenRevoker()
        )
    }
}
