import XCTest
@testable import GoogleAuth

final class MonoAccountMigrationTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func legacySecrets(subject: String? = nil) -> StoredAccountSecrets {
        StoredAccountSecrets(
            profile: AccountProfile(
                subject: subject,
                email: "ada@example.com",
                displayName: "Ada",
                avatarURL: nil
            ),
            tokens: TokenSet(
                accessToken: "access",
                refreshToken: "refresh",
                accessTokenExpiresAt: now.addingTimeInterval(3_600)
            )
        )
    }

    func testRunReturnsNilWhenNoLegacyPointer() throws {
        let migration = MonoAccountMigration(
            keychain: InMemoryKeychainStore(),
            legacy: InMemoryLegacyPointer(nil)
        )
        XCTAssertNil(try migration.runIfNeeded())
    }

    func testRunReturnsNilAndClearsPointerWhenKeychainItemIsMissing() throws {
        let pointer = InMemoryLegacyPointer("legacy-sub")
        let migration = MonoAccountMigration(
            keychain: InMemoryKeychainStore(),
            legacy: pointer
        )

        XCTAssertNil(try migration.runIfNeeded())
        XCTAssertNil(pointer.read(), "stale pointer must be cleared so the migration stops trying")
    }

    func testRunMigratesLegacyRecord() throws {
        let keychain = InMemoryKeychainStore()
        let pointer = InMemoryLegacyPointer("legacy-sub")
        try keychain.write(legacySecrets(), key: "legacy-sub")

        let migration = MonoAccountMigration(keychain: keychain, legacy: pointer)

        let migrated = try XCTUnwrap(try migration.runIfNeeded())

        XCTAssertNotEqual(migrated.account.id.rawValue, "legacy-sub", "new id must be a fresh UUID")
        XCTAssertEqual(migrated.account.subject, "legacy-sub", "legacy id is now the subject")
        XCTAssertEqual(migrated.account.profile.email, "ada@example.com")
        XCTAssertEqual(migrated.tokens.refreshToken, "refresh")

        // Legacy Keychain entry must be gone; pointer cleared.
        XCTAssertNil(try keychain.read(StoredAccountSecrets.self, key: "legacy-sub"))
        XCTAssertNil(pointer.read())
    }

    func testRunIsIdempotent() throws {
        let keychain = InMemoryKeychainStore()
        let pointer = InMemoryLegacyPointer("legacy-sub")
        try keychain.write(legacySecrets(), key: "legacy-sub")

        let migration = MonoAccountMigration(keychain: keychain, legacy: pointer)

        _ = try migration.runIfNeeded()

        // Second invocation: nothing left to do.
        XCTAssertNil(try migration.runIfNeeded())
    }

    func testMigrationPreservesSubjectWhenAlreadyPresent() throws {
        // Edge case: a forward-compatible build had already written the
        // subject field. Migration should keep the existing subject
        // rather than overwriting it with the legacy id.
        let keychain = InMemoryKeychainStore()
        let pointer = InMemoryLegacyPointer("legacy-sub")
        try keychain.write(legacySecrets(subject: "real-sub"), key: "legacy-sub")

        let migration = MonoAccountMigration(keychain: keychain, legacy: pointer)
        let migrated = try XCTUnwrap(try migration.runIfNeeded())

        XCTAssertEqual(migrated.account.subject, "real-sub")
    }
}
