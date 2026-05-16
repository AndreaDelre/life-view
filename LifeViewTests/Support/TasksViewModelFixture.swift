import Core
import Foundation
import GoogleAuth
import GoogleTasksClient
@testable import LifeView

/// Helpers for spinning up a fully-wired ``TasksViewModel`` against
/// stub HTTP — for the optimistic / rollback tests.
@MainActor
enum TasksViewModelFixture {
    static let accountID = AccountID("test-account")
    static let listID = "list-1"

    static func makeAccount() -> Account {
        Account(
            id: accountID,
            profile: AccountProfile(
                subject: "subject-1",
                email: "user@example.com",
                displayName: "Test User",
                avatarURL: nil
            )
        )
    }

    /// Builds a ``TasksViewModel`` driven by a `GoogleTasksClient` whose
    /// HTTP layer is the provided stub. Use the helper builder methods
    /// (`makeFetchTasksSeedResponse`, `makeInsertSuccessResponse`, …)
    /// to populate the stub's response queue, then call `await
    /// vm.setSelection(.single(...))` to drive the initial load.
    static func makeViewModel(
        http: StubTasksHTTPClient,
        queue: SerialOperationQueue<AccountID> = SerialOperationQueue<AccountID>()
    ) -> TasksViewModel {
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: http
        )
        let account = makeAccount()
        let registry = AccountSessionRegistry { _ in client }
        return TasksViewModel(
            sessions: registry,
            accountLookup: { id in id == accountID ? account : nil },
            preferences: makeIsolatedDefaults(),
            writeQueue: queue
        )
    }

    /// Throw-away UserDefaults so tests don't share `showsCompleted` or
    /// pollute the real domain.
    private static func makeIsolatedDefaults() -> UserDefaults {
        // swiftlint:disable:next force_unwrapping
        UserDefaults(suiteName: "fr.andreadelre.LifeView.tests.\(UUID().uuidString)")!
    }

    // MARK: - Canned wire-format responses

    static func listsResponse(_ lists: [(id: String, title: String)] = [(listID, "Personnel")]) -> Data {
        let items = lists.map { #"{"id":"\#($0.id)","title":"\#($0.title)","updated":"2026-05-15T08:00:00.000Z"}"# }
        return Data(#"{"items":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    static func tasksResponse(_ tasks: [(id: String, title: String, status: String, position: String)]) -> Data {
        let items = tasks.map {
            #"{"id":"\#($0.id)","title":"\#($0.title)","status":"\#($0.status)","position":"\#($0.position)"}"#
        }
        return Data(#"{"items":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    static func taskResponse(id: String, title: String, status: String = "needsAction", position: String) -> Data {
        Data(#"{"id":"\#(id)","title":"\#(title)","status":"\#(status)","position":"\#(position)"}"#.utf8)
    }

    /// Two seeded fetches (needsAction-only + showCompleted; the VM hits
    /// both during the initial single-mode load). Pass `tasks` as the
    /// content of the list.
    static func makeInitialFetchOutcomes(
        listsTitle: String = "Personnel",
        tasks: [(id: String, title: String, status: String, position: String)] = []
    ) -> [StubTasksHTTPClient.Outcome] {
        let lists = listsResponse([(listID, listsTitle)])
        let tasksData = tasksResponse(tasks)
        return [
            .success(statusCode: 200, body: lists),
            .success(statusCode: 200, body: tasksData)
        ]
    }
}

/// Tiny awaiter: spins the runloop until `predicate` becomes true or a
/// short timeout elapses. The optimistic flow schedules its network
/// step on a detached `Task { @MainActor … }` so the test has to give
/// the queue a window to fire before asserting on the reconciled state.
@MainActor
enum AsyncWait {
    static func until(
        timeout: TimeInterval = 1.0,
        _ predicate: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            // 5 ms granularity is enough to clear the awaits without
            // burning CPU in the typical sub-50ms tests.
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
