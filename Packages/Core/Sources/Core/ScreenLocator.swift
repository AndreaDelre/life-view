import AppKit
import Foundation

/// Selects the screen on which the panel should appear.
///
/// The panel is expected to slide in on the screen the user is *currently looking at*,
/// which on macOS is best approximated by "the screen containing the mouse cursor"
/// — not ``NSScreen/main`` which tracks the focused window instead.
///
/// This type is intentionally a thin, fully testable wrapper around the geometry
/// decision so the multi-screen logic can be exercised without a real display.
public enum ScreenLocator {
    /// Returns the screen whose `frame` contains the given mouse location, or the
    /// first screen of the list if none does (defensive fallback — should never
    /// happen in practice since `NSScreen.screens` covers the entire desktop).
    ///
    /// Pure function: takes its inputs explicitly so tests can feed in synthetic
    /// frames without hitting AppKit.
    public static func screen(
        containing mouseLocation: CGPoint,
        among screens: [CGRect]
    ) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let index = screens.firstIndex(where: { $0.contains(mouseLocation) }) {
            return index
        }
        return 0
    }

    /// Convenience wrapper that resolves the active ``NSScreen`` using the real
    /// mouse location and the list of attached screens.
    @MainActor
    public static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        guard let index = screen(containing: mouse, among: frames) else { return nil }
        return screens[index]
    }
}
