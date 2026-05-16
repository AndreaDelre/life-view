import Foundation
import GoogleAuth
@testable import LifeView
import os
import UserNotifications
import XCTest

/// In-memory stub for ``NotificationCenterAccess``. Tracks every
/// call so the tests can assert on the diff behaviour without
/// touching the real ``UNUserNotificationCenter`` (a process-wide
/// singleton that pops a permission dialog on first use).
///
/// `@unchecked Sendable` + ``OSAllocatedUnfairLock``: an actor would
/// have been the natural choice, but ``UNNotificationRequest`` is
/// not Sendable so we cannot route it through an actor's mailbox
/// without poking holes in the protocol contract. The unfair lock
/// is async-safe (unlike ``NSLock``) and the tests await every
/// scheduler call sequentially anyway.
final class StubNotificationCenter: NotificationCenterAccess, @unchecked Sendable {
    private struct State {
        var pending: [String: Date] = [:]
        var addCount = 0
        var removeCount = 0
        var removeAllCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var pending: [String: Date] { state.withLock { $0.pending } }
    var addCount: Int { state.withLock { $0.addCount } }
    var removeCount: Int { state.withLock { $0.removeCount } }
    var removeAllCount: Int { state.withLock { $0.removeAllCount } }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func add(_ request: UNNotificationRequest) async throws {
        let identifier = request.identifier
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        let next = trigger?.nextTriggerDate()
        state.withLock {
            $0.addCount += 1
            if let next {
                $0.pending[identifier] = next
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        state.withLock {
            $0.removeCount += identifiers.count
            for id in identifiers {
                $0.pending.removeValue(forKey: id)
            }
        }
    }

    func removeAllPendingNotificationRequests() {
        state.withLock {
            $0.removeAllCount += 1
            $0.pending.removeAll()
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        []
    }
}

/// Exercises the diff and filtering logic of ``NotificationScheduler``.
final class NotificationSchedulerTests: XCTestCase {
    private let accountID = AccountID("acct-1")
    private let listID = "list-1"

    private func makeFutureDate(_ minutes: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func notif(_ taskID: String, due: Date, title: String = "Tâche") -> ScheduledNotification {
        ScheduledNotification(
            accountID: accountID,
            listID: listID,
            taskID: taskID,
            title: title,
            dueDate: due
        )
    }

    func testInitialSyncSchedulesEveryFutureTask() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        let desired = [
            notif("t1", due: makeFutureDate(10)),
            notif("t2", due: makeFutureDate(20)),
            notif("t3", due: makeFutureDate(30))
        ]
        await scheduler.syncWith(desired: desired)

        let addCount = center.addCount
        let pending = center.pending
        XCTAssertEqual(addCount, 3)
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(center.removeCount, 0)
    }

    func testPastDueTasksAreSkipped() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        let desired = [
            notif("t-past", due: Date().addingTimeInterval(-3600)),
            notif("t-future", due: makeFutureDate(10))
        ]
        await scheduler.syncWith(desired: desired)

        XCTAssertEqual(center.addCount, 1)
        XCTAssertEqual(center.pending.count, 1)
    }

    func testNoOpSyncDoesNotReschedule() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        let desired = [notif("t1", due: makeFutureDate(10))]
        await scheduler.syncWith(desired: desired)
        let firstAdds = center.addCount

        // Re-sync identical state. Diff should be empty.
        await scheduler.syncWith(desired: desired)
        XCTAssertEqual(center.addCount, firstAdds, "Identical sync must not re-add")
        XCTAssertEqual(center.removeCount, 0)
    }

    func testRemovedTasksAreCancelled() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.syncWith(desired: [
            notif("t1", due: makeFutureDate(10)),
            notif("t2", due: makeFutureDate(20))
        ])
        await scheduler.syncWith(desired: [notif("t1", due: makeFutureDate(10))])

        let pending = center.pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(pending.keys.contains(where: { $0.hasSuffix(".t1") }))
        XCTAssertEqual(center.removeCount, 1)
    }

    func testChangedDueReschedules() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.syncWith(desired: [notif("t1", due: makeFutureDate(10))])
        let baselineAdds = center.addCount

        let updated = makeFutureDate(45)
        await scheduler.syncWith(desired: [notif("t1", due: updated)])

        XCTAssertEqual(center.addCount, baselineAdds + 1)
        XCTAssertEqual(center.pending.count, 1)
    }

    func testCancelAllClearsPending() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.syncWith(desired: [
            notif("t1", due: makeFutureDate(10)),
            notif("t2", due: makeFutureDate(20))
        ])

        await scheduler.cancelAll()
        XCTAssertEqual(center.removeAllCount, 1)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testCancelSingleTask() async {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.syncWith(desired: [
            notif("t1", due: makeFutureDate(10)),
            notif("t2", due: makeFutureDate(20))
        ])

        await scheduler.cancel(accountID: accountID, listID: listID, taskID: "t1")
        let pending = center.pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertFalse(pending.keys.contains(where: { $0.hasSuffix(".t1") }))
    }

    func testIdentifierIncludesAccountListAndTask() {
        let item = notif("t1", due: makeFutureDate(10))
        let id = NotificationScheduler.identifier(for: item)
        XCTAssertEqual(id, "notif.acct-1.list-1.t1")
    }
}
