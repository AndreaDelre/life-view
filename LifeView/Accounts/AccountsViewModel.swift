import AppKit
import GoogleAuth
import Observation

/// SwiftUI-facing observable surface over ``AccountStore``.
///
/// Subscribes to the store's `snapshots` async stream once at `start()`
/// and mirrors the freshest state into `@Observable` properties so the
/// view tree updates on every account change without per-view polling.
/// Owns the OAuth interactive flow because that flow needs an `NSWindow`
/// and the main queue, neither of which fit on an actor.
@MainActor
@Observable
final class AccountsViewModel {
    /// Display mode for the tasks panel: one account at a time, or all
    /// accounts aggregated. Persisted to UserDefaults so launches reopen
    /// in the user's last-chosen mode.
    enum DisplayMode: String, CaseIterable, Sendable, Codable {
        case single
        case all
    }

    private(set) var accounts: [Account] = []
    private(set) var selectedID: AccountID?
    private(set) var mode: DisplayMode
    private(set) var isLoaded: Bool = false
    private(set) var isWorking: Bool = false
    private(set) var errorMessage: String?

    private let store: AccountStore
    private let signInService: GoogleSignInService
    private let sessions: AccountSessionRegistry
    private let preferences: UserDefaults

    private var subscriptionTask: Task<Void, Never>?

    private static let modeKey = "AccountsViewModel.displayMode"

    init(
        store: AccountStore,
        signInService: GoogleSignInService,
        sessions: AccountSessionRegistry,
        preferences: UserDefaults = .standard
    ) {
        self.store = store
        self.signInService = signInService
        self.sessions = sessions
        self.preferences = preferences
        let raw = preferences.string(forKey: Self.modeKey) ?? DisplayMode.single.rawValue
        self.mode = DisplayMode(rawValue: raw) ?? .single
    }

    // No `deinit` cancellation here: under Swift 6 strict concurrency,
    // a `deinit` runs in a nonisolated context and cannot touch the
    // main-actor-isolated `subscriptionTask`. The app delegate calls
    // ``tearDown()`` from `applicationWillTerminate` and the view-model
    // outlives every consumer, so the task never leaks in practice.

    // MARK: - Lifecycle

    /// Idempotent: load the persisted accounts on first call, then start
    /// streaming snapshots from the store.
    func start() async {
        guard subscriptionTask == nil else { return }
        do {
            let initial = try await store.loadAll()
            apply(snapshot: initial)
            isLoaded = true
        } catch {
            errorMessage = Self.message(for: error)
            isLoaded = true
        }
        subscribeToSnapshots()
    }

    /// Severs the subscription. Called only on app teardown; the panel
    /// content view keeps the view-model alive across hide/show cycles.
    func tearDown() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    private func subscribeToSnapshots() {
        // The closure crosses isolation boundaries (store actor → main
        // actor), so each iteration is fenced by an explicit await + hop
        // back to MainActor via the function being @MainActor.
        let store = self.store
        subscriptionTask = Task { [weak self] in
            // Two-step on purpose: Swift 6.0 (Xcode 16.2 / CI) refuses
            // the chained form `for await … in await store.snapshots`
            // even though Xcode 26 accepts it. The intermediate `let`
            // lifts the cross-actor read out of the `for-await` clause.
            let stream = await store.snapshots
            for await snapshot in stream {
                guard let self else { return }
                self.apply(snapshot: snapshot)
            }
        }
    }

    private func apply(snapshot: AccountsSnapshot) {
        accounts = snapshot.accounts
        selectedID = snapshot.selectedID
    }

    // MARK: - Mutations

    /// Triggers the OAuth interactive flow and persists the resulting
    /// account. Duplicates (same Google `subject`) are de-duped by the
    /// store and surface as "selection moved onto the existing record".
    func addAccount(presenting window: NSWindow) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await signInService.signIn(presenting: window)
            _ = try await store.addAccount(result.account, tokens: result.tokens)
        } catch GoogleOAuthError.userCancelled {
            // The user dismissed the consent sheet — no error to surface.
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func select(_ id: AccountID) async {
        guard selectedID != id else { return }
        do {
            _ = try await store.select(id)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func removeAccount(_ id: AccountID) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            _ = try await store.removeAccount(id)
            sessions.discard(id)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func renameAccount(_ id: AccountID, displayName: String?) async {
        do {
            _ = try await store.renameAccount(id, displayName: displayName)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func setMode(_ next: DisplayMode) {
        guard next != mode else { return }
        mode = next
        preferences.set(next.rawValue, forKey: Self.modeKey)
    }

    func clearError() {
        errorMessage = nil
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
