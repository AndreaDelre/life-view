import Core
@testable import GoogleTasksClient
import XCTest

/// Tests for P5 task-list mutations: `insertTaskList`, `renameTaskList`,
/// `deleteTaskList`. Covers endpoint shape, body encoding, and the cache
/// surgery (including the cascade that drops tasks of a deleted list).
final class GoogleTasksClientListMutationsTests: XCTestCase {
    // MARK: - Endpoint shapes

    func testInsertTaskListEndpointShape() {
        let url = GoogleTasksEndpoints.insertTaskList()
        XCTAssertEqual(url.host, "tasks.googleapis.com")
        XCTAssertTrue(url.path.hasSuffix("/users/@me/lists"))
    }

    func testUpdateAndDeleteListEndpointsShareShape() {
        let patch = GoogleTasksEndpoints.updateTaskList(listID: "L-9")
        let delete = GoogleTasksEndpoints.deleteTaskList(listID: "L-9")
        XCTAssertTrue(patch.path.hasSuffix("/users/@me/lists/L-9"))
        XCTAssertEqual(patch.path, delete.path)
    }

    // MARK: - insertTaskList

    func testInsertTaskListPostsJSONBodyAndReturnsList() async throws {
        let responseJSON = """
        {"id":"new-1","title":"Boulot","updated":"2026-05-15T08:00:00.000Z"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(responseJSON.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        let inserted = try await client.insertTaskList(title: "Boulot")

        XCTAssertEqual(inserted.id, "new-1")
        XCTAssertEqual(inserted.title, "Boulot")

        let req = http.requests[0]
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path.hasSuffix("/users/@me/lists"), true)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["title"] as? String, "Boulot")
        XCTAssertEqual(body.keys.sorted(), ["title"])
    }

    func testInsertTaskListAppendsToListsCache() async throws {
        let seed = """
        {"items":[
          {"id":"l1","title":"Personnel","updated":"2026-05-15T08:00:00.000Z"}
        ]}
        """
        let insertResp = """
        {"id":"l2","title":"Boulot","updated":"2026-05-15T09:00:00.000Z"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 200, body: Data(insertResp.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTaskLists()
        _ = try await client.insertTaskList(title: "Boulot")

        let cached = try await client.fetchTaskLists()
        XCTAssertEqual(cached.map(\.id), ["l1", "l2"], "new list must be appended to the cache")
        XCTAssertEqual(http.requests.count, 2, "cache must not be invalidated by the insert")
    }

    // MARK: - renameTaskList

    func testRenameTaskListPatchesAndUpdatesCache() async throws {
        let seed = """
        {"items":[
          {"id":"l1","title":"Old","updated":"2026-05-15T08:00:00.000Z"}
        ]}
        """
        let patchResp = """
        {"id":"l1","title":"New","updated":"2026-05-15T09:00:00.000Z"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 200, body: Data(patchResp.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTaskLists()
        let renamed = try await client.renameTaskList(listID: "l1", title: "New")

        XCTAssertEqual(renamed.title, "New")
        let req = http.requests[1]
        XCTAssertEqual(req.httpMethod, "PATCH")
        XCTAssertEqual(req.url?.path.hasSuffix("/users/@me/lists/l1"), true)

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["title"] as? String, "New")

        let cached = try await client.fetchTaskLists()
        XCTAssertEqual(cached.first?.title, "New", "cache must reflect the rename")
        XCTAssertEqual(http.requests.count, 2, "cache must not be invalidated by the rename")
    }

    // MARK: - deleteTaskList

    func testDeleteTaskListSends204AndCascadesCache() async throws {
        let listsSeed = """
        {"items":[
          {"id":"l1","title":"Personnel","updated":"2026-05-15T08:00:00.000Z"},
          {"id":"l2","title":"Boulot","updated":"2026-05-15T09:00:00.000Z"}
        ]}
        """
        let tasksSeed = """
        {"items":[
          {"id":"t1","title":"x","status":"needsAction","position":"00000000000000000001"}
        ]}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(listsSeed.utf8)),
            .success(statusCode: 200, body: Data(tasksSeed.utf8)),
            .success(statusCode: 204, body: Data())
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTaskLists()
        _ = try await client.fetchTasks(in: "l1")

        try await client.deleteTaskList(listID: "l1")

        let req = http.requests[2]
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.url?.path.hasSuffix("/users/@me/lists/l1"), true)
        XCTAssertNil(req.httpBody)

        let cached = await client.cachedTasks(for: "l1", showCompleted: false)
        XCTAssertNil(cached, "tasks cache for the deleted list must be dropped")
    }

    func testDeleteTaskListSurfacesHTTPError() async throws {
        let http = StubTasksHTTPClient([
            .success(statusCode: 404, body: Data())
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        do {
            try await client.deleteTaskList(listID: "missing")
            XCTFail("expected http error")
        } catch let GoogleTasksError.http(status) {
            XCTAssertEqual(status, 404)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
