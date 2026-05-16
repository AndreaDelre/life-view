import XCTest
@testable import DesignSystem

/// Sanity tests for design tokens. They mostly assert the scale stays
/// monotonic and the named values match the documented 4pt rhythm so
/// an accidental edit (typo, swapped value) gets caught in CI.
final class TokensTests: XCTestCase {
    // MARK: - Spacing

    func testSpacingScaleIs4ptBased() {
        XCTAssertEqual(Spacing.xs, 4)
        XCTAssertEqual(Spacing.sm, 8)
        XCTAssertEqual(Spacing.md, 12)
        XCTAssertEqual(Spacing.lg, 16)
        XCTAssertEqual(Spacing.xl, 24)
        XCTAssertEqual(Spacing.xxl, 32)
    }

    func testSpacingScaleIsMonotonic() {
        let scale = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl]
        XCTAssertEqual(scale, scale.sorted())
    }

    // MARK: - Radius

    func testRadiusScaleValues() {
        XCTAssertEqual(Radius.sm, 4)
        XCTAssertEqual(Radius.md, 8)
        XCTAssertEqual(Radius.lg, 12)
    }

    func testRadiusScaleIsMonotonic() {
        let scale = [Radius.sm, Radius.md, Radius.lg]
        XCTAssertEqual(scale, scale.sorted())
    }
}
