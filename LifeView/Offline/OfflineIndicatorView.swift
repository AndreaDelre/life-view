import DesignSystem
import SwiftUI

/// Header chip that surfaces the current connectivity / sync state.
///
/// Three visual states, designed to be discreet:
///
/// - **Online + idle**: chip is hidden entirely (no chrome wasted on
///   the happy path).
/// - **Online + draining queue**: small spinner with a "Sync…" label,
///   so the user understands recent offline edits are being replayed.
/// - **Offline**: dim "Hors-ligne" badge with a `wifi.slash` icon —
///   confirms what is otherwise invisible (the writes still land in
///   the cache; they'll replay on reconnect).
///
/// Reads from ``OfflineSyncCoordinator`` via `@Bindable` so SwiftUI
/// re-renders on the observable changes without us wiring a publisher.
struct OfflineIndicatorView: View {
    @Bindable var coordinator: OfflineSyncCoordinator

    var body: some View {
        Group {
            if !coordinator.isOnline {
                offlineBadge
            } else if coordinator.isSyncing {
                syncingBadge
            } else {
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: coordinator.isOnline)
        .animation(.easeInOut(duration: 0.15), value: coordinator.isSyncing)
    }

    private var offlineBadge: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "wifi.slash")
                .imageScale(.small)
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            Text("Hors-ligne")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(Palette.surfaceWarning, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hors-ligne. Les modifications seront synchronisées à la reconnexion.")
        .help("Tu es hors-ligne. Tes modifications restent locales et seront envoyées dès le retour du réseau.")
    }

    private var syncingBadge: some View {
        HStack(spacing: Spacing.xs) {
            ProgressView()
                .controlSize(.mini)
                .accessibilityHidden(true)
            Text("Sync…")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Synchronisation des modifications en cours")
    }
}
