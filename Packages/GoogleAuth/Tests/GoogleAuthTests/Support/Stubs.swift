import Foundation
@testable import GoogleAuth

/// Refresher stub with a tunable response and call counting.
final class StubTokenRefresher: TokenRefreshing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StubTokenRefresher")
    private var _calls: [String] = []
    private var _responses: [Result<RefreshedAccessToken, Error>]

    init(_ response: Result<RefreshedAccessToken, Error>) {
        self._responses = [response]
    }

    init(responses: [Result<RefreshedAccessToken, Error>]) {
        precondition(!responses.isEmpty, "must provide at least one response")
        self._responses = responses
    }

    var calls: [String] {
        queue.sync { _calls }
    }

    func refresh(refreshToken: String) async throws -> RefreshedAccessToken {
        try queue.sync {
            _calls.append(refreshToken)
            let response: Result<RefreshedAccessToken, Error>
            if _responses.count > 1 {
                response = _responses.removeFirst()
            } else {
                response = _responses[0]
            }
            return try response.get()
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

    func revoke(token: String) async throws {
        try queue.sync {
            _calls.append(token)
            return try _response.get()
        }
    }
}

/// In-memory ``AccountIndexStorage`` fake.
final class InMemoryAccountIndexStorage: AccountIndexStorage, @unchecked Sendable {
    private let queue = DispatchQueue(label: "InMemoryAccountIndexStorage")
    private var value: AccountIndex

    init(_ initial: AccountIndex = .empty) {
        self.value = initial
    }

    func read() -> AccountIndex { queue.sync { value } }
    func write(_ index: AccountIndex) { queue.sync { value = index } }
}

/// In-memory legacy mono-account pointer.
final class InMemoryLegacyPointer: LegacyMonoAccountPointer, @unchecked Sendable {
    private let queue = DispatchQueue(label: "InMemoryLegacyPointer")
    private var value: String?

    init(_ initial: String? = nil) { self.value = initial }
    func read() -> String? { queue.sync { value } }
    func clear() { queue.sync { value = nil } }
}

/// Stub migrator with a tunable result.
struct StubMigrator: MonoAccountMigrating {
    let result: Result<MigratedAccount?, Error>
    func runIfNeeded() throws -> MigratedAccount? { try result.get() }
}
