import AppKit

/// A platform-agnostic representation of a global hotkey combination.
///
/// Stores the raw virtual keycode (Carbon / AppKit ``NSEvent`` `keyCode`) and a set
/// of modifier flags. The combo is pure data — registration with the OS is the job
/// of the `HotKey` module in the app target.
///
/// `HotKeyCombo` is intentionally `Sendable` so it can be passed across actor
/// boundaries (e.g. between the panel controller and the hotkey registrar).
public struct HotKeyCombo: Hashable, Sendable, Codable {
    /// Modifier flags expressed using ``NSEvent/ModifierFlags`` device-independent bits.
    public let modifiers: NSEvent.ModifierFlags
    /// Virtual key code (matches Carbon `kVK_*` constants and ``NSEvent/keyCode``).
    public let keyCode: UInt16

    public init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        self.keyCode = keyCode
    }

    // MARK: - Hashable / Equatable
    // Manual conformance because NSEvent.ModifierFlags is an OptionSet (UInt raw value)
    // that is itself not Hashable on the Swift type-checker side.

    public static func == (lhs: HotKeyCombo, rhs: HotKeyCombo) -> Bool {
        lhs.modifiers.rawValue == rhs.modifiers.rawValue && lhs.keyCode == rhs.keyCode
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(modifiers.rawValue)
        hasher.combine(keyCode)
    }

    /// Default hotkey for toggling the panel: `⌥⌘L`.
    public static let `default` = HotKeyCombo(
        modifiers: [.option, .command],
        keyCode: 0x25 // kVK_ANSI_L
    )

    // MARK: - Codable (manual: NSEvent.ModifierFlags is OptionSet of UInt)

    private enum CodingKeys: String, CodingKey {
        case modifiers
        case keyCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(UInt.self, forKey: .modifiers)
        let key = try container.decode(UInt16.self, forKey: .keyCode)
        self.init(modifiers: NSEvent.ModifierFlags(rawValue: raw), keyCode: key)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encode(keyCode, forKey: .keyCode)
    }
}

public extension HotKeyCombo {
    /// Human-readable symbol string, e.g. `⌥⌘L`.
    ///
    /// Order of modifier symbols follows the macOS convention: `⌃⌥⇧⌘` then the key.
    var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts
    }

    /// Maps a small subset of virtual keycodes to their printable representation.
    ///
    /// Unmapped keys fall back to a hex form (`#0xNN`) — good enough for a
    /// developer-facing display until P7 ships a real keycode → name table.
    static func keyName(for keyCode: UInt16) -> String {
        keyNameTable[keyCode] ?? String(format: "#0x%02X", keyCode)
    }

    /// Static keycode → glyph lookup. A dictionary keeps cyclomatic complexity
    /// flat (vs. a giant switch) and lets future keymaps merge in cleanly.
    private static let keyNameTable: [UInt16: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E",
        0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J",
        0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O",
        0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
        0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y",
        0x06: "Z",
        0x31: "Space", 0x24: "Return", 0x35: "Esc", 0x30: "Tab",
    ]
}
