import XCTest
@testable import GoogleAuth

final class AccountStoreTests: XCTestCase {
    private func makeStore(
        keychain: KeychainStoring = InMemoryKeychainStore(),
        indexStorage: AccountIndexStorage = InMemoryAccountIndexStorage(),
        refresher: TokenRefreshing? = nil,
        revoker: TokenRevoking? = nil,
        migrator: MonoAccountMigrating? = nil,
        now: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    ) -> AccountStore {
        AccountStore(
            keychain: keychain,
            indexStorage: indexStorage,
            refresher: refresher ?? StubTokenRefresher(.failure(GoogleOAuthError.noAccount)),
            revoker: revoker ?? StubTokenRevoker(),
            migrator: migrator,
            clock: { now }
        )
    }

    private func account(id: String = UUID().uuidString, subject: String = "sub-1", email: String = "ada@example.com") -> Account {
        Account(
            id: AccountID(id),
            profile: AccountProfile(subject: subject, email: email, displayName: nil, avatarURL: nil)
        )
    }

    private func tokens(now: Date, expiresIn: TimeInterval = 3_600, refreshToken: String = "refresh-1") -> TokenSet {
        TokenSet(
            accessToken: "access-1",
            refreshToken: refreshToken,
            accessTokenExpiresAt: now.addingTimeInterval(expiresIn)
        )
    }

    // MARK: - Load

    func testLoadAllOnEmptyStateReturnsEmptySnapshot() async throws {
        let store = makeStore()
        let snapshot = try await store.loadAll()
        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertNil(snapshot.selectedID)
    }

    func testLoadAllSelfHealsDanglingIndex() async throws {
        // Index points at an id whose Keychain item is gone.
        let keychain = InMemoryKeychainStore()
        let indexStorage = InMemoryAccountIndexStorage(
            AccountIndex(orderedIDs: [AccountID("ghost")], selectedID: AccountID("ghost"))
        )
        let store = makeStore(keychain: keychain, indexStorage: indexStorage)

        let snapshot = try await store.loadAll()

        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertNil(snapshot.selectedID)
        XCTAssertEqual(indexStorage.read().orderedIDs, [], "dangling id should have been pruned from the index")
    }

    // MARK: - Add

    func testAddFirstAccountSelectsIt() async throws {
        let store = makeStore()
        let acc = account()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        let snapshot = try await store.addAccount(acc, tokens: tokens(now: now))

        XCTAssertEqual(snapshot.accounts, [acc])
        XCTAssertEqual(snapshot.selectedID, acc.id)
    }

    func testAddSecondAccountAppendsAndSelectsIt() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let alpha = account(subject: "sub-A", email: "a@example.com")
        let bravo = account(subject: "sub-B", email: "b@example.com")

        _ = try await store.addAccount(alpha, tokens: tokens(now: now))
        let snapshot = try await store.addAccount(bravo, tokens: tokens(now: now))

