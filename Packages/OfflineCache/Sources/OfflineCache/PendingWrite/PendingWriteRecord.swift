import Foundation
import GoogleAuth
import GRDB

/// GRDB record for the `pending_writes` table.
///
/// The strongly-typed ``PendingWritePayload`` is stored as JSON in the
/// `payload` blob column plus a `kind` discriminator for fast filtering
/// without decoding the JSON. We deliberately keep both `kind` and the
/// JSON payload — the JSON is the source of truth, `kind` is the index.
struct PendingWriteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "pending_writes"

    var id: String
    var accountID: String
    var kind: String
    var payload: Data
    var createdAt: Date
    var attemptCount: Int

    init(write: PendingWrite, encoder: JSONEncoder) throws {
        id = write.id
        accountID = write.accountID.rawValue
        kind = Self.kind(of: write.payload)
        payload = try encoder.encode(write.payload)
        createdAt = write.createdAt
        attemptCount = write.attemptCount
    }

    init(
        id: String,
        accountID: String,
        kind: String,
        payload: Data,
        createdAt: Date,
        attemptCount: Int
    ) {
        self.id = id
        self.accountID = accountID
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }

    func toPendingWrite(decoder: JSONDecoder) throws -> PendingWrite {
        let decoded = try decoder.decode(PendingWritePayload.self, from: payload)
        return PendingWrite(
            id: id,
            accountID: AccountID(accountID),
            payload: decoded,
            createdAt: createdAt,
            attemptCount: attemptCount
        )
    }

    /// Maps a payload variant to its `kind` string for the column. Kept
    /// in one place so a new variant can't accidentally land without
    /// being indexable.
    static func kind(of payload: PendingWritePayload) -> String {
        switch payload {
        case .createTask: "createTask"
        case .updateTask: "updateTask"
        case .completeTask: "completeTask"
        case .deleteTask: "deleteTask"
        case .moveTask: "moveTask"
        case .createList: "createList"
        case .renameList: "renameList"
        case .deleteList: "deleteList"
        }
    }
}
