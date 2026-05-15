import GoogleAuth
import SwiftUI

/// Root SwiftUI view hosted inside the panel.
///
/// P3 layout: a slim header (title + account chip when signed in) above
/// either the sign-in screen or the tasks view, depending on auth state.
struct PanelContentView: View {
    let authViewModel: AuthViewModel
    let tasksViewModel: TasksViewModel
    let environment: PanelEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .onChange(of: isSignedIn) { _, signedIn in
            // Reset the tasks view-model whenever the user signs out so
            // the next sign-in starts from a clean cache and the .idle
            // state — without this, a quick sign-out / sign-in (or a
            // mid-session account swap) would surface stale data.
            if !signedIn {
                Task { await tasksViewModel.reset() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("LifeView")
                .font(.title2.weight(.semibold))
            Spacer()
            if case .signedIn(let account) = authViewModel.state {
                SignedInHeaderView(
                    account: account,
                    isWorking: authViewModel.isWorking,
                    onSignOut: performSignOut
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch authViewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            SignedOutView(isWorking: authViewModel.isWorking, onSignIn: performSignIn)
        case .signedIn:
            TasksView(viewModel: tasksViewModel)
        case .error(let message):
            ErrorBanner(message: message, retry: { Task { await authViewModel.start() } })
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = authViewModel.state { return true }
        return false
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
