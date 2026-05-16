import Foundation
import GoogleAuth
import UserNotifications

/// Description of a task whose due-date is to be (or already is)
/// reflected as a local notification.
///
/// `Sendable` so it can cross the actor boundary; deliberately not
/// `Identifiable` because the natural identifier is computed
/// (``NotificationScheduler/identifier(for:)``) rather than carried.
struct ScheduledNotification: Sendable, Equatable {
    let accountID: AccountID
    let listID: String
    let taskID: String
    let title: String
    let dueDate: Date
}

/// User-info keys used to round-trip the task coordinates through
/// ``UNNotificationRequest`` so the tap handler can route the focus
/// request back to the view-model.
enum NotificationUserInfoKey {
    static let accountID = "lv.accountID"
    static let listID = "lv.listID"
    static let taskID = "lv.taskID"
}

/// Schedules / cancels / reconciles local notifications for tasks with
/// a `due` date.
///
/// The actor keeps a tiny in-memory mirror of what is currently
/// pending in the system centre (identifier → due date) so a
/// ``syncWith(desired:)`` call can compute a minimal diff and only
/// touch the OS for the rows that actually changed — a full "wipe &
/// recreate" would briefly empty the centre and is wasted work besides.
///
/// The mirror is rebuilt from the OS centre on first use (so the
/// process can recover its view of pending notifications across
/// restarts without re-scheduling everything).
actor NotificationScheduler {
    private let center: NotificationCenterAccess

    /// identifier → due date. Rebuilt lazily from the OS centre on
    /// first call to ``syncWith(desired:)``.
    private var pending: [String: Date] = [:]
    private var didHydrate = false

    /// Cached authorization status. Re-fetched on demand by
    /// ``isAuthorized``; populated by ``requestAuthorization()``.
    private var cachedStatus: UNAuthorizationStatus?

    init(center: NotificationCenterAccess = SystemNotificationCenter()) {
        self.center = center
    }

    // MARK: - Authorization

    /// True when the user has previously granted the alert permission.
    /// Does not prompt — call ``requestAuthorization()`` for that.
    var isAuthorized: Bool {
        get async {
            let status: UNAuthorizationStatus
            if let cached = cachedStatus {
                status = cached
            } else {
                status = await center.authorizationStatus()
                cachedStatus = status
            }
            return status == .authorized || status == .provisional
        }
    }

    /// Prompts the user the first time, returns whether the grant
    /// succeeded. Idempotent — subsequent calls return the cached
    /// decision without re-prompting.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            cachedStatus = granted ? .authorized : .denied
            return granted
        } catch {
            cachedStatus = .denied
            return false
        }
    }

    // MARK: - Diff & sync

    /// Reconciles the system centre with `desired`. Performs a minimal
    /// diff: only schedules / cancels notifications that actually
    /// changed.
    ///
    /// - Past-due rows (`dueDate <= now`) are skipped — scheduling a
    ///   notification with a trigger in the past makes `UNCalendarNotificationTrigger`
    ///   fire immediately, which would spam the user on every reload.
    func syncWith(desired: [ScheduledNotification], now: Date = Date()) async {
        await hydrateIfNeeded()

        // Filter to future dues. Build a desired-state map keyed by id.
        let futures = desired.filter { $0.dueDate > now }
        var desiredByID: [String: ScheduledNotification] = [:]
        desiredByID.reserveCapacity(futures.count)
        for item in futures {
            desiredByID[Self.identifier(for: item)] = item
        }

        // Cancellations: ids present locally but absent from desired.
        let toCancel = pending.keys.filter { desiredByID[$0] == nil }
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toCancel))
            for id in toCancel { pending.removeValue(forKey: id) }
        }

        // Schedules: ids whose due differs (or is brand new).
        for (id, item) in desiredByID {
            if let existing = pending[id], existing == item.dueDate {
                continue
            }
            await schedule(item, identifier: id)
        }
    }

    /// Cancels every pending notification. Called on toggle-off.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        pending.removeAll()
    }

    /// Cancels notifications for a single task. Idempotent — used by
    /// the view-model on completion / deletion.
    func cancel(accountID: AccountID, listID: String, taskID: String) {
        let id = Self.identifier(accountID: accountID, listID: listID, taskID: taskID)
        guard pending.removeValue(forKey: id) != nil else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Identifier

    /// Stable identifier scoped by `(accountID, listID, taskID)` —
    /// guarantees that `add(_:)` replaces the prior pending request
    /// rather than stacking a second one for the same task.
    static func identifier(for item: ScheduledNotification) -> String {
        identifier(accountID: item.accountID, listID: item.listID, taskID: item.taskID)
    }

    static func identifier(accountID: AccountID, listID: String, taskID: String) -> String {
        // `.` is allowed in UN identifiers; the raw values are
        // Google IDs (URL-safe) or our locally-generated UUIDs, so no
        // escaping is required.
        "notif.\(accountID.rawValue).\(listID).\(taskID)"
    }

    // MARK: - Internals

    private func hydrateIfNeeded() async {
        guard !didHydrate else { return }
        didHydrate = true
        let existing = await center.pendingNotificationRequests()
        for request in existing {
            guard request.identifier.hasPrefix("notif.") else { continue }
            if let trigger = request.trigger as? UNCalendarNotificationTrigger,
               let next = trigger.nextTriggerDate() {
                pending[request.identifier] = next
            }
        }
    }

    private func schedule(_ item: ScheduledNotification, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = "Échéance"
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKey.accountID: item.accountID.rawValue,
            NotificationUserInfoKey.listID: item.listID,
            NotificationUserInfoKey.taskID: item.taskID
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: item.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            pending[identifier] = item.dueDate
        } catch {
            // The OS rejected the request (e.g. the trigger had become
            // past due between filtering and scheduling). Drop the
            // entry from the mirror so the next sync re-evaluates.
            pending.removeValue(forKey: identifier)
        }
    }
}
