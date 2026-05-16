import Foundation
import GoogleAuth
import Observation
import OfflineCache

/// App-level coordinator that turns connectivity changes into queue
/// drains and surfaces the resulting state to the UI.
///
/// Owns no business logic of its own — it composes the
/// ``NetworkPathMonitor`` and the ``WriteQueueDrainer``:
///
/// - subscribes to network status changes and triggers a drain on
///   every `.offline → .online` transition,
/// - exposes `isOnline` and `isSyncing` as `@Observable` so a single
///   SwiftUI view can render the offline / "en cours de sync" badge.
///
/// Created and kept alive by ``AppDelegate``. Crucially **not bound to
/// any view's lifecycle** — the panel comes and goes, but the
/// coordinator must keep listening to the network so the queue drains
/// reliably even when the panel is hidden.
@MainActor
@Observable
final class OfflineSyncCoordinator {
    /// True when the network monitor reports `.satisfied`. Starts at
    /// `true` so the UI doesn't render an "offline" badge for the few
    /// hundred milliseconds before the first path callback fires —
    /// flipping to `false` later would be a false flash.
    private(set) var isOnline: Bool = true

    /// True while at least one drain pass is in flight. Used to render
    /// the spinner next to the offline badge.
    private(set) var isSyncing: Bool = false

    /// Accounts the coordinator should drain. Pushed in by
    /// ``AccountsViewModel`` whenever the connected-accounts set
    /// changes; drained one by one (the drainer is concurrent-safe).
    private(set) var knownAccountIDs: [AccountID] = []

    private let networkMonitor: NetworkPathMonitor
    private let drainer: WriteQueueDrainer
    private var statusTask: Task<Void, Never>?
    private var pendingDrainCount: Int = 0

    init(networkMonitor: NetworkPathMonitor, drainer: WriteQueueDrainer) {
        self.networkMonitor = networkMonitor
        self.drainer = drainer
    }

    /// Idempotent: starts the network monitor and subscribes to the
    /// status stream. Called once from ``AppDelegate``.
    func start() {
        guard statusTask == nil else { return }
        let monitor = networkMonitor
        let weakSelf = WeakBox(self)
        statusTask = Task {
            await monitor.start()
            let stream = await monitor.statuses
            for await status in stream {
                guard let coordinator = weakSelf.value else { return }
                await coordinator.handle(status: status)
            }
        }
    }

    /// Updates the set of accounts we drain. Triggers an immediate
    /// drain pass on each newly-tracked account so a launch with
    /// queued writes from a previous session doesn't have to wait for
    /// a network transition.
    func updateKnownAccounts(_ ids: [AccountID]) {
        let newOnes = ids.filter { id in !knownAccountIDs.contains(id) }
        knownAccountIDs = ids
        guard isOnline else { return }
        for accountID in newOnes {
            triggerDrain(accountID: accountID)
        }
    }

    /// Manually trigger a drain across every known account. Called
    /// from the view-model after a mutation succeeds (a successful
    /// online mutation is a strong hint that connectivity is back and
    /// any other queued writes for the same account can flush now).
    func requestDrain(accountID: AccountID) {
        guard isOnline else { return }
        triggerDrain(accountID: accountID)
    }

    // MARK: - Private

    private func handle(status: NetworkPathMonitor.Status) async {
        let nextOnline = status == .online
        let wasOffline = !isOnline
        isOnline = nextOnline
        guard nextOnline, wasOffline else { return }
        // Transition into online state: drain every known account.
        for accountID in knownAccountIDs {
            triggerDrain(accountID: accountID)
        }
    }

    private func triggerDrain(accountID: AccountID) {
        let drainer = drainer
        let weakSelf = WeakBox(self)
        pendingDrainCount += 1
        isSyncing = pendingDrainCount > 0
        Task {
            _ = await drainer.drain(accountID: accountID)
            await MainActor.run {
                guard let coordinator = weakSelf.value else { return }
                coordinator.pendingDrainCount = max(0, coordinator.pendingDrainCount - 1)
                coordinator.isSyncing = coordinator.pendingDrainCount > 0
            }
        }
    }
}

/// Weak reference helper used to break the obvious retain cycles in the
/// closures that the network monitor's status loop installs.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
