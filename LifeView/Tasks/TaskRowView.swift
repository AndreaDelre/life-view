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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            checkbox

            VStack(alignment: .leading, spacing: 2) {
                titleView
                    .strikethrough(task.status == .completed, color: .secondary)
                    .foregroundStyle(task.status == .completed ? Color.secondary : Color.primary)

                if let due = task.due {
                    Text(formatDue(due))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isPending {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
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
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var checkbox: some View {
        Button {
            onToggleCompletion(task.status != .completed)
        } label: {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Color.accentColor : Color.secondary)
                .font(.body)
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .accessibilityLabel(task.status == .completed ? "Marquer comme à faire" : "Marquer terminée")
    }

    private var titleView: some View {
        InlineEditableText(
            text: task.title.isEmpty ? "(Sans titre)" : task.title,
            isEditing: $isEditing,
            placeholder: "Titre",
            onCommit: onEditTitle
        )
        .font(.body)
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
