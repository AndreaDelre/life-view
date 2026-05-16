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
    private var notificationsCoordinator: NotificationsCoordinator?
    private var notificationFocusObserverTask: Task<Void, Never>?

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

        let coordinator = buildSyncCoordinator(cache: offlineCache, registry: registry, store: store)
        let accountsVM = AccountsViewModel(store: store, signInService: signInService, sessions: registry)
        accountsViewModel = accountsVM
        let tasksVM = buildTasksViewModel(
            registry: registry, accountsVM: accountsVM,
            offlineCache: offlineCache, coordinator: coordinator
        )
        tasksViewModel = tasksVM
        startAccountsObserver(accountsVM: accountsVM, coordinator: coordinator)
        let notifications = installNotifications(tasksVM: tasksVM)

        let controller = PanelController(
            accountsViewModel: accountsVM,
            tasksViewModel: tasksVM,
            syncCoordinator: coordinator,
            notificationsCoordinator: notifications
        )
        panelController = controller
        statusBarController = StatusBarController { [weak controller] in controller?.toggle() }
        registerHotKey(combo: HotKeyStore.load())

        // Forward notification taps: open the panel and ask the
        // view-model to focus the matching row.
        notificationFocusObserverTask = Task { [weak self] in
            await self?.observeNotificationFocus()
        }
    }

    /// Builds the offline-sync coordinator if a cache is available.
    /// Returns nil — and lets the app degrade to online-only — if the
    /// cache failed to open at startup.
    private func buildSyncCoordinator(
        cache offlineCache: OfflineCacheStore?,
        registry: AccountSessionRegistry,
        store: AccountStore
    ) -> OfflineSyncCoordinator? {
        guard let offlineCache else { return nil }
        let executor = GoogleTasksWriteExecutor(
            clientLookup: { [weak registry] id in
                guard let registry else {
                    return GoogleTasksClient(authorizing: AccountStoreTasksAdapter(store: store, accountID: id))
                }
                return registry.client(for: id)
            }
        )
        let drainer = WriteQueueDrainer(cache: offlineCache, executor: executor)
        let coord = OfflineSyncCoordinator(networkMonitor: NetworkPathMonitor(), drainer: drainer)
        syncCoordinator = coord
        coord.start()
        return coord
    }

    private func buildTasksViewModel(
        registry: AccountSessionRegistry,
        accountsVM: AccountsViewModel,
        offlineCache: OfflineCacheStore?,
        coordinator: OfflineSyncCoordinator?
    ) -> TasksViewModel {
        TasksViewModel(
            sessions: registry,
            accountLookup: { [weak accountsVM] id in
                accountsVM?.accounts.first(where: { $0.id == id })
            },
            cache: offlineCache,
            syncCoordinator: coordinator
        )
    }

    private func startAccountsObserver(accountsVM: AccountsViewModel, coordinator: OfflineSyncCoordinator?) {
        guard let coordinator else { return }
        accountsObserverTask = Task { [weak accountsVM, weak coordinator] in
            guard let accountsVM else { return }
            while !Task.isCancelled {
                let ids = accountsVM.accounts.map(\.id)
                coordinator?.updateKnownAccounts(ids)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Wires the notifications stack: scheduler + UN delegate + view-
    /// model bridge. Returns the coordinator so the panel can bind to
    /// it.
    private func installNotifications(tasksVM: TasksViewModel) -> NotificationsCoordinator {
        let notifications = NotificationsCoordinator(tasksViewModel: tasksVM)
        notificationsCoordinator = notifications
        tasksVM.attach(notificationsCoordinator: notifications)
        notifications.start()
        return notifications
    }

    func applicationWillTerminate(_: Notification) {
        accountsViewModel?.tearDown()
        accountsObserverTask?.cancel()
        accountsObserverTask = nil
        notificationFocusObserverTask?.cancel()
        notificationFocusObserverTask = nil
        notificationsCoordinator?.stop()
        hotKey = nil
    }

    // MARK: - Notification tap → panel focus

    /// Loops on the `pendingFocus` observable, opening the panel and
    /// asking the view-model to focus the matching task on every tap.
    /// Runs for the app's lifetime; cancelled on terminate.
    private func observeNotificationFocus() async {
        guard let coordinator = notificationsCoordinator else { return }
        while !Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = coordinator.pendingFocus
                } onChange: {
                    continuation.resume()
                }
            }
            guard let request = coordinator.pendingFocus,
                  let tasksVM = tasksViewModel,
                  let panel = panelController else { continue }
            coordinator.pendingFocus = nil
            panel.show()
            await tasksVM.focusTask(
                accountID: request.accountID,
                listID: request.listID,
                taskID: request.taskID
            )
        }
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
