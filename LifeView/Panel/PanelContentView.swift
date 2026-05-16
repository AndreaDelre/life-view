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
///
/// P6.4 adds the keyboard help overlay layered on top of the whole
/// content via a ZStack. The visibility flag is owned here so the `?`
/// binding (also bound here) and the Esc cascade can both flip it.
struct PanelContentView: View {
    let accountsViewModel: AccountsViewModel
    let tasksViewModel: TasksViewModel
    let environment: PanelEnvironment

    @State private var showsHelp: Bool = false

    var body: some View {
        ZStack {
            mainContent
            if showsHelp {
                HelpOverlayView(onDismiss: { showsHelp = false })
                    .zIndex(1)
            }
        }
        .background(
            // Hidden `?` shortcut. A real bound button keeps the
            // shortcut active regardless of which sub-view holds
            // focus — `keyboardShortcut` only fires on visible,
            // enabled controls inside the responder chain, and a
            // zero-sized button is the smallest stable host.
            Button("Aide raccourcis", action: toggleHelp)
                .keyboardShortcut(Shortcut.toggleHelp)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        // Esc cascade: TextField `onExitCommand` handles "cancel edit"
        // first (it consumes the key before this fires); if no field
        // was focused we land here. Closing the help bubble takes
        // priority over closing the panel — the panel close itself
        // is delegated to `LifeViewPanel.keyDown` which only runs
        // when SwiftUI did NOT consume the event.
        .onExitCommand {
            if showsHelp { showsHelp = false }
        }
        .animation(.easeInOut(duration: 0.16), value: showsHelp)
    }

    private var mainContent: some View {
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
            helpButton
        }
    }

    private var helpButton: some View {
        Button(action: toggleHelp) {
            Image(systemName: "questionmark.circle")
                .symbolRenderingMode(.hierarchical)
                .imageScale(.medium)
        }
        .buttonStyle(.borderless)
        .help("Afficher l’aide raccourcis (?)")
        .accessibilityLabel("Afficher l’aide raccourcis")
    }

    private func toggleHelp() {
        showsHelp.toggle()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !accountsViewModel.isLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if accountsViewModel.accounts.isEmpty {
            SignedOutView(isWorking: accountsViewModel.isWorking, onSignIn: performAddAccount)
        } else {
            TasksView(
                viewModel: tasksViewModel,
                accountsViewModel: accountsViewModel
            )
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
