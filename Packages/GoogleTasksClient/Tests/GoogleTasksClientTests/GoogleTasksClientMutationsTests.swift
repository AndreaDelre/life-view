import Core
@testable import GoogleTasksClient
import XCTest

/// Tests for P5 task mutations: `insertTask`, `updateTask`, `deleteTask`,
/// including request shape, body encoding, cache surgery and 401 retry.
final class GoogleTasksClientMutationsTests: XCTestCase {
    // MARK: - Endpoint shapes

    func testInsertTaskEndpointShape() {
        let url = GoogleTasksEndpoints.insertTask(in: "list-1")
        XCTAssertEqual(url.host, "tasks.googleapis.com")
        XCTAssertTrue(url.path.hasSuffix("/lists/list-1/tasks"))
    }

    func testUpdateAndDeleteTaskEndpointShapes() {
        let patch = GoogleTasksEndpoints.updateTask(in: "list-1", taskID: "t-9")
        let delete = GoogleTasksEndpoints.deleteTask(in: "list-1", taskID: "t-9")
        XCTAssertTrue(patch.path.hasSuffix("/lists/list-1/tasks/t-9"))
        XCTAssertEqual(patch.path, delete.path)
    }

    // MARK: - insertTask

    func testInsertTaskPostsJSONBodyAndReturnsTask() async throws {
        let responseJSON = """
        {"id":"new-1","title":"Acheter du pain","status":"needsAction",
         "position":"00000000000000000001",
         "due":"2026-06-01T00:00:00.000Z"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(responseJSON.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        let draft = TaskDraft(
            title: "Acheter du pain",
            notes: nil,
            due: Date(timeIntervalSince1970: 1_780_185_600)
        )
        let inserted = try await client.insertTask(in: "list-1", draft: draft)

        XCTAssertEqual(inserted.id, "new-1")
        XCTAssertEqual(inserted.title, "Acheter du pain")
        XCTAssertEqual(inserted.status, .needsAction)
        XCTAssertEqual(inserted.position, "00000000000000000001")

        XCTAssertEqual(http.requests.count, 1)
        let request = http.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path.hasSuffix("/lists/list-1/tasks"), true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")

        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["title"] as? String, "Acheter du pain")
        XCTAssertNotNil(body["due"])
        XCTAssertNil(body["notes"], "nil notes must not be sent")
    }

    func testInsertTaskOmitsEmptyNotes() async throws {
        let responseJSON = #"{"id":"n","title":"x","status":"needsAction","position":"1"}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(responseJSON.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.insertTask(
            in: "list-1",
            draft: TaskDraft(title: "x", notes: "", due: nil)
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(http.requests[0].httpBody)) as? [String: Any]
        )
        XCTAssertNil(body["notes"], "empty-string notes must not be sent")
        XCTAssertNil(body["due"])
    }

    func testInsertTaskAppendsToTasksCache() async throws {
        let seed = """
        {"items":[
          {"id":"t1","title":"existing","status":"needsAction","position":"00000000000000000001"}
        ]}
        """
        let insertResp = """
        {"id":"t2","title":"new","status":"needsAction","position":"00000000000000000002"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 200, body: Data(insertResp.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTasks(in: "list-1", showCompleted: false)
        _ = try await client.fetchTasks(in: "list-1", showCompleted: true)

        _ = try await client.insertTask(in: "list-1", draft: TaskDraft(title: "new"))

        let visible = await client.cachedTasks(for: "list-1", showCompleted: false)
        let withCompleted = await client.cachedTasks(for: "list-1", showCompleted: true)
        XCTAssertEqual(visible?.map(\.id), ["t1", "t2"])
        XCTAssertEqual(withCompleted?.map(\.id), ["t1", "t2"])
    }

    // MARK: - updateTask

    func testUpdateTaskSendsPatchWithOnlyChangedFields() async throws {
        let responseJSON = """
        {"id":"t1","title":"Renamed","status":"needsAction","position":"00000000000000000001"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(responseJSON.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        let patch = TaskPatch(title: .set("Renamed"))
        let updated = try await client.updateTask(in: "list-1", taskID: "t1", patch: patch)

        XCTAssertEqual(updated.title, "Renamed")
        let req = http.requests[0]
        XCTAssertEqual(req.httpMethod, "PATCH")
        XCTAssertEqual(req.url?.path.hasSuffix("/lists/list-1/tasks/t1"), true)

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["title"] as? String, "Renamed")
        XCTAssertEqual(body.keys.sorted(), ["title"], "only changed keys should be present")
    }

    func testUpdateTaskClearFieldEncodesExplicitNull() async throws {
        let responseJSON = #"{"id":"t1","title":"x","status":"needsAction","position":"1"}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(responseJSON.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.updateTask(
            in: "list-1",
            taskID: "t1",
            patch: TaskPatch(due: .clear)
        )

        let raw = try String(data: XCTUnwrap(http.requests[0].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(raw.contains("\"due\":null"), "expected explicit null in body, got: \(raw)")
    }

    func testUpdateTaskEncodesStatusAsWireString() async throws {
        let responseJSON = #"{"id":"t1","title":"x","status":"completed","position":"1"}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(responseJSON.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.updateTask(
            in: "list-1",
            taskID: "t1",
            patch: TaskPatch(status: .set(.completed))
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(http.requests[0].httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["status"] as? String, "completed")
    }

    func testUpdateTaskEmptyPatchThrows() async {
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([])
        )

        do {
            _ = try await client.updateTask(in: "list-1", taskID: "t1", patch: TaskPatch())
            XCTFail("expected emptyPatch error")
        } catch GoogleTasksError.emptyPatch {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUpdateTaskCompletedTaskLeavesNeedsActionCache() async throws {
        let seed = """
        {"items":[
          {"id":"t1","title":"x","status":"needsAction","position":"00000000000000000001"}
        ]}
        """
        let patchResp = """
        {"id":"t1","title":"x","status":"completed","position":"00000000000000000001"}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 200, body: Data(patchResp.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTasks(in: "list-1", showCompleted: false)
        _ = try await client.fetchTasks(in: "list-1", showCompleted: true)

        _ = try await client.updateTask(
            in: "list-1",
            taskID: "t1",
            patch: TaskPatch(status: .set(.completed))
        )

        let visible = await client.cachedTasks(for: "list-1", showCompleted: false)
        let withCompleted = await client.cachedTasks(for: "list-1", showCompleted: true)
        XCTAssertEqual(visible?.map(\.id), [], "completed task must leave the needsAction-only view")
        XCTAssertEqual(withCompleted?.first?.status, .completed)
    }

    // MARK: - deleteTask

    func testDeleteTaskSends204AndRemovesFromCache() async throws {
        let seed = """
        {"items":[
          {"id":"t1","title":"x","status":"needsAction","position":"00000000000000000001"},
          {"id":"t2","title":"y","status":"needsAction","position":"00000000000000000002"}
        ]}
        """
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(seed.utf8)),
            .success(statusCode: 204, body: Data())
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTasks(in: "list-1")
        try await client.deleteTask(in: "list-1", taskID: "t1")

        let cached = await client.cachedTasks(for: "list-1", showCompleted: false)
        XCTAssertEqual(cached?.map(\.id), ["t2"])

        let req = http.requests[1]
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.url?.path.hasSuffix("/lists/list-1/tasks/t1"), true)
        XCTAssertNil(req.httpBody)
    }

    func testDeleteTaskSurfacesHTTPError() async throws {
        let http = StubTasksHTTPClient([
            .success(statusCode: 500, body: Data())
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        do {
            try await client.deleteTask(in: "list-1", taskID: "t1")
            XCTFail("expected http error")
        } catch let GoogleTasksError.http(status) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - 401 retry on mutations

    func testInsertTaskRetriesAfter401() async throws {
        let resp = #"{"id":"n","title":"x","status":"needsAction","position":"1"}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 401, body: Data()),
            .success(statusCode: 200, body: Data(resp.utf8))
        ])
        let auth = StubTasksAuthorizing()
        let client = GoogleTasksClient(authorizing: auth, http: http)

        _ = try await client.insertTask(in: "list-1", draft: TaskDraft(title: "x"))
        XCTAssertEqual(auth.refreshedTokenCalls, 1)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(http.requests[1].httpMethod, "POST")
        XCTAssertEqual(
            http.requests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer tok-2"
        )
    }
}
