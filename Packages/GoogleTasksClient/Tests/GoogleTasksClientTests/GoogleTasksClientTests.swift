import Core
import XCTest
@testable import GoogleTasksClient

final class GoogleTasksClientTests: XCTestCase {
    // MARK: - fetchTaskLists

    func testFetchTaskListsHappyPath() async throws {
        let bodyJSON = """
        {
          "items": [
            {"id": "list-1", "title": "Personnel", "updated": "2026-05-15T08:00:00.000Z"},
            {"id": "list-2", "title": "Boulot",    "updated": "2026-05-14T10:30:00.123Z"}
          ]
        }
        """
        let body = Data(bodyJSON.utf8)

        let auth = StubTasksAuthorizing()
        let http = StubTasksHTTPClient([.success(statusCode: 200, body: body)])
        let client = GoogleTasksClient(authorizing: auth, http: http)

        let lists = try await client.fetchTaskLists()

        XCTAssertEqual(lists.map(\.id), ["list-1", "list-2"])
        XCTAssertEqual(lists.map(\.title), ["Personnel", "Boulot"])
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(
            http.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer tok-1"
        )
    }

    func testFetchTaskListsFollowsPagination() async throws {
        let page1 = #"{"items":[{"id":"a","title":"A","updated":"2026-05-15T00:00:00Z"}],"nextPageToken":"P2"}"#
        let page2 = #"{"items":[{"id":"b","title":"B","updated":"2026-05-15T00:00:00Z"}]}"#

        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(page1.utf8)),
            .success(statusCode: 200, body: Data(page2.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        let lists = try await client.fetchTaskLists()

        XCTAssertEqual(lists.map(\.id), ["a", "b"])
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertTrue(http.requests[1].url?.query?.contains("pageToken=P2") == true)
    }

    func testFetchTaskListsHandlesEmptyResponse() async throws {
        let body = #"{}"#
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.success(statusCode: 200, body: Data(body.utf8))])
        )

        let lists = try await client.fetchTaskLists()
        XCTAssertEqual(lists, [])
    }

    func testFetchTaskListsCachesResultsBetweenCalls() async throws {
        let body = #"{"items":[{"id":"a","title":"A","updated":"2026-05-15T00:00:00Z"}]}"#
        let http = StubTasksHTTPClient([.success(statusCode: 200, body: Data(body.utf8))])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTaskLists()
        _ = try await client.fetchTaskLists()

        XCTAssertEqual(http.requests.count, 1, "second call must be served from cache")
    }

    func testFetchTaskListsForceReloadBypassesCache() async throws {
        let body = #"{"items":[{"id":"a","title":"A","updated":"2026-05-15T00:00:00Z"}]}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(body.utf8)),
            .success(statusCode: 200, body: Data(body.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTaskLists()
        _ = try await client.fetchTaskLists(forceReload: true)

        XCTAssertEqual(http.requests.count, 2)
    }

    func testInvalidateCacheForcesReFetch() async throws {
        let body = #"{"items":[{"id":"a","title":"A","updated":"2026-05-15T00:00:00Z"}]}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 200, body: Data(body.utf8)),
            .success(statusCode: 200, body: Data(body.utf8))
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        _ = try await client.fetchTaskLists()
        await client.invalidateCache()
        _ = try await client.fetchTaskLists()

        XCTAssertEqual(http.requests.count, 2)
    }

    // MARK: - fetchTasks

    func testFetchTasksMapsAndSortsByPosition() async throws {
        let bodyJSON = """
        {
          "items": [
            {"id":"t3","title":"Late",  "status":"needsAction","position":"00000000000000000003"},
            {"id":"t1","title":"Early", "status":"needsAction","position":"00000000000000000001"},
            {"id":"t2","title":"Mid",   "status":"needsAction","position":"00000000000000000002","due":"2026-06-01T00:00:00.000Z"}
          ]
        }
        """
        let body = Data(bodyJSON.utf8)

        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.success(statusCode: 200, body: body)])
        )

        let tasks = try await client.fetchTasks(in: "list-1")

        XCTAssertEqual(tasks.map(\.id), ["t1", "t2", "t3"])
        XCTAssertEqual(tasks[1].due, ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z"))
    }

    func testFetchTasksDropsItemsWithoutPosition() async throws {
        // Real-world case: tombstones / partially-deleted entries. We do
        // not want them to surface as "(untitled)" rows in the panel.
        let bodyJSON = """
        {
          "items": [
            {"id":"good","title":"OK","status":"needsAction","position":"00000000000000000001"},
            {"id":"ghost","title":"","status":"deleted"}
          ]
        }
        """
        let body = Data(bodyJSON.utf8)

        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.success(statusCode: 200, body: body)])
        )

        let tasks = try await client.fetchTasks(in: "list-1")
        XCTAssertEqual(tasks.map(\.id), ["good"])
    }

    func testFetchTasksMapsCompletedStatus() async throws {
        let body = #"""
        {"items":[{"id":"x","title":"done","status":"completed","position":"00000000000000000001"}]}
        """#
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.success(statusCode: 200, body: Data(body.utf8))])
        )

        let tasks = try await client.fetchTasks(in: "list-1")
        XCTAssertEqual(tasks.first?.status, .completed)
    }

    // MARK: - 401 retry

    func testRetriesOnceWithRefreshedTokenAfter401() async throws {
        let body = #"{"items":[{"id":"a","title":"A","updated":"2026-05-15T00:00:00Z"}]}"#
        let http = StubTasksHTTPClient([
            .success(statusCode: 401, body: Data()),
            .success(statusCode: 200, body: Data(body.utf8))
        ])
        let auth = StubTasksAuthorizing()
        let client = GoogleTasksClient(authorizing: auth, http: http)

        let lists = try await client.fetchTaskLists()

        XCTAssertEqual(lists.map(\.id), ["a"])
        XCTAssertEqual(auth.refreshedTokenCalls, 1, "must refresh exactly once on 401")
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(
            http.requests[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer tok-1"
        )
        XCTAssertEqual(
            http.requests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer tok-2"
        )
    }

    func testThrowsUnauthorizedWhenStill401AfterRefresh() async {
        let http = StubTasksHTTPClient([
            .success(statusCode: 401, body: Data()),
            .success(statusCode: 401, body: Data())
        ])
        let client = GoogleTasksClient(authorizing: StubTasksAuthorizing(), http: http)

        do {
            _ = try await client.fetchTaskLists()
            XCTFail("expected GoogleTasksError.unauthorized")
        } catch GoogleTasksError.unauthorized {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testThrowsUnauthorizedWhenRefreshItselfFails() async {
        let http = StubTasksHTTPClient([.success(statusCode: 401, body: Data())])
        let auth = StubTasksAuthorizing(refreshError: NSError(domain: "test", code: 1))
        let client = GoogleTasksClient(authorizing: auth, http: http)

        do {
            _ = try await client.fetchTaskLists()
            XCTFail("expected GoogleTasksError.unauthorized")
        } catch GoogleTasksError.unauthorized {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Errors

    func testHTTPErrorSurfacesStatusCode() async {
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.success(statusCode: 503, body: Data())])
        )

        do {
            _ = try await client.fetchTaskLists()
            XCTFail("expected http error")
        } catch GoogleTasksError.http(let status) {
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testDecodingFailureThrowsDecodingFailed() async {
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.success(statusCode: 200, body: Data("not json".utf8))])
        )

        do {
            _ = try await client.fetchTaskLists()
            XCTFail("expected decoding error")
        } catch GoogleTasksError.decodingFailed {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testTransportErrorIsWrapped() async {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let client = GoogleTasksClient(
            authorizing: StubTasksAuthorizing(),
            http: StubTasksHTTPClient([.failure(underlying)])
        )

        do {
            _ = try await client.fetchTaskLists()
            XCTFail("expected transport error")
        } catch GoogleTasksError.transport {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Endpoints

    func testTaskListEndpointShape() {
        let url = GoogleTasksEndpoints.taskLists(pageToken: nil)
        XCTAssertEqual(url.host, "tasks.googleapis.com")
        XCTAssertTrue(url.path.hasSuffix("/users/@me/lists"))
        XCTAssertTrue(url.query?.contains("maxResults=100") == true)
    }

    func testTasksEndpointEscapesListID() {
        let url = GoogleTasksEndpoints.tasks(in: "id with space", pageToken: nil)
        XCTAssertTrue(url.path.contains("id%20with%20space") || url.path.contains("id with space"))
        XCTAssertTrue(url.query?.contains("showCompleted=false") == true)
    }
}
