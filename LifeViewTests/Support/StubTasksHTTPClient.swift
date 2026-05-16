import Foundation
import GoogleTasksClient

/// Records requests and replays a queued response. Mirrors the test
/// stub used inside `GoogleTasksClientTests` — re-defined here because
/// test-target code can't be shared across modules.
final class StubTasksHTTPClient: TasksHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    private let queue = DispatchQueue(label: "StubTasksHTTPClient.lifeview")
    private var _responses: [Outcome]
    private var _requests: [URLRequest] = []

    init(_ responses: [Outcome]) {
        _responses = responses
    }

    var requests: [URLRequest] {
        queue.sync { _requests }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try queue.sync {
            _requests.append(request)
            guard !_responses.isEmpty else {
                throw GoogleTasksError.transport(message: "stub: no scripted response left")
            }
            switch _responses.removeFirst() {
            case let .failure(error):
                throw error
            case let .success(status, body):
                // swiftlint:disable:next force_unwrapping
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (body, response)
            }
        }
    }
}
