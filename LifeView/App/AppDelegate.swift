import AppKit
import Core

/// Application-level orchestrator.
///
/// Holds the singletons that have to outlive any SwiftUI view: the panel
/// controller, the menu-bar item, and the global hotkey. SwiftUI's `App`
/// lifecycle is too short-lived (and too view-flavoured) to own these.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var statusBarController: StatusBarController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_: Notification) {
        // Hide the dock icon. We rely on `LSUIElement = true` in Info.plist as
        // the primary mechanism (handled via INFOPLIST_KEY in project.yml), but
        // we also pin the activation policy here as a defence in depth.
        NSApp.setActivationPolicy(.accessory)

        let controller = PanelController()
        panelController = controller

        statusBarController = StatusBarController { [weak controller] in
            controller?.toggle()
        }

        registerHotKey(combo: HotKeyStore.load())
    }

    func applicationWillTerminate(_: Notification) {
        hotKey = nil
    }

    // MARK: - Hot key

    private func registerHotKey(combo: HotKeyCombo) {
        hotKey = GlobalHotKey(combo: combo) { [weak self] in
            self?.panelController?.toggle()
        }
        if hotKey == nil {
            NSLog("[LifeView] Hotkey registration failed for combo \(combo.displayString)")
        }
    }
}
