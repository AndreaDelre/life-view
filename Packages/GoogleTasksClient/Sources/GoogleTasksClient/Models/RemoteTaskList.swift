import Core
import Foundation

/// Wire-format DTO for a Google Tasks list. Internal to the package — only
/// the domain ``Core/TaskList`` crosses the package boundary.
struct RemoteTaskList: Decodable {
    let id: String
    let title: String
    let updated: Date

    func toDomain() -> TaskList {
        TaskList(id: id, title: title, updatedAt: updated)
    }
}

/// Paginated `tasklists.list` response.
struct RemoteTaskListPage: Decodable {
    let items: [RemoteTaskList]?
    let nextPageToken: String?
}
