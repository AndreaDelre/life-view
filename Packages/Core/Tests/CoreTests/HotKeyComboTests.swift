import AppKit
import XCTest
@testable import Core

final class HotKeyComboTests: XCTestCase {
    func testDefaultIsOptionCommandL() {
        let combo = HotKeyCombo.default
        XCTAssertTrue(combo.modifiers.contains(.option))
        XCTAssertTrue(combo.modifiers.contains(.command))
        XCTAssertFalse(combo.modifiers.contains(.shift))
        XCTAssertFalse(combo.modifiers.contains(.control))
        XCTAssertEqual(combo.keyCode, 0x25)
    }

    func testDisplayStringOrdersModifiersMacStyle() {
        // ⌃⌥⇧⌘ then key — order matters for human readability.
        let combo = HotKeyCombo(
            modifiers: [.command, .shift, .option, .control],
            keyCode: 0x25
        )
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘L")
    }

    func testDisplayStringForDefault() {
        XCTAssertEqual(HotKeyCombo.default.displayString, "⌥⌘L")
    }

    func testDisplayStringForUnmappedKeyCodeFallsBackToHex() {
        let combo = HotKeyCombo(modifiers: [.command], keyCode: 0xAB)
        XCTAssertEqual(combo.displayString, "⌘#0xAB")
    }

    func testModifiersAreStrippedOfNonDeviceIndependentBits() {
        // Pass in raw bits including device-dependent flags; those should be filtered.
        let raw = NSEvent.ModifierFlags(rawValue: 0xFFFF_FFFF)
        let combo = HotKeyCombo(modifiers: raw, keyCode: 0x25)
        let allowed: NSEvent.ModifierFlags = .deviceIndependentFlagsMask
        XCTAssertEqual(combo.modifiers.rawValue & ~allowed.rawValue, 0)
    }

    func testCodableRoundTrip() throws {
        let original = HotKeyCombo(modifiers: [.option, .command, .shift], keyCode: 0x25)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEquality() {
        let lhs = HotKeyCombo(modifiers: [.option, .command], keyCode: 0x25)
        let rhs = HotKeyCombo(modifiers: [.command, .option], keyCode: 0x25)
        XCTAssertEqual(lhs, rhs, "Modifier order in OptionSet must not affect equality.")
    }
}
