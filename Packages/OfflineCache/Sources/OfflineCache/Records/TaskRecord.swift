import Core
import Foundation
import GoogleAuth
import GRDB

/// GRDB record for the `tasks` table. Package-private.
struct TaskRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tasks"

    var accountID: String
    var listID: String
    var taskID: String
    var title: String
    var notes: String?
    var status: String
    var due: Date?
    var position: String
    var parent: String?

    init(accountID: AccountID, listID: String, task: TaskItem) {
        self.accountID = accountID.rawValue
        self.listID = listID
        taskID = task.id
        title = task.title
        notes = task.notes
        status = task.status.rawValue
        due = task.due
        position = task.position
        parent = task.parent
    }

    var domain: TaskItem? {
        guard let status = TaskStatus(rawValue: status) else { return nil }
        return TaskItem(
            id: taskID,
            title: title,
            notes: notes,
            status: status,
            due: due,
            position: position,
            parent: parent
        )
    }
}
