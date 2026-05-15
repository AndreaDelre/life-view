import AppKit
import GoogleAuth
import Observation

/// Observable state machine for the authentication corner of the panel.
///
/// Lives on the main actor: every transition is consumed by SwiftUI views,
/// and the underlying `GoogleSignInService` also requires main-actor
/// presentation. `GoogleAccountStore` is an `actor` so its calls are awaited
/// from here.
@MainActor
@Observable
final class AuthViewModel {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(Account)
        case error(String)
    }

    private(set) var state: State = .loading
    private(set) var isWorking: Bool = false

    private let store: GoogleAccountStore
    private let signInService: GoogleSignInService

    init(store: GoogleAccountStore, signInService: GoogleSignInService) {
        self.store = store
        self.signInService = signInService
    }

    /// Reads the persisted account from the Keychain. Idempotent — safe to
    /// call again after a sign-in or sign-out to re-sync the view.
    func start() async {
        do {
            if let account = try await store.loadAccount() {
                state = .signedIn(account)
            } else {
                state = .signedOut
            }
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    func signIn(presenting window: NSWindow) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await signInService.signIn(presenting: window)
            try await store.saveAccount(result.account, tokens: result.tokens)
            state = .signedIn(result.account)
        } catch GoogleOAuthError.userCancelled {
            // The user dismissed the consent sheet — no error to surface.
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    func signOut() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await store.removeAccount()
            state = .signedOut
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    // MARK: - Helpers

    private static func message(for error: Error) -> String {
        if let oauth = error as? GoogleOAuthError {
            switch oauth {
            case .http(let status): return "Erreur réseau Google (HTTP \(status))."
            case .decodingFailed: return "Réponse Google inattendue."
            case .userCancelled: return "Connexion annulée."
            case .incompleteResponse: return "Profil Google incomplet."
            case .noAccount: return "Aucun compte enregistré."
            }
        }
        return (error as NSError).localizedDescription
    }
}
