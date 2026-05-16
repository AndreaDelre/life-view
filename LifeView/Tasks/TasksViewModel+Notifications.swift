import Foundation
import GoogleAuth

/// Bridge between ``TasksViewModel`` and ``NotificationsCoordinator``.
///
/// Two thin responsibilities:
///
/// - Expose ``focusTask(accountID:listID:taskID:)`` so a notification
///   tap can pre-position the view-model on the right account / list
///   before the panel renders, and request row-level focus through
///   ``focusRequestTaskID``.
/// - Hold a weak reference to the coordinator so the mutation extension
///   can notify it when a task is completed / deleted, without
///   coupling the coordinator to every mutation entry point.
///
/// The coordinator wires itself in via ``attach(notificationsCoordinator:)``
/// during ``AppDelegate/applicationDidFinishLaunching``.
extension TasksViewModel {
    /// Wires the coordinator. Stored weakly inside an associated
    /// box because ``TasksViewModel`` is `@Observable` — adding a
    /// stored `weak var` directly would tie it into the observation
    /// tracking, which we don't want for an integration seam.
    func attach(notificationsCoordinator: NotificationsCoordinator) {
        NotificationsBridge.shared.set(coordinator: notificationsCoordinator, for: self)
    }

    /// Notifies the coordinator that `taskID` is no longer eligible
    /// for a notification (completed or deleted). No-op if no
    /// coordinator has been attached or the user has notifications
    /// turned off.
    func notifyTaskClosed(accountID: AccountID, listID: String, taskID: String) {
        NotificationsBridge.shared
            .coordinator(for: self)?
            .taskCompletedOrDeleted(accountID: accountID, listID: listID, taskID: taskID)
    }

    /// Brings the panel's selection in line with `(accountID, listID)`
    /// and records `taskID` as the row to scroll-to / select. Safe to
    /// call from a non-main context — the actor isolation of the
    /// view-model puts every mutation back on the main actor.
    func focusTask(accountID: AccountID, listID: String, taskID: String) async {
        // Adjust selection so the right account is loaded.
        switch selection {
        case .none:
            await setSelection(.single(accountID))
        case .single(let current):
            if current != accountID {
                await setSelection(.single(accountID))
            }
        case .all:
            // Aggregated mode already shows every account; no
            // selection change needed.
            break
        }

        // In single mode, ensure the right list is selected too.
        if case .single = selection,
           case let .singleLoaded(payload) = state,
           payload.selectedListID != listID,
           payload.lists.contains(where: { $0.id == listID }) {
            selectList(listID)
        }

        focusRequestTaskID = taskID
    }
}

/// Lazily-allocated table mapping ``TasksViewModel`` instances to the
/// ``NotificationsCoordinator`` they should call back into.
///
/// We avoid an `Observable`-tracked stored property on the view-model
/// (would re-trigger view rendering whenever the coordinator changed)
/// and avoid an `objc_setAssociatedObject` (not Sendable-safe under
/// strict concurrency) by going through this main-actor-isolated table.
@MainActor
final class NotificationsBridge {
    static let shared = NotificationsBridge()

    private var bindings: [ObjectIdentifier: WeakRef] = [:]

    private struct WeakRef {
        weak var coordinator: NotificationsCoordinator?
    }

    private init() {}

    func set(coordinator: NotificationsCoordinator, for viewModel: TasksViewModel) {
        bindings[ObjectIdentifier(viewModel)] = WeakRef(coordinator: coordinator)
    }

    func coordinator(for viewModel: TasksViewModel) -> NotificationsCoordinator? {
        bindings[ObjectIdentifier(viewModel)]?.coordinator
    }
}
