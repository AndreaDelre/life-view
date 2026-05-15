import Foundation
@testable import GoogleTasksClient

/// Auth seam stub — counts how many times the client asks for a token vs.
/// for a forcibly-refreshed one.
final class StubTasksAuthorizing: TasksAuthorizing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StubTasksAuthorizing")
    private var _accessToken: String
    private var _refreshedToken: String
    private var _refreshError: Error?
    private(set) var accessTokenCalls = 0
    private(set) var refreshedTokenCalls = 0

    init(accessToken: String = "tok-1", refreshedToken: String = "tok-2", refreshError: Error? = nil) {
        self._accessToken = accessToken
        self._refreshedToken = refreshedToken
        self._refreshError = refreshError
    }

    func accessToken() async throws -> String {
        queue.sync {
            accessTokenCalls += 1
            return _accessToken
        }
    }

    func refreshedAccessToken() async throws -> String {
        try queue.sync {
            refreshedTokenCalls += 1
            if let error = _refreshError { throw error }
            // After a refresh the cached token is rotated.
            _accessToken = _refreshedToken
            return _refreshedToken
        }
    }
}
