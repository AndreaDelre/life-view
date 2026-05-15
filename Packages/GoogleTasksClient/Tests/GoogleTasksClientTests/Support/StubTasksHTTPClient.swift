import Foundation
@testable import GoogleTasksClient

/// Records every request and replays a queued response.
///
/// `responses` is a queue: each `send` call pops the head. If the queue
/// is empty when called the stub fails the test by throwing an
/// unmistakable error — a missing scripted response is almost always a
/// test bug, not a runtime case worth re-attempting.
final class StubTasksHTTPClient: TasksHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    private let queue = DispatchQueue(label: "StubTasksHTTPClient")
    private var _responses: [Outcome]
    private var _requests: [URLRequest] = []

    init(_ responses: [Outcome]) {
        self._responses = responses
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
            case .failure(let error):
                throw error
            case .success(let status, let body):
                // swiftlint:disable:next force_unwrapping
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (body, response)
            }
        }
    }
}
