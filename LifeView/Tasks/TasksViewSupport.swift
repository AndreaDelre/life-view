import DesignSystem
import SwiftUI

/// Visual primitives shared by `TasksView` and the aggregated mode
/// renderers. Pulled out of `TasksView.swift` to keep that file under
/// SwiftLint's `file_length` budget. None of these views own state or
/// know anything about Google Tasks — they are pure UI building blocks
/// scoped `internal` so the rest of the app target can compose them.
struct CompletedToggle: View {
    let showsCompleted: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: showsCompleted ? "eye.fill" : "eye.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .help(showsCompleted ? "Masquer les tâches terminées" : "Afficher les tâches terminées")
        .accessibilityLabel(showsCompleted ? "Masquer les tâches terminées" : "Afficher les tâches terminées")
        .accessibilityAddTraits(showsCompleted ? [.isButton, .isSelected] : .isButton)
    }
}

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .opacity(isRefreshing ? 0 : 1)
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: IconSize.sm, height: IconSize.sm)
        }
        .buttonStyle(.borderless)
        .disabled(isRefreshing)
        .help("Rafraîchir")
        .accessibilityLabel(isRefreshing ? "Rafraîchissement en cours" : "Rafraîchir")
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.callout)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: retry)
                .controlSize(.small)
                .accessibilityHint("Recharge les données")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Pin a `keyboardShortcut`-host button to zero size + zero opacity
/// without losing its responder-chain hookup. SwiftUI ignores the
/// shortcut if the button is `.hidden()` or removed from the view
/// tree, so we keep it visually neutral instead.
extension View {
    func hiddenShortcutHost() -> some View {
        self
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
