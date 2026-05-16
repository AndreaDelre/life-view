import DesignSystem
import GoogleAuth
import SwiftUI

/// Top-of-panel strip: one avatar per connected account, a toggle for the
/// aggregated "all accounts" view, and a `+` button to start the OAuth flow
/// for an additional account.
///
/// Owned by the panel content view rather than the tasks view so the strip
/// stays visible when there are zero accounts (the `+` button is the only
/// affordance to add the first one — the dedicated sign-in screen still
/// renders below in that state).
struct AccountsBarView: View {
    @Bindable var viewModel: AccountsViewModel
    let onAddAccount: () -> Void

    @State private var renameTarget: Account?
    @State private var renameDraft: String = ""

    var body: some View {
        HStack(spacing: Spacing.sm) {
            allAccountsToggle
            avatarStrip
            Spacer(minLength: 0)
            addButton
        }
        .alert(
            "Renommer le compte",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            ),
            presenting: renameTarget
        ) { account in
            TextField("Nom affiché", text: $renameDraft)
            Button("Annuler", role: .cancel) {
                renameTarget = nil
            }
            Button("Enregistrer") {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                let nextName = trimmed.isEmpty ? nil : trimmed
                Task { await viewModel.renameAccount(account.id, displayName: nextName) }
                renameTarget = nil
            }
        } message: { account in
            Text(account.profile.email)
        }
    }

    // MARK: - Subviews

    private var avatarStrip: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(viewModel.accounts) { account in
                AccountAvatarButton(
                    account: account,
                    isSelected: isAvatarHighlighted(account.id),
                    isDimmed: viewModel.mode == .all && !isAvatarHighlighted(account.id),
                    onSelect: { selectSingle(account) },
                    onRename: { startRename(account) },
                    onDisconnect: { Task { await viewModel.removeAccount(account.id) } }
                )
                .disabled(viewModel.isWorking)
            }
        }
    }

    @ViewBuilder
    private var allAccountsToggle: some View {
        if viewModel.accounts.count >= 2 {
            Button {
                viewModel.setMode(viewModel.mode == .all ? .single : .all)
            } label: {
                Image(systemName: viewModel.mode == .all ? "person.2.fill" : "person.2")
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: IconSize.md, height: IconSize.md)
            }
            .buttonStyle(.borderless)
            .help(viewModel.mode == .all ? "Vue agrégée — désactiver" : "Voir tous les comptes")
            .accessibilityLabel(viewModel.mode == .all ? "Désactiver la vue tous comptes" : "Vue tous comptes")
        }
    }

    private var addButton: some View {
        Button(action: onAddAccount) {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
        }
        .buttonStyle(.borderless)
        .disabled(viewModel.isWorking)
        .help("Ajouter un compte Google")
        .accessibilityLabel("Ajouter un compte Google")
    }

    // MARK: - Helpers

    private func isAvatarHighlighted(_ id: AccountID) -> Bool {
        switch viewModel.mode {
        case .single:
            return viewModel.selectedID == id
        case .all:
            return true
        }
    }

    private func selectSingle(_ account: Account) {
        if viewModel.mode == .all { viewModel.setMode(.single) }
        Task { await viewModel.select(account.id) }
    }

    private func startRename(_ account: Account) {
        renameDraft = account.profile.displayName ?? ""
        renameTarget = account
    }
}

/// Single avatar with selection ring, a select-on-click affordance, and a
/// context menu for the per-account actions.
private struct AccountAvatarButton: View {
    let account: Account
    let isSelected: Bool
    let isDimmed: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            AccountAvatarView(url: account.profile.avatarURL)
                .frame(width: IconSize.lg, height: IconSize.lg)
                .opacity(isDimmed ? 0.55 : 1)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .help(displayLabel)
        .accessibilityLabel(displayLabel)
        .contextMenu {
            Section {
                Text(account.profile.email)
                if let name = account.profile.displayName, !name.isEmpty {
                    Text(name)
                }
            }
            Button("Renommer…", action: onRename)
            Button(role: .destructive, action: onDisconnect) {
                Label("Déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private var displayLabel: String {
        if let name = account.profile.displayName, !name.isEmpty {
            return "\(name) — \(account.profile.email)"
        }
        return account.profile.email
    }
}
