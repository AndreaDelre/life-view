import DesignSystem
import SwiftUI

/// Header affordance for the notifications opt-in. A bell icon that
/// reflects the on/off state and opens a small popover with the
/// single toggle.
///
/// A popover is enough for P6.7 — the issue explicitly defers the
/// proper Preferences screen to P7. The popover anchors on the
/// button itself and adopts the panel's borderless aesthetic.
struct NotificationsToggleButton: View {
    @Bindable var coordinator: NotificationsCoordinator
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: coordinator.isEnabled ? "bell.fill" : "bell")
                .symbolRenderingMode(.hierarchical)
                .imageScale(.medium)
        }
        .buttonStyle(.borderless)
        .help(coordinator.isEnabled
            ? "Notifications d’échéance activées"
            : "Notifications d’échéance désactivées")
        .accessibilityLabel(coordinator.isEnabled
            ? "Notifications d’échéance activées"
            : "Notifications d’échéance désactivées")
        .accessibilityHint("Ouvre le réglage des notifications")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications d’échéance")
                        .font(Typography.titleSmall)
                    Text("Reçois une alerte macOS quand une tâche arrive à échéance.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            if coordinator.isEnabled, !coordinator.isAuthorized {
                Divider()
                Text("L’autorisation système n’est pas accordée. Ouvre Réglages système › Notifications pour autoriser LifeView.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .frame(width: 280)
    }

    /// Two-way binding routed through ``NotificationsCoordinator/setEnabled(_:)``
    /// so the persistence + permission flow runs on every change.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isEnabled },
            set: { coordinator.setEnabled($0) }
        )
    }
}
