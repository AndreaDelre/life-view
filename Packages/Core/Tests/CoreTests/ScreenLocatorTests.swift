import CoreGraphics
import XCTest
@testable import Core

final class ScreenLocatorTests: XCTestCase {
    /// Two screens side by side: main (0..1440) and right (1440..3840).
    private let twoScreens: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: 0, width: 2560, height: 1440),
    ]

    func testReturnsNilWhenNoScreens() {
        XCTAssertNil(ScreenLocator.screen(containing: .zero, among: []))
    }

    func testPicksMainScreenWhenMouseInside() {
        let index = ScreenLocator.screen(containing: CGPoint(x: 100, y: 100), among: twoScreens)
        XCTAssertEqual(index, 0)
    }

    func testPicksSecondaryScreenWhenMouseInside() {
        let index = ScreenLocator.screen(containing: CGPoint(x: 2000, y: 500), among: twoScreens)
        XCTAssertEqual(index, 1)
    }

    func testFallsBackToFirstScreenWhenMouseOutsideAll() {
        // Mouse coordinate not covered by any screen — defensive fallback.
        let index = ScreenLocator.screen(containing: CGPoint(x: -100, y: -100), among: twoScreens)
        XCTAssertEqual(index, 0)
    }

    func testBoundaryPointResolvesToFirstContainingScreen() {
        // Shared edge at x=1440 — CGRect.contains is half-open, so x=1440 belongs to screen 1.
        let index = ScreenLocator.screen(containing: CGPoint(x: 1440, y: 100), among: twoScreens)
        XCTAssertEqual(index, 1)
    }
}
