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
///
/// Visual treatment: a soft "card" pill that lifts the input off the
/// translucent panel material — same affordance shape used by modern
/// task apps (TickTick / Todoist quick-add). The card grows a faint
/// accent ring while focused so the user has unambiguous feedback that
/// the keystrokes will land in this field.
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
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Créer la tâche")
            .accessibilityHint("Ajoute la tâche à la liste sélectionnée")

            TextField("Ajouter une tâche", text: $title)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .focused($fieldFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Titre de la nouvelle tâche")
                .accessibilityHint("Appuie sur Entrée pour valider")

            QuickDatePicker(date: $due)
        }
        .padding(.vertical, Spacing.sm + 2)
        .padding(.horizontal, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: fieldFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.12), value: fieldFocused)
        .animation(.easeInOut(duration: 0.12), value: canSubmit)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var strokeColor: Color {
        fieldFocused ? Palette.accent.opacity(0.55) : Palette.surfaceCardStroke
    }
}
