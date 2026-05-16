import AppKit
import Core
import GoogleAuth
import GoogleTasksClient
import OfflineCache

/// Application-level orchestrator.
///
/// Holds the singletons that have to outlive any SwiftUI view: the panel
/// controller, the menu-bar item, the global hotkey, and the accounts /
/// tasks view-models. SwiftUI's `App` lifecycle is too short-lived (and
/// too view-flavoured) to own these.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var statusBarController: StatusBarController?
    private var hotKey: GlobalHotKey?
    private var accountsViewModel: AccountsViewModel?
    private var tasksViewModel: TasksViewModel?
    private var sessionRegistry: AccountSessionRegistry?
    private var cache: OfflineCacheStore?
    private var syncCoordinator: OfflineSyncCoordinator?
    private var accountsObserverTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_: Notification) {
        // Hide the dock icon. We rely on `LSUIElement = true` in Info.plist as
        // the primary mechanism (handled via XcodeGen), but we also pin the
        // activation policy here as a defence in depth.
        NSApp.setActivationPolicy(.accessory)

        let clientID = Self.googleClientID()
        let signInService = GoogleSignInService(clientID: clientID)
        let store = GoogleAuthAssembly.makeAccountStore(clientID: clientID)
        let registry = AccountSessionRegistry(store: store)
        sessionRegistry = registry

        let offlineCache = Self.makeOfflineCache()
        cache = offlineCache

        // Build the drainer + sync coordinator only when the cache is
        // available. If the cache failed to open (rare — disk full, FS
        // permission edge case) the app degrades gracefully to the
        // online-only behaviour we shipped through P6.5.
        var coordinator: OfflineSyncCoordinator?
        if let offlineCache {
            let executor = GoogleTasksWriteExecutor(
                clientLookup: { [weak registry] id in
                    guard let registry else {
                        // The registry has been torn down; return a
                        // throwaway client. The executor will throw on
                        // its first call and the drainer treats that
                        // as transient — the queue stays put for the
                        // next session.
                        return GoogleTasksClient(authorizing: AccountStoreTasksAdapter(store: store, accountID: id))
                    }
                    return registry.client(for: id)
                }
            )
            let networkMonitor = NetworkPathMonitor()
            let drainer = WriteQueueDrainer(cache: offlineCache, executor: executor)
            let coord = OfflineSyncCoordinator(networkMonitor: networkMonitor, drainer: drainer)
            coordinator = coord
            syncCoordinator = coord
            coord.start()
        }

        let accountsVM = AccountsViewModel(
            store: store,
            signInService: signInService,
            sessions: registry
        )
        accountsViewModel = accountsVM

        // The tasks view-model needs to translate AccountIDs into the
        // matching Account profile for headers in the aggregated view.
        // Closure captures `accountsVM` weakly to avoid a retain cycle
        // — both view-models live for the app's lifetime so weak is safe.
        let tasksVM = TasksViewModel(
            sessions: registry,
            accountLookup: { [weak accountsVM] id in
                accountsVM?.accounts.first(where: { $0.id == id })
            },
            cache: offlineCache,
            syncCoordinator: coordinator
        )
        tasksViewModel = tasksVM

        if let coordinator {
            // Push the known accounts into the coordinator so an initial
            // queue from the previous session drains as soon as we're
            // online. Re-pushes on every snapshot change keep the set
            // current with sign-ins / sign-outs.
            accountsObserverTask = Task { [weak accountsVM, weak coordinator] in
                guard let accountsVM else { return }
                while !Task.isCancelled {
                    let ids = accountsVM.accounts.map(\.id)
                    coordinator?.updateKnownAccounts(ids)
                    // Cheap poll — the snapshot stream is internal to
                    // AccountsViewModel; mirroring it via Observation
                    // would couple the delegate to SwiftUI internals.
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }

        let controller = PanelController(
            accountsViewModel: accountsVM,
            tasksViewModel: tasksVM,
            syncCoordinator: coordinator
        )
        panelController = controller

        statusBarController = StatusBarController { [weak controller] in
            controller?.toggle()
        }

        registerHotKey(combo: HotKeyStore.load())
    }

    func applicationWillTerminate(_: Notification) {
        accountsViewModel?.tearDown()
        accountsObserverTask?.cancel()
        accountsObserverTask = nil
        hotKey = nil
    }

    /// Builds the offline cache anchored under Application Support.
    /// Returns `nil` if the store cannot be created — caller falls
    /// back to online-only behaviour without crashing.
    private static func makeOfflineCache() -> OfflineCacheStore? {
        let fileManager = FileManager.default
        guard let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let appDirectory = baseURL.appendingPathComponent("LifeView", isDirectory: true)
        let dbURL = appDirectory.appendingPathComponent("cache.sqlite")
        do {
            return try OfflineCacheStore(databasePath: dbURL)
        } catch {
            NSLog("[LifeView] OfflineCacheStore init failed: \(error.localizedDescription)")
            return nil
        }
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
