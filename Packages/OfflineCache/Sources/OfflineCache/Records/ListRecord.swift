import Core
import Foundation
import GoogleAuth
import GRDB

/// GRDB record for the `lists` table.
///
/// Kept package-private (`internal`) so the persistence shape never
/// leaks to the rest of the app — callers see ``TaskList`` from `Core`.
struct ListRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "lists"

    var accountID: String
    var listID: String
    var title: String
    var updatedAt: Date

    init(accountID: AccountID, list: TaskList) {
        self.accountID = accountID.rawValue
        listID = list.id
        title = list.title
        updatedAt = list.updatedAt
    }

    var domain: TaskList {
        TaskList(id: listID, title: title, updatedAt: updatedAt)
    }
}