        XCTAssertEqual(snapshot.accounts.map(\.id), [alpha.id, bravo.id])
        XCTAssertEqual(snapshot.selectedID, bravo.id, "newly-added account should become the selected one")
    }

    func testAddAccountWithMatchingSubjectKeepsExistingLocalID() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let original = account(subject: "sub-shared", email: "old@example.com")
        _ = try await store.addAccount(original, tokens: tokens(now: now, refreshToken: "r-old"))

        // Re-sign-in with a new local id but the same subject (typical
        // OAuth re-consent flow).
        let reAuth = Account(
            id: AccountID.make(),
            profile: AccountProfile(
                subject: "sub-shared",
                email: "new@example.com",
                displayName: "Updated",
                avatarURL: nil
            )
        )
        let snapshot = try await store.addAccount(
            reAuth,
            tokens: tokens(now: now, refreshToken: "r-new")
        )

        XCTAssertEqual(snapshot.accounts.count, 1, "matching subject must dedupe")
        XCTAssertEqual(snapshot.accounts[0].id, original.id, "local id must be preserved")
        XCTAssertEqual(snapshot.accounts[0].profile.email, "new@example.com", "profile should be updated")
        XCTAssertEqual(snapshot.selectedID, original.id)
    }

    // MARK: - Remove

    func testRemoveSelectedAccountReselectsNext() async throws {
        let revoker = StubTokenRevoker()
        let store = makeStore(revoker: revoker)
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let alpha = account(subject: "sub-A", email: "a@example.com")
        let bravo = account(subject: "sub-B", email: "b@example.com")
        _ = try await store.addAccount(alpha, tokens: tokens(now: now, refreshToken: "r-a"))
        _ = try await store.addAccount(bravo, tokens: tokens(now: now, refreshToken: "r-b"))
        // b is selected by virtue of being added last.

        let snapshot = try await store.removeAccount(bravo.id)

        XCTAssertEqual(snapshot.accounts.map(\.id), [alpha.id])
        XCTAssertEqual(snapshot.selectedID, alpha.id, "selection should fall back to the surviving account")
        XCTAssertEqual(revoker.calls, ["r-b"])
    }

    func testRemoveLastAccountLeavesEmptySelection() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let acc = account()
        _ = try await store.addAccount(acc, tokens: tokens(now: now))

        let snapshot = try await store.removeAccount(acc.id)

        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertNil(snapshot.selectedID)
    }

    func testRemoveAccountToleratesRevocationFailure() async throws {
        let revoker = StubTokenRevoker(.failure(GoogleOAuthError.http(statusCode: 503)))
        let keychain = InMemoryKeychainStore()
        let store = makeStore(keychain: keychain, revoker: revoker)
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let acc = account()
        _ = try await store.addAccount(acc, tokens: tokens(now: now))

        let snapshot = try await store.removeAccount(acc.id)

        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertTrue(keychain.snapshot.isEmpty, "local purge must proceed even if revoke fails")
    }

    // MARK: - Select / rename

    func testSelectChangesSelection() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let alpha = account(subject: "sub-A", email: "a@example.com")
        let bravo = account(subject: "sub-B", email: "b@example.com")
        _ = try await store.addAccount(alpha, tokens: tokens(now: now))
        _ = try await store.addAccount(bravo, tokens: tokens(now: now))
        // b selected.

        let snapshot = try await store.select(alpha.id)
        XCTAssertEqual(snapshot.selectedID, alpha.id)
    }

    func testSelectUnknownIDThrows() async throws {
        let store = makeStore()
        _ = try await store.addAccount(account(), tokens: tokens(now: Date()))

        do {
            _ = try await store.select(AccountID("does-not-exist"))
            XCTFail("expected noAccount")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .noAccount)
        }
    }

    func testRenameOverridesDisplayName() async throws {
        let store = makeStore()
        let acc = account()
        _ = try await store.addAccount(acc, tokens: tokens(now: Date()))

        let snapshot = try await store.renameAccount(acc.id, displayName: "Custom")

        XCTAssertEqual(snapshot.accounts.first?.profile.displayName, "Custom")
    }

    func testRenameWithEmptyClearsDisplayName() async throws {
        let store = makeStore()
        let acc = account()
        _ = try await store.addAccount(acc, tokens: tokens(now: Date()))
        _ = try await store.renameAccount(acc.id, displayName: "Custom")

        let snapshot = try await store.renameAccount(acc.id, displayName: "")
        XCTAssertNil(snapshot.accounts.first?.profile.displayName)
    }

    // MARK: - Token access

    func testValidAccessTokenReturnsCachedWhenFresh() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let refresher = StubTokenRefresher(.failure(GoogleOAuthError.http(statusCode: 500)))
        let store = makeStore(refresher: refresher, now: now)
        let acc = account()
        _ = try await store.addAccount(acc, tokens: tokens(now: now))

        let token = try await store.validAccessToken(for: acc.id)

        XCTAssertEqual(token, "access-1")
        XCTAssertEqual(refresher.calls, [], "refresher must not run for a fresh token")
    }

    func testValidAccessTokenRefreshesPerAccountIndependently() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let refresher = StubTokenRefresher(responses: [
            .success(RefreshedAccessToken(accessToken: "fresh-A", expiresAt: now.addingTimeInterval(3_600))),
            .success(RefreshedAccessToken(accessToken: "fresh-B", expiresAt: now.addingTimeInterval(3_600)))
        ])
        let store = makeStore(refresher: refresher, now: now)
        let alpha = account(subject: "sub-A", email: "a@example.com")
        let bravo = account(subject: "sub-B", email: "b@example.com")
        _ = try await store.addAccount(alpha, tokens: tokens(now: now, expiresIn: -10, refreshToken: "r-A"))
        _ = try await store.addAccount(bravo, tokens: tokens(now: now, expiresIn: -10, refreshToken: "r-B"))

        let tokenA = try await store.validAccessToken(for: alpha.id)
        let tokenB = try await store.validAccessToken(for: bravo.id)

        XCTAssertEqual(tokenA, "fresh-A")
        XCTAssertEqual(tokenB, "fresh-B")
        XCTAssertEqual(refresher.calls.sorted(), ["r-A", "r-B"])
    }

    func testForceRefreshAccessTokenAlwaysRefreshes() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let refresher = StubTokenRefresher(.success(
            RefreshedAccessToken(accessToken: "rotated", expiresAt: now.addingTimeInterval(3_600))
        ))
        let store = makeStore(refresher: refresher, now: now)
        let acc = account()
        _ = try await store.addAccount(acc, tokens: tokens(now: now))

        let token = try await store.forceRefreshAccessToken(for: acc.id)

        XCTAssertEqual(token, "rotated")
        XCTAssertEqual(refresher.calls.count, 1)
    }

    func testValidAccessTokenOnUnknownAccountThrows() async {
        let store = makeStore()
        do {
            _ = try await store.validAccessToken(for: AccountID("does-not-exist"))
            XCTFail("expected noAccount")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .noAccount)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Concurrency

    func testConcurrentAddsAreSerialisedAndDoNotCorruptIndex() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        // 10 concurrent adds of distinct accounts; the actor must serialise
        // them. We don't care about the order, only that the index ends up
        // with exactly 10 entries with no duplicates.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                let acc = account(subject: "sub-\(index)", email: "user\(index)@example.com")
                let tok = tokens(now: now)
                group.addTask { _ = try? await store.addAccount(acc, tokens: tok) }
            }
        }

        let snapshot = try await store.loadAll()
        XCTAssertEqual(snapshot.accounts.count, 10)
        XCTAssertEqual(Set(snapshot.accounts.map(\.id)).count, 10, "no duplicate ids")
    }

    // MARK: - Snapshots stream

    func testSnapshotsStreamReplaysCurrentStateAndYieldsOnMutation() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let alpha = account(subject: "sub-A", email: "a@example.com")
        _ = try await store.addAccount(alpha, tokens: tokens(now: now))

        var iterator = await store.snapshots.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial?.accounts.count, 1, "current state should replay on subscription")

        let bravo = account(subject: "sub-B", email: "b@example.com")
        _ = try await store.addAccount(bravo, tokens: tokens(now: now))

        let next = await iterator.next()
        XCTAssertEqual(next?.accounts.count, 2)
        XCTAssertEqual(next?.selectedID, bravo.id)
    }

    // MARK: - Migration

    func testLoadAllRunsMigratorWhenIndexEmpty() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let migrated = MigratedAccount(account: account(), tokens: tokens(now: now))
        let keychain = InMemoryKeychainStore()
        let indexStorage = InMemoryAccountIndexStorage()
        let store = makeStore(
            keychain: keychain,
            indexStorage: indexStorage,
            migrator: StubMigrator(result: .success(migrated))
        )

        let snapshot = try await store.loadAll()

        XCTAssertEqual(snapshot.accounts, [migrated.account])
        XCTAssertEqual(snapshot.selectedID, migrated.account.id)
        XCTAssertEqual(indexStorage.read().orderedIDs, [migrated.account.id])
        XCTAssertNotNil(try keychain.read(StoredAccountSecrets.self, key: migrated.account.id.rawValue))
    }

    func testLoadAllSkipsMigratorWhenIndexNonEmpty() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // Pre-populate index with one account.
        let existing = account()
        let keychain = InMemoryKeychainStore()
        try keychain.write(
            StoredAccountSecrets(profile: existing.profile, tokens: tokens(now: now)),
            key: existing.id.rawValue
        )
        let indexStorage = InMemoryAccountIndexStorage(
            AccountIndex(orderedIDs: [existing.id], selectedID: existing.id)
        )

        // Migrator would explode if called — proves it isn't.
        let store = makeStore(
            keychain: keychain,
            indexStorage: indexStorage,
            migrator: StubMigrator(result: .failure(GoogleOAuthError.noAccount))
        )

        let snapshot = try await store.loadAll()
        XCTAssertEqual(snapshot.accounts, [existing])
    }
}
