import DesignSystem
import SwiftUI

/// Top-of-list capture row for the panel. Single-mode only — aggregated
/// mode does not have a target list, so the parent view hides this
/// component there.
///
/// Pressing `Return` (or clicking the leading `+`) commits the typed
/// title plus the selected due date and resets the row. The focus
/// binding is owned by the parent so the ⌘N shortcut and panel-open
/// auto-focus can flip it without re-creating the view.
struct NewTaskRow: View {
    @Binding var title: String
    @Binding var due: Date?
    @FocusState.Binding var fieldFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Button(action: onSubmit) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(canSubmit ? Palette.accent : Palette.textSecondary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Créer la tâche")

            TextField("Nouvelle tâche", text: $title)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Titre de la nouvelle tâche")

            QuickDatePicker(date: $due)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
