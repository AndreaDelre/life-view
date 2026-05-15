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
    private(set) var isVisible = false

    /// Auto-close is suspended while this counter is > 0. We bump it during
    /// the OAuth `ASWebAuthenticationSession` because that flow steals focus
    /// system-wide and would otherwise trigger the global-click monitor and
    /// yank the panel away mid-consent.
    private var interactionLockCount = 0

    init(accountsViewModel: AccountsViewModel, tasksViewModel: TasksViewModel) {
        // Start with a placeholder frame; real geometry is computed at open time.
        let initialFrame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: 600)
        panel = LifeViewPanel(contentRect: initialFrame)

        // `panel` is captured weakly so the SwiftUI content view does not
        // retain the controller's panel; the controller owns the lifetime.
        let environment = PanelEnvironment(
            presentingWindow: { [weak panel] in panel },
            acquireInteractionLock: { [weak self] in self?.acquireInteractionLock() },
            releaseInteractionLock: { [weak self] in self?.releaseInteractionLock() }
        )
        panel.contentView = NSHostingView(
            rootView: PanelContentView(
                accountsViewModel: accountsViewModel,
                tasksViewModel: tasksViewModel,
                environment: environment
            )
        )
        panel.onEscape = { [weak self] in
            self?.hide()
        }
    }

    // MARK: - Interaction lock

    func acquireInteractionLock() {
        interactionLockCount += 1
        removeCloseMonitors()
    }

    func releaseInteractionLock() {
        interactionLockCount = max(0, interactionLockCount - 1)
        if interactionLockCount == 0, isVisible {
            installCloseMonitors()
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
        panel.orderFrontRegardless()
        // Panel must be the app's key window to receive Escape via `keyDown`.
        // The matching subtlety is on the close path: `orderOut(nil)` hides
        // the panel but does NOT resign key window status, which left stale
        // focus state and blocked subsequent hotkey deliveries. `hide()` now
        // calls `panel.close()` after the slide-out animation to fully
        // resign — `isReleasedWhenClosed = false` keeps the panel reusable.
        panel.makeFirstResponder(panel.contentView)
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }

        if interactionLockCount == 0 {
            installCloseMonitors()
        }
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
                // Skip the close if the user re-opened during the animation:
                // doing it now would yank the freshly-shown panel back off.
                guard !self.isVisible else { return }
                self.panel.close()
            }
        })
    }

    // MARK: - Auto-close monitors

    private func installCloseMonitors() {
        removeCloseMonitors()
        // Click anywhere outside our process closes the panel. We intentionally
        // do NOT install a *local* monitor: clicks on our own `NSStatusItem`
        // would fire it before the status item's action, causing the menu-bar
        // toggle to always re-open instead of closing. A future preferences
        // window will need its own logic at that time.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeCloseMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}
