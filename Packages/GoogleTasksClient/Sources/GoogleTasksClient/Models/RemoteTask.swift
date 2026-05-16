import Core
import Foundation

/// Wire-format DTO for a Google task. Internal — see ``RemoteTaskList``.
struct RemoteTask: Decodable {
    let id: String
    let title: String?
    let notes: String?
    let status: String?
    let due: Date?
    let position: String?
    let parent: String?

    /// Maps to the domain ``Core/TaskItem``. Returns `nil` if a required
    /// field is missing — Google Tasks occasionally returns tombstone
    /// entries (e.g. when `showDeleted=true`) that we'd rather drop than
    /// display as "(untitled)".
    func toDomain() -> TaskItem? {
        guard let position else { return nil }
        let mappedStatus: TaskStatus
        switch status {
        case "completed": mappedStatus = .completed
        case "needsAction", nil: mappedStatus = .needsAction
        default: mappedStatus = .needsAction
        }
        return TaskItem(
            id: id,
            title: title ?? "",
            notes: notes,
            status: mappedStatus,
            due: due,
            position: position,
            parent: parent
        )
    }
}

/// Paginated `tasks.list` response.
struct RemoteTaskPage: Decodable {
    let items: [RemoteTask]?
    let nextPageToken: String?
}
