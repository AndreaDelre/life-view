import AppKit
import Core
import GoogleAuth
import GoogleTasksClient

/// Application-level orchestrator.
///
/// Holds the singletons that have to outlive any SwiftUI view: the panel
/// controller, the menu-bar item, the global hotkey, and the auth view
/// model. SwiftUI's `App` lifecycle is too short-lived (and too
/// view-flavoured) to own these.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var statusBarController: StatusBarController?
    private var hotKey: GlobalHotKey?
    private var authViewModel: AuthViewModel?
    private var tasksViewModel: TasksViewModel?

    func applicationDidFinishLaunching(_: Notification) {
        // Hide the dock icon. We rely on `LSUIElement = true` in Info.plist as
        // the primary mechanism (handled via XcodeGen), but we also pin the
        // activation policy here as a defence in depth.
        NSApp.setActivationPolicy(.accessory)

        let clientID = Self.googleClientID()
        let signInService = GoogleSignInService(clientID: clientID)
        let store = GoogleAuthAssembly.makeAccountStore(clientID: clientID)
        let viewModel = AuthViewModel(store: store, signInService: signInService)
        authViewModel = viewModel

        let tasksClient = GoogleTasksClient(
            authorizing: GoogleAccountStoreTasksAdapter(store: store)
        )
        let tasksVM = TasksViewModel(client: tasksClient)
        tasksViewModel = tasksVM

        let controller = PanelController(authViewModel: viewModel, tasksViewModel: tasksVM)
        panelController = controller

        statusBarController = StatusBarController { [weak controller] in
            controller?.toggle()
        }

        registerHotKey(combo: HotKeyStore.load())
    }

    func applicationWillTerminate(_: Notification) {
        hotKey = nil
    }

    // MARK: - Hot key

    private func registerHotKey(combo: HotKeyCombo) {
        hotKey = GlobalHotKey(combo: combo) { [weak self] in
            self?.panelController?.toggle()
        }
        if hotKey == nil {
            NSLog("[LifeView] Hotkey registration failed for combo \(combo.displayString)")
        }
    }

    // MARK: - Configuration

    /// Reads the OAuth client ID injected via `project.yml → info →
    /// properties → GIDClientID`. A missing or empty value is a build
    /// configuration bug, not a runtime one — fail loudly so it is caught
    /// during the first launch in development rather than silently breaking
    /// the sign-in flow at the worst possible time.
    private static func googleClientID() -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !value.isEmpty
        else {
            preconditionFailure("GIDClientID missing from Info.plist — check project.yml")
        }
        return value
    }
}
