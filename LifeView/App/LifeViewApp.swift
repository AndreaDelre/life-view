import AppKit
import SwiftUI

/// SwiftUI lifecycle entry point.
///
/// The app deliberately ships **no** ``Scene``: the only UI surface is the
/// floating ``LifeViewPanel`` owned by the ``AppDelegate``. Declaring an empty
/// `Settings` scene keeps SwiftUI happy without producing a window at launch.
@main
struct LifeViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            // Empty settings scene — replaced by the real preferences UI in P7.
            EmptyView()
        }
    }
}
