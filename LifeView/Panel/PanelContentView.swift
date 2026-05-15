import GoogleAuth
import SwiftUI

/// Root SwiftUI view hosted inside the panel.
///
/// In P2 the only content is the auth section. P3+ will graft on the lists
/// of tasks once the user is signed in.
struct PanelContentView: View {
    let authViewModel: AuthViewModel
    let environment: PanelEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            VisualEffectBackground()
        }
        .task {
            await authViewModel.start()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("LifeView")
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch authViewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            SignedOutView(isWorking: authViewModel.isWorking, onSignIn: performSignIn)
        case .signedIn(let account):
            SignedInView(
                account: account,
                isWorking: authViewModel.isWorking,
                onSignOut: performSignOut
            )
            Spacer(minLength: 0)
        case .error(let message):
            ErrorBanner(message: message, retry: { Task { await authViewModel.start() } })
        }
    }

    // MARK: - Actions

    private func performSignIn() {
        guard let window = environment.presentingWindow() else { return }
        Task { @MainActor in
            environment.acquireInteractionLock()
            defer { environment.releaseInteractionLock() }
            await authViewModel.signIn(presenting: window)
        }
    }

    private func performSignOut() {
        Task { @MainActor in
            await authViewModel.signOut()
        }
    }
}

// MARK: - Error banner

private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: retry)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Background

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
