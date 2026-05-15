import Foundation

/// Minimal abstraction over the network used by the OAuth pipeline.
///
/// The OAuth refresh/revoke endpoints don't justify pulling in a real HTTP
/// library, but they DO need to be mocked in tests — we don't want the unit
/// test suite hitting `oauth2.googleapis.com`. This protocol is the seam.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default implementation backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleOAuthError.http(statusCode: -1)
        }
        return (data, http)
    }
}
