import AppKit

/// The borderless, non-activating panel that slides in from the left edge.
///
/// Design notes:
/// - ``canBecomeKey`` is overridden so the panel can receive `keyDown` events
///   (needed to close on Escape) — borderless windows otherwise refuse the
///   key window status.
/// - ``canBecomeMain`` stays `false`: we do not want to be the application's
///   main window or appear in the window menu.
/// - ``acceptsFirstResponder`` is true so the field editor stays on the panel
///   when SwiftUI does not consume the keystroke.
final class LifeViewPanel: NSPanel {
    /// Closure invoked when the user presses Escape while the panel has focus.
    var onEscape: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none // we drive the animation manually
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // 53 == kVK_Escape
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
