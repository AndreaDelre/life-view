import DesignSystem
import GoogleAuth
import SwiftUI

/// Root SwiftUI view hosted inside the panel.
///
/// P4 layout: a slim header (title), the accounts bar (avatars + add
/// button + aggregate toggle), and below either the sign-in screen
/// (when zero accounts are connected) or the tasks view (single or
/// aggregated depending on the mode). The accounts bar stays visible
/// in both states so the `+` affordance is always reachable.
struct PanelContentView: View {
    let accountsViewModel: AccountsViewModel
    let tasksViewModel: TasksViewModel
    let environment: PanelEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            AccountsBarView(viewModel: accountsViewModel, onAddAccount: performAddAccount)
            if let error = accountsViewModel.errorMessage {
                inlineError(error)
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            VisualEffectBackground()
        }
        .task {
            await accountsViewModel.start()
            await tasksViewModel.setSelection(derivedSelection)
        }
        .onChange(of: derivedSelection) { _, next in
            Task { await tasksViewModel.setSelection(next) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("LifeView")
                .font(Typography.titleLarge)
            Spacer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !accountsViewModel.isLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if accountsViewModel.accounts.isEmpty {
            SignedOutView(isWorking: accountsViewModel.isWorking, onSignIn: performAddAccount)
        } else {
            TasksView(viewModel: tasksViewModel)
        }
    }

    @ViewBuilder
    private func inlineError(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            Button(action: accountsViewModel.clearError) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Effacer l’erreur")
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(Palette.surfaceWarning, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Derived state

    private var derivedSelection: TasksViewModel.Selection {
        guard !accountsViewModel.accounts.isEmpty else { return .none }
        switch accountsViewModel.mode {
        case .single:
            guard let id = accountsViewModel.selectedID else { return .none }
            return .single(id)
        case .all:
            return .all(accountsViewModel.accounts.map(\.id))
        }
    }

    // MARK: - Actions

    private func performAddAccount() {
        guard let window = environment.presentingWindow() else { return }
        Task { @MainActor in
            environment.acquireInteractionLock()
            defer { environment.releaseInteractionLock() }
            await accountsViewModel.addAccount(presenting: window)
        }
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
