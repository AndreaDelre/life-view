import SwiftUI

@main
struct LifeViewApp: App {
    var body: some Scene {
        WindowGroup("LifeView") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("LifeView — coquille en cours")
                .font(.title2)
                .foregroundStyle(.primary)
            Text("Phase P0 : squelette technique.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 200)
    }
}

#Preview {
    RootView()
}
