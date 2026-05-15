import AppKit

/// Bag of `@MainActor` callbacks the SwiftUI content view needs to talk back
/// to `PanelController` without holding a direct reference.
///
/// * `presentingWindow` — the panel's own `NSWindow`, used to anchor
///   `ASWebAuthenticationSession` during the Google sign-in flow.
/// * `acquireInteractionLock` / `releaseInteractionLock` — bracket calls
///   around any system-modal operation so the global-click auto-close
///   doesn't fire during it.
@MainActor
struct PanelEnvironment {
    let presentingWindow: @MainActor () -> NSWindow?
    let acquireInteractionLock: @MainActor () -> Void
    let releaseInteractionLock: @MainActor () -> Void
}
