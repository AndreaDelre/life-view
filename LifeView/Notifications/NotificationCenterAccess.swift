import Foundation
import UserNotifications

/// Narrow protocol exposing the slice of ``UNUserNotificationCenter``
/// the scheduler actually uses.
///
/// Exists for tests: the real `UNUserNotificationCenter` is a singleton
/// tied to the app bundle, requires a host running inside a properly-
/// signed bundle, and pops a permission dialog on first use — all
/// of which make it non-mockable from a unit-test target. A protocol-
/// based shim lets us inject an in-memory stub in tests while the
/// production code goes straight to the real centre.
protocol NotificationCenterAccess: Sendable {
    /// Triggers the OS permission dialog the first time. Subsequent
    /// calls return the cached decision without re-prompting.
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool

    /// Currently-granted authorization status (cached by the OS).
    func authorizationStatus() async -> UNAuthorizationStatus

    /// Schedules — or replaces, identifier is the key — a notification
    /// request. Throwing here means the OS rejected the request (most
    /// commonly because the trigger has already fired).
    func add(_ request: UNNotificationRequest) async throws

    /// Cancels every pending request whose identifier is in `identifiers`.
    /// No-op for identifiers that are not pending.
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])

    /// Cancels every pending request. Used on toggle-off.
    func removeAllPendingNotificationRequests()

    /// Snapshot of the requests currently pending. Used by the
    /// scheduler to compute the diff against the desired state.
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

/// Production adapter delegating straight to ``UNUserNotificationCenter/current()``.
struct SystemNotificationCenter: NotificationCenterAccess {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
}
