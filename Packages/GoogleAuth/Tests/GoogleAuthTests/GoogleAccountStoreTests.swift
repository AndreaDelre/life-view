import XCTest
@testable import GoogleAuth

final class GoogleAccountStoreTests: XCTestCase {
    private let accountID = AccountID("sub-123")
    private let profile = AccountProfile(
        email: "ada@example.com",
        displayName: "Ada",
        avatarURL: nil
    )

    private func makeAccount() -> Account {
        Account(id: accountID, profile: profile)
    }

    private func makeFreshTokens(expiresIn seconds: TimeInterval, now: Date) -> TokenSet {
        TokenSet(
            accessToken: "access-original",
            refreshToken: "refresh-original",
            accessTokenExpiresAt: now.addingTimeInterval(seconds)
        )
    }

    // MARK: - load/save/remove

    func testLoadAccountReturnsNilWhenEmpty() async throws {
        let store = GoogleAccountStore(
            keychain: InMemoryKeychainStore(),
            activeAccount: InMemoryActiveAccountStorage(),
            refresher: StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: StubTokenRevoker()
        )

        let account = try await store.loadAccount()
        XCTAssertNil(account)
    }

    func testSaveThenLoadReturnsAccount() async throws {
        let store = GoogleAccountStore(
            keychain: InMemoryKeychainStore(),
            activeAccount: InMemoryActiveAccountStorage(),
            refresher: StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: StubTokenRevoker()
        )
        let now = Date()
        let account = makeAccount()
        let tokens = makeFreshTokens(expiresIn: 3_600, now: now)

        try await store.saveAccount(account, tokens: tokens)

        let loaded = try await store.loadAccount()
        XCTAssertEqual(loaded, account)
    }

    func testLoadAccountSelfHealsStalePointer() async throws {
        // ActiveAccountStorage points at an ID that doesn't exist in the
        // Keychain — likely a previous test or a manual `security delete`.
        let active = InMemoryActiveAccountStorage(AccountID("ghost"))
        let store = GoogleAccountStore(
            keychain: InMemoryKeychainStore(),
            activeAccount: active,
            refresher: StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: StubTokenRevoker()
        )

        let loaded = try await store.loadAccount()
        XCTAssertNil(loaded)
        XCTAssertNil(active.read(), "stale active pointer should have been cleared")
    }

    func testRemoveAccountRevokesAndPurges() async throws {
        let keychain = InMemoryKeychainStore()
        let active = InMemoryActiveAccountStorage()
        let revoker = StubTokenRevoker()
        let store = GoogleAccountStore(
            keychain: keychain,
            activeAccount: active,
            refresher: StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: revoker
        )
        try await store.saveAccount(makeAccount(), tokens: makeFreshTokens(expiresIn: 3_600, now: Date()))

        try await store.removeAccount()

        XCTAssertEqual(revoker.calls, ["refresh-original"])
        XCTAssertNil(active.read())
        XCTAssertTrue(keychain.snapshot.isEmpty, "Keychain should be empty after disconnect")
    }

    func testRemoveAccountTolerantToRevocationFailure() async throws {
        let keychain = InMemoryKeychainStore()
        let active = InMemoryActiveAccountStorage()
        let revoker = StubTokenRevoker(.failure(GoogleOAuthError.http(statusCode: 503)))
        let store = GoogleAccountStore(
            keychain: keychain,
            activeAccount: active,
            refresher: StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: revoker
        )
        try await store.saveAccount(makeAccount(), tokens: makeFreshTokens(expiresIn: 3_600, now: Date()))

        try await store.removeAccount()

        XCTAssertNil(active.read())
        XCTAssertTrue(keychain.snapshot.isEmpty)
    }

    // MARK: - validAccessToken / refresh

    func testValidAccessTokenThrowsWhenNoAccount() async {
        let store = GoogleAccountStore(
            keychain: InMemoryKeychainStore(),
            activeAccount: InMemoryActiveAccountStorage(),
            refresher: StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: StubTokenRevoker()
        )

        do {
            _ = try await store.validAccessToken()
            XCTFail("expected GoogleOAuthError.noAccount")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .noAccount)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testValidAccessTokenReturnsCachedWhenFresh() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let refresher = StubTokenRefresher(.failure(GoogleOAuthError.http(statusCode: 500)))
        let store = GoogleAccountStore(
            keychain: InMemoryKeychainStore(),
            activeAccount: InMemoryActiveAccountStorage(),
            refresher: refresher,
            revoker: StubTokenRevoker(),
            clock: { now }
        )
        try await store.saveAccount(
            makeAccount(),
            tokens: makeFreshTokens(expiresIn: 3_600, now: now)
        )

        let token = try await store.validAccessToken()

        XCTAssertEqual(token, "access-original")
        XCTAssertEqual(refresher.calls, [], "refresher must not be hit for a fresh token")
    }

    func testValidAccessTokenRefreshesWhenExpired() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let refresher = StubTokenRefresher(.success(
            RefreshedAccessToken(
                accessToken: "access-refreshed",
                expiresAt: now.addingTimeInterval(3_600)
            )
        ))
        let keychain = InMemoryKeychainStore()
        let store = GoogleAccountStore(
            keychain: keychain,
            activeAccount: InMemoryActiveAccountStorage(),
            refresher: refresher,
            revoker: StubTokenRevoker(),
            clock: { now }
        )
        // Already-expired token.
        try await store.saveAccount(
            makeAccount(),
            tokens: makeFreshTokens(expiresIn: -10, now: now)
        )

        let token = try await store.validAccessToken()

        XCTAssertEqual(token, "access-refreshed")
        XCTAssertEqual(refresher.calls, ["refresh-original"])

        // Refreshed tokens should be persisted: a second call must NOT
        // re-hit the refresher.
        _ = try await store.validAccessToken()
        XCTAssertEqual(refresher.calls.count, 1, "refresh must be cached")
    }

    func testValidAccessTokenPropagatesRefreshFailure() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let refresher = StubTokenRefresher(.failure(GoogleOAuthError.http(statusCode: 401)))
        let store = GoogleAccountStore(
            keychain: InMemoryKeychainStore(),
            activeAccount: InMemoryActiveAccountStorage(),
            refresher: refresher,
            revoker: StubTokenRevoker(),
            clock: { now }
        )
        try await store.saveAccount(
            makeAccount(),
            tokens: makeFreshTokens(expiresIn: -10, now: now)
        )

        do {
            _ = try await store.validAccessToken()
            XCTFail("expected refresh failure to surface")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .http(statusCode: 401))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
