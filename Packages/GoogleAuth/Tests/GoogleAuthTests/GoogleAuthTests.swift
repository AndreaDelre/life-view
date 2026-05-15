import XCTest
@testable import GoogleAuth

final class GoogleAuthTests: XCTestCase {
    func testAssemblyBuildsAStore() {
        // Smoke test: the production-default wiring should at least compile
        // and not crash on construction. Behaviour is covered by the
        // dedicated suites below.
        _ = GoogleAuthAssembly.makeAccountStore(clientID: "fake.apps.googleusercontent.com")
    }
}
