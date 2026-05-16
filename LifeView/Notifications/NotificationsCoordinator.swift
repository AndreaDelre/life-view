import AppKit
import Foundation
import GoogleAuth
import Observation
import UserNotifications

/// Focus request emitted when the user taps a delivered notification.
/// The panel controller / tasks view-model observe this to open the
/// panel and scroll-to / select the matching row.
struct NotificationFocusRequest: Equatable, Sendable {
    let accountID: AccountID
    let listID: String
    let taskID: String
}

/// App-side glue around ``NotificationScheduler``: persists the
/// opt-in toggle in `UserDefaults`, listens for ``TasksViewModel`` state
/// changes to rebuild the desired set, owns the
/// ``UNUserNotificationCenterDelegate`` adapter for the tap handler.
///
/// `@Observable` so the popover toggle binds straight to ``isEnabled``
/// without an intermediate ObservableObject.
@MainActor
@Observable
final class NotificationsCoordinator: NSObject {
    static let preferencesKey = "notificationsEnabled"

    private let scheduler: NotificationScheduler
    private let tasksViewModel: TasksViewModel
    private let preferences: UserDefaults

    /// Persisted opt-in flag. Writing to it through the popover
    /// triggers ``setEnabled(_:)`` which either asks for authorization
    /// + syncs, or cancels everything pending.
    private(set) var isEnabled: Bool

    /// True after the OS dialog has been shown and either grant /
    /// denial was recorded. Surfaced to the popover so the UI can hint
    /// "ouvrir les Préférences Système" when the user previously
    /// refused but is now trying to opt back in.
    private(set) var isAuthorized: Bool = false

    /// True while a `setEnabled(true)` call is awaiting the OS
    /// authorization roundtrip. Drives a spinner in the popover so the
    /// toggle doesn't appear frozen during the second or two the OS
    /// takes to surface its dialog (and rapidly flip the toggle ON
    /// then OFF if auth fails).
    private(set) var isRequestingAuthorization: Bool = false

    /// Set to a human-readable message when the last authorization
    /// request failed for a **system** reason (typically: Debug
    /// ad-hoc signed build — the OS requires a Developer ID / App
    /// Store signed bundle to grant notification permissions).
    /// Distinct from `isAuthorized = false` which can also mean
    /// "user explicitly refused".
    private(set) var lastAuthSystemError: String?

    /// Latest focus request from a notification tap. Set non-nil by
    /// the delegate adapter; consumers read & clear it.
    var pendingFocus: NotificationFocusRequest?

    /// Background task that observes the view-model `state` via
    /// `withObservationTracking` and re-syncs on every change.
    private var observationTask: Task<Void, Never>?

    init(
        scheduler: NotificationScheduler = NotificationScheduler(),
        tasksViewModel: TasksViewModel,
        preferences: UserDefaults = .standard
    ) {
        self.scheduler = scheduler
        self.tasksViewModel = tasksViewModel
        self.preferences = preferences
        isEnabled = preferences.bool(forKey: Self.preferencesKey)
        super.init()
    }

