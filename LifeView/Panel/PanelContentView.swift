import SwiftUI

/// SwiftUI placeholder rendered inside the panel for P1.
///
/// Real content (accounts, task lists) arrives in P2+. For now this view shows
/// the brand name and an explicit empty state so the phase milestone is visible
/// during manual QA.
struct PanelContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("LifeView")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.top, 8)

            Divider()

            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Aucune tâche pour le moment")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Phase P1 — coquille d’application.\nLa connexion Google arrive en P2.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Translucent material — feels native on top of arbitrary backgrounds.
            VisualEffectBackground()
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

#Preview {
    PanelContentView()
        .frame(width: 380, height: 600)
}
