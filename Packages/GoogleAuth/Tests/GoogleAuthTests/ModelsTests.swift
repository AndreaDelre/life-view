import XCTest
@testable import GoogleAuth

final class TokenSetTests: XCTestCase {
    func testIsExpiredWhenExpirationIsInThePast() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let tokens = TokenSet(
            accessToken: "a",
            refreshToken: "r",
            accessTokenExpiresAt: now.addingTimeInterval(-10)
        )

        XCTAssertTrue(tokens.isAccessTokenExpired(now: now))
    }

    func testIsExpiredWithinSafetyMargin() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // 30 s in the future, but our default margin is 60 s -> considered expired.
        let tokens = TokenSet(
            accessToken: "a",
            refreshToken: "r",
            accessTokenExpiresAt: now.addingTimeInterval(30)
        )

        XCTAssertTrue(tokens.isAccessTokenExpired(now: now))
    }

    func testNotExpiredWellInTheFuture() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let tokens = TokenSet(
            accessToken: "a",
            refreshToken: "r",
            accessTokenExpiresAt: now.addingTimeInterval(3_600)
        )

        XCTAssertFalse(tokens.isAccessTokenExpired(now: now))
    }

    func testDescriptionRedactsTokens() {
        let tokens = TokenSet(
            accessToken: "super-secret-access",
            refreshToken: "super-secret-refresh",
            accessTokenExpiresAt: Date()
        )

        let desc = "\(tokens)"
        let debugDesc = String(reflecting: tokens)
        XCTAssertFalse(desc.contains("super-secret"), "description leaked a token: \(desc)")
        XCTAssertFalse(debugDesc.contains("super-secret"), "debugDescription leaked a token")
    }
}

final class AccountProfileTests: XCTestCase {
    func testCodableRoundTripWithAllFields() throws {
        let profile = AccountProfile(
            email: "ada@example.com",
            displayName: "Ada Lovelace",
            avatarURL: URL(string: "https://example.com/a.png")
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AccountProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }

    func testCodableRoundTripWithoutOptionals() throws {
        let profile = AccountProfile(email: "ada@example.com", displayName: nil, avatarURL: nil)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AccountProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }
}