    /// Wires the delegate and, if the user had previously opted in,
    /// starts observing the view-model. Idempotent.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await self.refreshAuthorization() }
        if isEnabled {
            beginObservingTasks()
        }
    }

    /// Detaches the observation Task. Used at shutdown.
    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Toggle

    /// Called by the popover's toggle binding. For OFF we apply the
    /// change immediately (cancelling pending notifications is local).
    /// For ON we **defer** the state change until the OS authorization
    /// roundtrip finishes — flipping `isEnabled = true` optimistically
    /// then back to `false` on rejection was producing a brief
    /// "stuck on" appearance + an orange warning chip during the
    /// gap, which read as a freeze.
    func setEnabled(_ value: Bool) {
        guard value != isEnabled else { return }
        if value {
            // Don't mutate `isEnabled` yet — the toggle binding will
            // re-read it after `isRequestingAuthorization` drops back
            // to false and reflect whatever the auth outcome was.
            guard !isRequestingAuthorization else { return }
            isRequestingAuthorization = true
            lastAuthSystemError = nil
            Task { await self.enable() }
        } else {
            isEnabled = false
            preferences.set(false, forKey: Self.preferencesKey)
            lastAuthSystemError = nil
            Task { await self.disable() }
        }
    }

    private func enable() async {
        let outcome = await scheduler.requestAuthorization()
        isRequestingAuthorization = false
        switch outcome {
        case .granted:
            isAuthorized = true
            isEnabled = true
            preferences.set(true, forKey: Self.preferencesKey)
            beginObservingTasks()
            await resyncFromCurrentState()
        case .denied:
            // User refused at the OS dialog. Leave `isEnabled` at
            // false (the toggle stays off). The popover shows the
            // generic "ouvre Réglages système" hint.
            isAuthorized = false
        case let .systemError(message):
            // System rejected the request (e.g. Debug ad-hoc signed
            // build). Surface a distinct error so the popover can
            // explain WHY it isn't working — silently flipping back
            // to OFF feels like a freeze.
            isAuthorized = false
            lastAuthSystemError = message
        }
    }

    private func disable() async {
        observationTask?.cancel()
        observationTask = nil
        await scheduler.cancelAll()
    }

    /// Re-checks the OS-side status (which may have changed via
    /// System Settings) and caches it on ``isAuthorized``.
    private func refreshAuthorization() async {
        isAuthorized = await scheduler.isAuthorized
    }

    // MARK: - Observation

    private func beginObservingTasks() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            // Loop over `state` changes via the Observation runtime.
            // Each tick reads + registers dependencies, then awaits
            // the next mutation. Cheap and avoids polling.
            while !Task.isCancelled {
                guard let self else { return }
                let desired = await collectDesired()
                await self.scheduler.syncWith(desired: desired)
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.tasksViewModel.state
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Rebuilds the desired set from the current view-model state.
    /// Called both on observation ticks and after enable / hook
    /// invocations from the mutations path.
    private func collectDesired() async -> [ScheduledNotification] {
        Self.desiredFromState(tasksViewModel.state)
    }

    /// Pure helper: extracts the desired notification set from a
    /// view-model state. Static + nonisolated so tests can exercise
    /// the mapping independently of the actor — the state value
    /// itself is `Sendable`, no isolation is needed to read it.
    nonisolated static func desiredFromState(_ state: TasksViewModel.State) -> [ScheduledNotification] {
        var out: [ScheduledNotification] = []
        switch state {
        case .idle, .loading, .error:
            return out
        case let .singleLoaded(payload):
            guard let listID = payload.selectedListID,
                  case let .loaded(items) = payload.tasksState else { return out }
            for item in items {
                guard let due = item.due, item.status == .needsAction else { continue }
                out.append(ScheduledNotification(
                    accountID: payload.account.id,
                    listID: listID,
                    taskID: item.id,
                    title: item.title,
                    dueDate: due
                ))
            }
        case let .allLoaded(sections):
            for section in sections {
                for slice in section.slices {
                    guard case let .loaded(items) = slice.tasksState else { continue }
                    for item in items {
                        guard let due = item.due, item.status == .needsAction else { continue }
                        out.append(ScheduledNotification(
                            accountID: section.account.id,
                            listID: slice.list.id,
                            taskID: item.id,
                            title: item.title,
                            dueDate: due
                        ))
                    }
                }
            }
        }
        return out
    }

    /// Hook called by the view-model mutation extension on completion
    /// / deletion. The next observation tick will also catch up, but
    /// invoking the scheduler directly removes the notif before the
    /// next state diff propagates.
    func taskCompletedOrDeleted(accountID: AccountID, listID: String, taskID: String) {
        guard isEnabled else { return }
        Task { await scheduler.cancel(accountID: accountID, listID: listID, taskID: taskID) }
    }

    /// Public entry point used by the panel right after the user opts
    /// in, before any state change has fired.
    func resyncFromCurrentState() async {
        let desired = await collectDesired()
        await scheduler.syncWith(desired: desired)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationsCoordinator: UNUserNotificationCenterDelegate {
    /// Decides what happens when a notification arrives while the app
    /// is in the foreground. We display a banner + play the sound so
    /// the user is not confused by a silent delivery — they have
    /// already opted in.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a delivered notification. Decodes
    /// the task coordinates from `userInfo` and posts them on
    /// ``pendingFocus`` for the app delegate to consume.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let accountRaw = userInfo[NotificationUserInfoKey.accountID] as? String,
              let listID = userInfo[NotificationUserInfoKey.listID] as? String,
              let taskID = userInfo[NotificationUserInfoKey.taskID] as? String
        else {
            completionHandler()
            return
        }
        let request = NotificationFocusRequest(
            accountID: AccountID(accountRaw),
            listID: listID,
            taskID: taskID
        )
        Task { @MainActor [weak self] in
            self?.pendingFocus = request
            completionHandler()
        }
    }
}
