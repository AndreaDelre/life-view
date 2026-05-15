import Foundation
@testable import GoogleAuth

/// Refresher stub with a tunable response and call counting.
final class StubTokenRefresher: TokenRefreshing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StubTokenRefresher")
    private var _calls: [String] = []
    private var _response: Result<RefreshedAccessToken, Error>

    init(_ response: Result<RefreshedAccessToken, Error>) {
        self._response = response
    }

    func setResponse(_ response: Result<RefreshedAccessToken, Error>) {
        queue.sync { _response = response }
    }

    var calls: [String] {
        queue.sync { _calls }
    }

    func refresh(refreshToken: String) async throws -> RefreshedAccessToken {
        try queue.sync {
            _calls.append(refreshToken)
            return try _response.get()
        }
    }
}

/// Revoker stub.
final class StubTokenRevoker: TokenRevoking, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StubTokenRevoker")
    private var _calls: [String] = []
    private var _response: Result<Void, Error>

    init(_ response: Result<Void, Error> = .success(())) {
        self._response = response
    }

    var calls: [String] {
        queue.sync { _calls }
    }

    func setResponse(_ response: Result<Void, Error>) {
        queue.sync { _response = response }
    }

    func revoke(token: String) async throws {
        try queue.sync {
            _calls.append(token)
            return try _response.get()
        }
    }
}

/// In-memory ``ActiveAccountStorage`` fake.
final class InMemoryActiveAccountStorage: ActiveAccountStorage, @unchecked Sendable {
    private let queue = DispatchQueue(label: "InMemoryActiveAccountStorage")
    private var value: AccountID?

    init(_ initial: AccountID? = nil) {
        self.value = initial
    }

    func read() -> AccountID? {
        queue.sync { value }
    }

    func write(_ accountID: AccountID?) {
        queue.sync { value = accountID }
    }
}
