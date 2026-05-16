import Core
import DesignSystem
import SwiftUI

/// One line of the tasks `List`. Owns no business logic — every
/// mutation is dispatched through the four callbacks supplied by the
/// parent so the row stays trivially testable and reusable between
/// single and aggregated modes.
///
/// `isEditing` is a binding (rather than internal `@State`) so the
/// parent can drive entry into edit mode from outside the row — from
/// the context menu, from the row's `Return`-key handler, etc.
struct TaskRowView: View {
    let task: TaskItem
    let isPending: Bool
    @Binding var isEditing: Bool
    let onToggleCompletion: (Bool) -> Void
    let onEditTitle: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            checkbox

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                titleView
                    // Strike-through + color shift on completion are
                    // animated together so the row "settles" into its
                    // completed state instead of snapping. Reduce-motion
                    // drops the timing to a plain cross-fade through
                    // `Motion.reduced` (same easing, no spring/bounce).
                    .strikethrough(task.status == .completed, color: Palette.textSecondary)
                    .foregroundStyle(task.status == .completed ? Palette.textSecondary : Palette.textPrimary)
                    .animation(reduceMotion ? Motion.reduced : Motion.emphasised, value: task.status)

                if let due = task.due {
                    Text(formatDue(due))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Synchronisation en cours")
            }
        }
        .padding(.vertical, Spacing.xs)
        .opacity(isPending ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                isEditing = true
            } label: {
                Label("Renommer", systemImage: "pencil")
            }
            .disabled(isPending)

            Button(role: .destructive, action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(isPending)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onToggleCompletion(task.status != .completed)
            } label: {
                Label(
                    task.status == .completed ? "À faire" : "Terminer",
                    systemImage: task.status == .completed ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(Palette.success)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
        }
        // Combine the row into a single VoiceOver element so the user
        // hears "Acheter du pain, à faire, échéance demain" in one
        // utterance rather than five separate stops. We override the
        // label/value/hint/traits manually because `.combine` would
        // otherwise concatenate the checkbox button label + title +
        // due caption into an awkward stream.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityValue(accessibilityRowValue)
        .accessibilityHint(isPending ? "Synchronisation en cours" : "Utilise le menu d’actions pour modifier")
        .accessibilityAddTraits(task.status == .completed ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: task.status == .completed ? "Marquer à faire" : "Marquer terminée") {
            guard !isPending else { return }
            onToggleCompletion(task.status != .completed)
        }
        .accessibilityAction(named: "Renommer") {
            guard !isPending else { return }
            isEditing = true
        }
        .accessibilityAction(named: "Supprimer") {
            guard !isPending else { return }
            onDelete()
        }
    }

    private var checkbox: some View {
        Button {
            onToggleCompletion(task.status != .completed)
        } label: {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Palette.accent : Palette.textSecondary)
                .font(Typography.body)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? Motion.reduced : Motion.quick, value: task.status)
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        // Hidden from VoiceOver because the parent row aggregates the
        // toggle into a custom action (and the row itself is a button).
        // Leaving the checkbox visible would produce a redundant
        // "Marquer terminée, bouton" stop inside the row element.
        .accessibilityHidden(true)
    }

    // MARK: - Accessibility

    /// Sentence read by VoiceOver when it lands on the row. Format:
    /// `"<titre>"` — keeping the title alone as the label lets VoiceOver
    /// announce `"<titre>, terminée, échéance demain, bouton"` by
    /// composing the label with `accessibilityValue` and the traits
    /// added above.
    private var accessibilityRowLabel: String {
        task.title.isEmpty ? "Tâche sans titre" : task.title
    }

    /// Composite value: status (à faire / terminée) + due date if any.
    /// Joined with ", " so VoiceOver inserts a natural pause between
    /// the two pieces of information.
    private var accessibilityRowValue: String {
        var parts: [String] = [task.status == .completed ? "terminée" : "à faire"]
        if let due = task.due {
            parts.append("échéance \(formatDue(due))")
        }
        return parts.joined(separator: ", ")
    }

    private var titleView: some View {
        InlineEditableText(
            text: task.title.isEmpty ? "(Sans titre)" : task.title,
            isEditing: $isEditing,
            placeholder: "Titre",
            onCommit: onEditTitle
        )
        .font(Typography.body)
        .onTapGesture(count: 2) {
            guard !isPending else { return }
            isEditing = true
        }
    }

    private func formatDue(_ date: Date) -> String {
        // Google stores `due` as midnight UTC. We display it relative to
        // the user's calendar — "Aujourd'hui", "Demain", "il y a 3 jours"…
        date.formatted(.relative(presentation: .named))
    }
}

#Preview("Needs action") {
    @Previewable @State var isEditing = false
    TaskRowView(
        task: TaskItem(
            id: "1",
            title: "Acheter du pain",
            status: .needsAction,
            due: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            position: "00000000000000000001"
        ),
        isPending: false,
        isEditing: $isEditing,
        onToggleCompletion: { _ in },
        onEditTitle: { _ in },
        onDelete: {}
    )
    .padding()
}

#Preview("Completed") {
    @Previewable @State var isEditing = false
    TaskRowView(
        task: TaskItem(
            id: "2",
            title: "Lancer la machine",
            status: .completed,
            position: "00000000000000000002"
        ),
        isPending: false,
        isEditing: $isEditing,
        onToggleCompletion: { _ in },
        onEditTitle: { _ in },
        onDelete: {}
    )
    .padding()
}

#Preview("Pending") {
    @Previewable @State var isEditing = false
    TaskRowView(
        task: TaskItem(
            id: "3",
            title: "Création en cours…",
            status: .needsAction,
            position: ""
        ),
        isPending: true,
        isEditing: $isEditing,
        onToggleCompletion: { _ in },
        onEditTitle: { _ in },
        onDelete: {}
    )
    .padding()
}
