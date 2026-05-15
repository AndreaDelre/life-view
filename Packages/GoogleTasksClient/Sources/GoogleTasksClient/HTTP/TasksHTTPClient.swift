import Foundation

/// Network seam for ``GoogleTasksClient``.
///
/// Mirrors the same pattern used by `GoogleAuth.HTTPClient`: a tiny
/// protocol around `URLSession.data(for:)` so unit tests can stub the
/// network without standing up a fake server.
public protocol TasksHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default `URLSession`-backed implementation.
public struct URLSessionTasksHTTPClient: TasksHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleTasksError.transport(message: "Non-HTTP response")
        }
        return (data, http)
    }
}
