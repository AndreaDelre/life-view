import AppKit

/// Owns the menu bar item that toggles the panel.
///
/// Uses a left-click button action rather than an `NSMenu` so the click is a
/// pure toggle (no popup). Right-click could later open a small menu with
/// "Preferences…" / "Quit" — out of scope for P1.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let onToggle: @MainActor () -> Void

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "checklist",
                accessibilityDescription: "LifeView"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
        }
    }

    @objc
    private func statusItemClicked() {
        onToggle()
    }
}
