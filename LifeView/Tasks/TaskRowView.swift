import Core
import SwiftUI

/// One line of the tasks `List`. Title + optional relative due date,
/// status surfaced via the leading icon and a strike-through on the
/// completed title.
struct TaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Color.accentColor : Color.secondary)
                .font(.body)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "(Sans titre)" : task.title)
                    .font(.body)
                    .strikethrough(task.status == .completed, color: .secondary)
                    .foregroundStyle(task.status == .completed ? Color.secondary : Color.primary)

                if let due = task.due {
                    Text(formatDue(due))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func formatDue(_ date: Date) -> String {
        // Google stores `due` as midnight UTC. We display it relative to
        // the user's calendar — "Aujourd'hui", "Demain", "il y a 3 jours"…
        date.formatted(.relative(presentation: .named))
    }
}

#Preview("Needs action") {
    TaskRowView(
        task: TaskItem(
            id: "1",
            title: "Acheter du pain",
            status: .needsAction,
            due: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            position: "00000000000000000001"
        )
    )
    .padding()
}

#Preview("Completed") {
    TaskRowView(
        task: TaskItem(
            id: "2",
            title: "Lancer la machine",
            status: .completed,
            position: "00000000000000000002"
        )
    )
    .padding()
}
