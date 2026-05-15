import AppKit
import Core
import SwiftUI

/// Owns the ``LifeViewPanel`` instance, drives the slide animation, and wires
/// the auto-close monitors. Single point of truth for "is the panel visible".
@MainActor
final class PanelController {
    /// Width of the panel in points. Configurable later, fixed for P1.
    static let panelWidth: CGFloat = 380

    private static let animationDuration: TimeInterval = 0.22

    private let panel: LifeViewPanel
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private(set) var isVisible = false

    init() {
        // Start with a placeholder frame; real geometry is computed at open time.
        let initialFrame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: 600)
        panel = LifeViewPanel(contentRect: initialFrame)
        panel.contentView = NSHostingView(rootView: PanelContentView())
        panel.onEscape = { [weak self] in
            self?.hide()
        }
    }

    // MARK: - Public API

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else { return }
        guard let screen = ScreenLocator.screenUnderMouse() ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let targetFrame = NSRect(
            x: visible.minX,
            y: visible.minY,
            width: Self.panelWidth,
            height: visible.height
        )
        // Start off-screen to the left of the visible area for the slide effect.
        let startFrame = targetFrame.offsetBy(dx: -Self.panelWidth, dy: 0)

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        // `orderFrontRegardless` brings the panel up without activating the
        // app. We deliberately do NOT call `makeKey()` here: making a
        // non-activating panel the key window leaves stale key-window state
        // after `orderOut` (panel hidden but still the app's key window),
        // which prevents subsequent global hotkey deliveries until the user
        // focuses another app to clear that state. Escape is captured via a
        // global key monitor instead, so the panel stays purely visual.
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }

        installCloseMonitors()
        isVisible = true
    }

    func hide() {
        guard isVisible else { return }
        // Set state first so a fast re-toggle during the slide-out animation
        // sees the up-to-date value and triggers a fresh show().
        isVisible = false

        let current = panel.frame
        let offscreen = current.offsetBy(dx: -Self.panelWidth, dy: 0)

        removeCloseMonitors()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(offscreen, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Skip the orderOut if the user re-opened during the animation:
                // doing it now would yank the freshly-shown panel back off.
                guard !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Auto-close monitors

    private func installCloseMonitors() {
        removeCloseMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Any click outside our process closes the panel.
            Task { @MainActor in self?.hide() }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            // If the click landed in another window of our own app (e.g. a future
            // preferences window), still close the panel. Clicks inside the panel
            // itself are ignored.
            if event.window !== self.panel {
                Task { @MainActor in self.hide() }
            }
            return event
        }

        // Escape via global key monitor: the panel is non-key, so we cannot
        // rely on `panel.keyDown` to receive the event. Global monitors observe
        // events headed to other apps without consuming them — pressing Escape
        // in another app will both perform its native action *and* dismiss
        // our panel, which is the expected behaviour for a heads-up overlay.
        // 53 = kVK_Escape.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeCloseMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }
}
