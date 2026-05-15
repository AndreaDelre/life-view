import XCTest
@testable import GoogleAuth

/// Round-trip tests for the ``KeychainStoring`` contract, exercised against
/// the in-memory fake. The real ``KeychainStore`` is covered by a separate
/// integration test below that uses a unique service name to avoid polluting
/// the developer's login keychain.
final class KeychainStoringRoundTripTests: XCTestCase {
    func testReadReturnsNilForUnknownKey() throws {
        let store = InMemoryKeychainStore()
        XCTAssertNil(try store.read(key: "missing"))
    }

    func testWriteThenReadRoundTripsRawBytes() throws {
        let store = InMemoryKeychainStore()
        let payload = Data("hello".utf8)

        try store.write(payload, key: "k")

        XCTAssertEqual(try store.read(key: "k"), payload)
    }

    func testWriteThenReadRoundTripsCodable() throws {
        let store = InMemoryKeychainStore()
        let profile = AccountProfile(
            email: "ada@example.com",
            displayName: "Ada Lovelace",
            avatarURL: URL(string: "https://example.com/a.png")
        )

        try store.write(profile, key: "profile")

        let loaded: AccountProfile? = try store.read(AccountProfile.self, key: "profile")
        XCTAssertEqual(loaded, profile)
    }

    func testWriteOverwritesPreviousValue() throws {
        let store = InMemoryKeychainStore()
        try store.write(Data("a".utf8), key: "k")
        try store.write(Data("b".utf8), key: "k")

        XCTAssertEqual(try store.read(key: "k"), Data("b".utf8))
    }

    func testDeleteRemovesItem() throws {
        let store = InMemoryKeychainStore()
        try store.write(Data("a".utf8), key: "k")

        try store.delete(key: "k")

        XCTAssertNil(try store.read(key: "k"))
    }

    func testDeleteIsIdempotent() throws {
        let store = InMemoryKeychainStore()
        XCTAssertNoThrow(try store.delete(key: "never-existed"))
    }
}

/// Integration test against the platform Keychain. Skipped automatically if
/// the test process can't access the user Keychain (e.g. a hermetic CI
/// runner without a login keychain).
final class KeychainStoreIntegrationTests: XCTestCase {
    private var serviceName: String!

    override func setUp() {
        super.setUp()
        // Unique per-run service name so concurrent test runs and leftovers
        // from a previous crashed run can't collide.
        serviceName = "fr.andreadelre.LifeView.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        // Best-effort cleanup. Failures here just mean the next run has
        // stray items under the unique service name — harmless.
        let store = KeychainStore(service: serviceName)
        try? store.delete(key: "round-trip")
        super.tearDown()
    }

    func testRoundTripWithRealKeychain() throws {
        let store = KeychainStore(service: serviceName)
        let payload = Data("hello".utf8)

        do {
            try store.write(payload, key: "round-trip")
        } catch KeychainError.unhandled(let status) {
            // errSecMissingEntitlement (-34018) etc. — the test host can't
            // talk to the Keychain in this environment.
            try XCTSkipIf(true, "Skipping: Keychain unavailable (OSStatus \(status))")
            return
        }

        XCTAssertEqual(try store.read(key: "round-trip"), payload)

        try store.delete(key: "round-trip")
        XCTAssertNil(try store.read(key: "round-trip"))
    }
}
