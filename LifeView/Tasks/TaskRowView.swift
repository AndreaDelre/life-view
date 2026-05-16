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
    /// Nesting level. `0` for top-level tasks, `1+` for sub-tasks. Drives
    /// the leading indent + the vertical guide line on the left edge.
    var depth: Int = 0
    /// Number of direct sub-tasks for this row. `0` when the row has
    /// none (or when it is itself a sub-task). Used to render the
    /// Todoist-style `X/Y` counter on parent rows.
    var totalSubtasks: Int = 0
    /// Number of those sub-tasks already completed. Pairs with
    /// ``totalSubtasks`` for the `X/Y` counter.
    var completedSubtasks: Int = 0
    @Binding var isEditing: Bool
    /// Whether the row is the currently-selected one. Single-mode
    /// drives this from a custom selection state (we don't use
    /// `List(selection:)` because macOS hard-codes the selection bar
    /// to the system accent blue and there's no public API to retint
    /// it). Aggregated-mode leaves the default `false` — there is no
    /// row-level cursor there.
    var isSelected: Bool = false
    let onToggleCompletion: (Bool) -> Void
    let onEditTitle: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering: Bool = false

    /// Per-level indent applied to sub-tasks. Sized so the child's
    /// checkbox sits roughly under the parent's title baseline — same
    /// visual rhythm as Todoist.
    private static let depthIndent: CGFloat = 22

    private var indent: CGFloat { CGFloat(depth) * Self.depthIndent }

    var body: some View {
        // Center alignment (rather than firstTextBaseline) so the
        // bigger checkbox glyph dictates the row's vertical midline
        // and the trailing due-date / pending pieces line up cleanly
        // alongside the title text.
        HStack(alignment: .center, spacing: Spacing.sm) {
            checkbox

            titleRow
                // Strike-through + color shift on completion are
                // animated together so the row "settles" into its
                // completed state instead of snapping. Reduce-motion
                // drops the timing to a plain cross-fade through
                // `Motion.reduced` (same easing, no spring/bounce).
                .animation(reduceMotion ? Motion.reduced : Motion.emphasised, value: task.status)

            Spacer(minLength: Spacing.sm)

            if let due = task.due {
                Text(formatDue(due))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }

            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Synchronisation en cours")
            }
        }
        .padding(.leading, indent)
        .background(alignment: .leading) { subtaskGuide }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(
            // Single highlight layer covering selection / hover / idle.
            // Drawn with a rounded shape so the affordance reads as a
            // modern card rather than the flat full-width bar macOS
            // `List(selection:)` would normally draw. We toggle opacity
            // (not view presence) so SwiftUI can cross-fade between
            // states instead of snapping.
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(rowTint)
                .opacity(rowTint == .clear ? 0 : 1)
        )
        .animation(reduceMotion ? Motion.reduced : Motion.quick, value: isHovering)
        .animation(reduceMotion ? Motion.reduced : Motion.quick, value: isSelected)
        .animation(reduceMotion ? Motion.reduced : Motion.quick, value: isEditing)
        .onHover { hovering in
            isHovering = hovering
        }
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

    /// Pre-resolved row tint. Pending wins (busy reads as "don't
    /// touch me"), then editing pins the selection tint (so the row
    /// doesn't fall back to the empty background while the inline
    /// editor is active), then selected beats hover beats idle.
    private var rowTint: Color {
        if isPending { return .clear }
        if isEditing { return Palette.surfaceRowSelected }
        if isSelected { return Palette.surfaceRowSelected }
        if isHovering { return Palette.surfaceHover }
        return .clear
    }

    private var checkbox: some View {
        Button {
            onToggleCompletion(task.status != .completed)
        } label: {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Palette.accent : Palette.textSecondary)
                // Sub-task checkboxes shrink one step to reinforce the
                // hierarchy at a glance — same trick Todoist uses.
                // Top-level checkboxes use `.title3` (~20pt) so the
                // glyph reads as a chunky, deliberately-targetable
                // affordance — the previous body-size circle felt
                // hairline and crowded the title text.
                .font(depth > 0 ? Typography.body : .title3)
                .symbolRenderingMode(.hierarchical)
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

    /// Title + (optional) sub-task counter on the same baseline. The
    /// counter is rendered as `X/Y` on parent rows that own at least
    /// one sub-task, in a muted caption style that doesn't compete
    /// with the title text.
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            titleView
                .strikethrough(task.status == .completed, color: Palette.textSecondary)
                .foregroundStyle(task.status == .completed ? Palette.textSecondary : Palette.textPrimary)

            if totalSubtasks > 0 {
                Text("\(completedSubtasks)/\(totalSubtasks)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
    }

    /// Thin vertical hairline drawn in the leading gutter of a sub-task
    /// row. Visually anchors the child to its parent without requiring
    /// an across-rows overlay (which `List` doesn't let us draw).
    @ViewBuilder
    private var subtaskGuide: some View {
        if depth > 0 {
            // The 1pt-wide line sits at the centre of each indent step
            // so successive nesting levels remain visually distinct.
            // Subtract a tiny vertical inset so the line doesn't kiss
            // the row separators above/below.
            Rectangle()
                .fill(Palette.separator)
                .frame(width: 1)
                .padding(.leading, indent - Self.depthIndent / 2)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Accessibility

    /// Sentence read by VoiceOver when it lands on the row. Format:
    /// `"<titre>"` (or `"Sous-tâche : <titre>"` when the row is nested)
    /// — keeping the title compact lets VoiceOver announce
    /// `"<titre>, terminée, échéance demain, bouton"` by composing the
    /// label with `accessibilityValue` and the traits added above.
    private var accessibilityRowLabel: String {
        let base = task.title.isEmpty ? "Tâche sans titre" : task.title
        return depth > 0 ? "Sous-tâche : \(base)" : base
    }

    /// Composite value: status (à faire / terminée) + due date if any
    /// + sub-task progress when this row is a parent. Joined with ", "
    /// so VoiceOver inserts a natural pause between the pieces of
    /// information.
    private var accessibilityRowValue: String {
        var parts: [String] = [task.status == .completed ? "terminée" : "à faire"]
        if let due = task.due {
            parts.append("échéance \(formatDue(due))")
        }
        if totalSubtasks > 0 {
            parts.append("\(completedSubtasks) sur \(totalSubtasks) sous-tâches terminées")
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

#Preview("Hierarchy") {
    @Previewable @State var isEditing = false
    VStack(spacing: 0) {
        TaskRowView(
            task: TaskItem(
                id: "p1",
                title: "Préparer le déménagement",
                status: .needsAction,
                position: "00000000000000000001"
            ),
            isPending: false,
            depth: 0,
            totalSubtasks: 3,
            completedSubtasks: 1,
            isEditing: $isEditing,
            onToggleCompletion: { _ in },
            onEditTitle: { _ in },
            onDelete: {}
        )
        TaskRowView(
            task: TaskItem(
                id: "c1",
                title: "Acheter des cartons",
                status: .completed,
                position: "00000000000000000002",
                parent: "p1"
            ),
            isPending: false,
            depth: 1,
            isEditing: $isEditing,
            onToggleCompletion: { _ in },
            onEditTitle: { _ in },
            onDelete: {}
        )
        TaskRowView(
            task: TaskItem(
                id: "c2",
                title: "Réserver l'utilitaire",
                status: .needsAction,
                position: "00000000000000000003",
                parent: "p1"
            ),
            isPending: false,
            depth: 1,
            isEditing: $isEditing,
            onToggleCompletion: { _ in },
            onEditTitle: { _ in },
            onDelete: {}
        )
        TaskRowView(
            task: TaskItem(
                id: "c3",
                title: "Prévenir le syndic",
                status: .needsAction,
                position: "00000000000000000004",
                parent: "p1"
            ),
            isPending: false,
            depth: 1,
            isEditing: $isEditing,
            onToggleCompletion: { _ in },
            onEditTitle: { _ in },
            onDelete: {}
        )
    }
    .padding()
}
