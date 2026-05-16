import Core
import Foundation
import GoogleAuth
@testable import OfflineCache
import XCTest

final class OfflineCacheStoreTests: XCTestCase {
    private let accountA = AccountID("acct-A")
    private let accountB = AccountID("acct-B")

    private func makeStore() async throws -> OfflineCacheStore {
        try OfflineCacheStore.inMemory()
    }

    // MARK: - Lists round-trip

    func test_saveAndLoadLists_returnsSaved() async throws {
        let store = try await makeStore()
        let lists = [
            TaskList(id: "l1", title: "Personnel", updatedAt: Date(timeIntervalSince1970: 1_000)),
            TaskList(id: "l2", title: "Boulot", updatedAt: Date(timeIntervalSince1970: 2_000))
        ]
        try await store.saveLists(lists, accountID: accountA)
        let loaded = try await store.loadLists(accountID: accountA)
        XCTAssertEqual(Set(loaded.map(\.id)), Set(lists.map(\.id)))
    }

    func test_saveLists_replacesPrevious() async throws {
        let store = try await makeStore()
        try await store.saveLists([
            TaskList(id: "l1", title: "Old", updatedAt: Date())
        ], accountID: accountA)
        try await store.saveLists([
            TaskList(id: "l2", title: "New", updatedAt: Date())
        ], accountID: accountA)
        let loaded = try await store.loadLists(accountID: accountA)
        XCTAssertEqual(loaded.map(\.id), ["l2"])
    }

    func test_lists_scopedByAccount() async throws {
        let store = try await makeStore()
        try await store.saveLists([
            TaskList(id: "l1", title: "A", updatedAt: Date())
        ], accountID: accountA)
        try await store.saveLists([
            TaskList(id: "l2", title: "B", updatedAt: Date())
        ], accountID: accountB)
        let aLoaded = try await store.loadLists(accountID: accountA)
        let bLoaded = try await store.loadLists(accountID: accountB)
        XCTAssertEqual(aLoaded.map(\.id), ["l1"])
        XCTAssertEqual(bLoaded.map(\.id), ["l2"])
    }

    // MARK: - Tasks round-trip

    func test_saveAndLoadTasks_returnsSortedByPosition() async throws {
        let store = try await makeStore()
        let tasks = [
            TaskItem(id: "t2", title: "Second", status: .needsAction, position: "00000000000000000002"),
            TaskItem(id: "t1", title: "First", status: .needsAction, position: "00000000000000000001"),
            TaskItem(id: "t3", title: "Third", status: .completed, position: "00000000000000000003")
        ]
        try await store.saveTasks(tasks, listID: "list-1", accountID: accountA)
        let loaded = try await store.loadTasks(listID: "list-1", accountID: accountA)
        XCTAssertEqual(loaded.map(\.id), ["t1", "t2", "t3"])
    }

    func test_upsertTask_replacesExisting() async throws {
        let store = try await makeStore()
        let initial = TaskItem(id: "t1", title: "Old", status: .needsAction, position: "p")
        try await store.saveTasks([initial], listID: "list-1", accountID: accountA)
        let updated = TaskItem(id: "t1", title: "New", status: .completed, position: "p")
        try await store.upsertTask(updated, listID: "list-1", accountID: accountA)
        let loaded = try await store.loadTasks(listID: "list-1", accountID: accountA)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "New")
        XCTAssertEqual(loaded.first?.status, .completed)
    }

    func test_deleteList_cascadesTasks() async throws {
        let store = try await makeStore()
        try await store.saveLists([
            TaskList(id: "l1", title: "L", updatedAt: Date())
        ], accountID: accountA)
        try await store.saveTasks([
            TaskItem(id: "t1", title: "T", status: .needsAction, position: "p")
        ], listID: "l1", accountID: accountA)
        try await store.deleteList(listID: "l1", accountID: accountA)
        let lists = try await store.loadLists(accountID: accountA)
        let tasks = try await store.loadTasks(listID: "l1", accountID: accountA)
        XCTAssertTrue(lists.isEmpty)
        XCTAssertTrue(tasks.isEmpty)
    }

    // MARK: - Snapshot

    func test_snapshot_returnsListsAndGroupedTasks() async throws {
        let store = try await makeStore()
        try await store.saveLists([
            TaskList(id: "l1", title: "L1", updatedAt: Date()),
            TaskList(id: "l2", title: "L2", updatedAt: Date())
        ], accountID: accountA)
        try await store.saveTasks([
            TaskItem(id: "t1", title: "T1", status: .needsAction, position: "a")
        ], listID: "l1", accountID: accountA)
        try await store.saveTasks([
            TaskItem(id: "t2", title: "T2", status: .needsAction, position: "a"),
            TaskItem(id: "t3", title: "T3", status: .needsAction, position: "b")
        ], listID: "l2", accountID: accountA)

        let snapshot = try store.snapshot(accountID: accountA)
        XCTAssertEqual(Set(snapshot.lists.map(\.id)), Set(["l1", "l2"]))
        XCTAssertEqual(snapshot.tasks(for: "l1").map(\.id), ["t1"])
        XCTAssertEqual(snapshot.tasks(for: "l2").map(\.id), ["t2", "t3"])
    }

    func test_snapshot_emptyForUnknownAccount() async throws {
        let store = try await makeStore()
        let snapshot = try store.snapshot(accountID: AccountID("nobody"))
        XCTAssertTrue(snapshot.lists.isEmpty)
        XCTAssertTrue(snapshot.tasksByList.isEmpty)
    }

    // MARK: - Wipe

    func test_wipeAccount_clearsListsTasksAndQueue() async throws {
        let store = try await makeStore()
        try await store.saveLists([
            TaskList(id: "l1", title: "L", updatedAt: Date())
        ], accountID: accountA)
        try await store.saveTasks([
            TaskItem(id: "t1", title: "T", status: .needsAction, position: "p")
        ], listID: "l1", accountID: accountA)
        _ = try await store.enqueueWrite(
            accountID: accountA,
            payload: .deleteTask(listID: "l1", taskID: "t1")
        )

        try await store.wipeAccount(accountA)

        let lists = try await store.loadLists(accountID: accountA)
        let queued = try await store.pendingWrites(accountID: accountA)
        XCTAssertTrue(lists.isEmpty)
        XCTAssertTrue(queued.isEmpty)
    }
}
