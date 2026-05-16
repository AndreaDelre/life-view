import Core
import Foundation
import GoogleAuth
import GRDB

/// Disk-backed cache + pending-write log for the offline mode.
///
/// One instance for the whole app — partitioning is internal, by the
/// `accountID` column on every row. Backed by a GRDB
/// ``DatabasePool`` so reads happen on a worker pool while writes
/// serialise on a dedicated writer; the actor envelope on top serialises
/// the public mutating API and protects the encoders / decoders.
///
/// The store is intentionally **stateless** beyond the database handle:
/// no in-memory mirror, no observation pipeline. The view-model already
/// is the source of truth in memory; the cache is just what survives
/// across launches.
public actor OfflineCacheStore {
    /// `any DatabaseWriter` so the on-disk (`DatabasePool`) and the
    /// in-memory test (`DatabaseQueue`) variants share the same code
    /// path. Both conform to `DatabaseWriter` which is the protocol
    /// that exposes `read`/`write` plus migrator support.
    private let dbWriter: any DatabaseWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Opens (or creates) the cache database at `path`. Runs the
    /// migrator on init so the schema is current by the time the first
    /// read fires.
    public init(databasePath: URL) throws {
        // Ensure the parent directory exists — GRDB will not create it.
        let parent = databasePath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        var config = Configuration()
        // Foreign keys aren't used (composite PKs are the integrity
        // story) but enabling the pragma keeps a future migration that
        // adds FKs safe without flipping a global default.
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: databasePath.path, configuration: config)
        dbWriter = pool

        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()

        try CacheSchema.makeMigrator().migrate(pool)
    }

    /// In-memory cache used by tests (no on-disk file). The schema is
    /// applied at init time, exactly like the on-disk variant.
    public static func inMemory() throws -> OfflineCacheStore {
        try OfflineCacheStore(memoryQueue: DatabaseQueue())
    }

    private init(memoryQueue: DatabaseQueue) throws {
        dbWriter = memoryQueue
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
        try CacheSchema.makeMigrator().migrate(memoryQueue)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    // MARK: - Synchronous snapshot

    /// Builds a one-shot snapshot of `accountID`'s cached data.
    ///
    /// `nonisolated` and **synchronous** so the main-actor view-model
    /// can call it at launch without an `await` — that hop would add
    /// at least one runloop tick to the very first frame the user
    /// sees after the panel slides in.
    ///
    /// Uses `dbWriter.read` under the hood, which blocks until SQLite
    /// returns; the call is fast enough (a few ms on a warm DB) to be
    /// safe on the main actor for the initial paint. Subsequent
    /// refreshes go through the async API.
    nonisolated public func snapshot(accountID: AccountID) throws -> OfflineCacheSnapshot {
        try dbWriter.read { db in
            let lists = try ListRecord
                .filter(Column("accountID") == accountID.rawValue)
                .fetchAll(db)
                .map(\.domain)

            let taskRows = try TaskRecord
                .filter(Column("accountID") == accountID.rawValue)
                .order(Column("position"))
                .fetchAll(db)

            var grouped: [String: [TaskItem]] = [:]
            for row in taskRows {
                guard let item = row.domain else { continue }
                grouped[row.listID, default: []].append(item)
            }
            // SQLite gives us tasks sorted by `position` globally, but
            // the position string is sibling-local — re-arrange each
            // list so children sit immediately under their parent.
            for key in grouped.keys {
                grouped[key] = TaskItem.hierarchicallySorted(grouped[key] ?? [])
            }
            return OfflineCacheSnapshot(lists: lists, tasksByList: grouped)
        }
    }

    // MARK: - Lists

    /// Replaces the cached lists for `accountID` with `lists`. Used by
    /// every successful `fetchTaskLists`: a list that was deleted
    /// server-side disappears locally on the next sync without us
    /// having to track tombstones.
    public func saveLists(_ lists: [TaskList], accountID: AccountID) throws {
        let records = lists.map { ListRecord(accountID: accountID, list: $0) }
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM lists WHERE accountID = ?",
                arguments: [accountID.rawValue]
            )
            for record in records {
                try record.insert(db)
            }
        }
    }

    /// Returns all cached lists for `accountID`. Mostly useful in tests
    /// — production code reads through ``snapshot(accountID:)``.
    public func loadLists(accountID: AccountID) throws -> [TaskList] {
        try dbWriter.read { db in
            try ListRecord
                .filter(Column("accountID") == accountID.rawValue)
                .fetchAll(db)
                .map(\.domain)
        }
    }

    /// Upserts one list (used after a `renameList` mutation succeeds).
    public func upsertList(_ list: TaskList, accountID: AccountID) throws {
        let record = ListRecord(accountID: accountID, list: list)
        try dbWriter.write { db in
            try record.save(db)
        }
    }

    /// Drops a list and every task it contained (the server's cascade).
    public func deleteList(listID: String, accountID: AccountID) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM lists WHERE accountID = ? AND listID = ?",
                arguments: [accountID.rawValue, listID]
            )
            try db.execute(
                sql: "DELETE FROM tasks WHERE accountID = ? AND listID = ?",
                arguments: [accountID.rawValue, listID]
            )
        }
    }

    // MARK: - Tasks

    /// Replaces the cached tasks for `(accountID, listID)` with `tasks`.
    /// Same rationale as ``saveLists`` for the wipe-then-insert pattern.
    public func saveTasks(_ tasks: [TaskItem], listID: String, accountID: AccountID) throws {
        let records = tasks.map { TaskRecord(accountID: accountID, listID: listID, task: $0) }
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM tasks WHERE accountID = ? AND listID = ?",
                arguments: [accountID.rawValue, listID]
            )
            for record in records {
                try record.insert(db)
            }
        }
    }

    /// Returns cached tasks for one list, sorted hierarchically (each
    /// top-level task immediately followed by its sub-tasks). Mostly
    /// used in tests; the view-model reads via ``snapshot``.
    public func loadTasks(listID: String, accountID: AccountID) throws -> [TaskItem] {
        try dbWriter.read { db in
            let items = try TaskRecord
                .filter(Column("accountID") == accountID.rawValue)
                .filter(Column("listID") == listID)
                .order(Column("position"))
                .fetchAll(db)
                .compactMap(\.domain)
            return TaskItem.hierarchicallySorted(items)
        }
    }

    /// Upsert one task (after a successful create/update/move mutation).
    public func upsertTask(_ task: TaskItem, listID: String, accountID: AccountID) throws {
        let record = TaskRecord(accountID: accountID, listID: listID, task: task)
        try dbWriter.write { db in
            try record.save(db)
        }
    }

    /// Delete one task by `taskID`.
    public func deleteTask(taskID: String, listID: String, accountID: AccountID) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM tasks WHERE accountID = ? AND listID = ? AND taskID = ?",
                arguments: [accountID.rawValue, listID, taskID]
            )
        }
    }

    /// Drops every cached row for `accountID`. Called on sign-out.
    public func wipeAccount(_ accountID: AccountID) throws {
        try dbWriter.write { db in
            for table in ["lists", "tasks", "pending_writes"] {
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE accountID = ?",
                    arguments: [accountID.rawValue]
                )
            }
        }
    }

    // MARK: - Pending writes

    /// Appends a new entry to the queue. Returns the persisted record so
    /// the caller can reference its ``PendingWrite/id`` for follow-up.
    @discardableResult
    public func enqueueWrite(
        accountID: AccountID,
        payload: PendingWritePayload,
        at createdAt: Date = Date()
    ) throws -> PendingWrite {
        let write = PendingWrite(
            id: UUID().uuidString,
            accountID: accountID,
            payload: payload,
            createdAt: createdAt,
            attemptCount: 0
        )
        let record = try PendingWriteRecord(write: write, encoder: encoder)
        try dbWriter.write { db in
            try record.insert(db)
        }
        return write
    }

    /// Returns the queue contents for `accountID` ordered by
    /// `createdAt ASC` — the order the drainer must replay them in.
    public func pendingWrites(accountID: AccountID) throws -> [PendingWrite] {
        try dbWriter.read { db in
            try PendingWriteRecord
                .filter(Column("accountID") == accountID.rawValue)
                .order(Column("createdAt"))
                .fetchAll(db)
        }
        .map { try $0.toPendingWrite(decoder: decoder) }
    }

    /// Returns the queue for every account, ordered globally by
    /// `createdAt`. The drainer uses this when reconnecting to fan out
    /// per-account drains; the ordering is preserved when partitioned.
    public func allPendingWrites() throws -> [PendingWrite] {
        try dbWriter.read { db in
            try PendingWriteRecord
                .order(Column("createdAt"))
                .fetchAll(db)
        }
        .map { try $0.toPendingWrite(decoder: decoder) }
    }

    /// Removes a queue entry by `id`. The drainer calls this after a
    /// successful replay (or a "drop on permanent failure" decision).
    public func removeWrite(id: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM pending_writes WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Bumps `attemptCount` for `id`. Called by the drainer between
    /// retries — the counter feeds the backoff calculation upstream.
    public func bumpAttempt(id: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: """
                UPDATE pending_writes
                SET attemptCount = attemptCount + 1
                WHERE id = ?
                """,
                arguments: [id]
            )
        }
    }

    /// Reads the queued payload for `id`, hands it to `transform`, then
    /// writes the result back. Used by the view-model's "collapse"
    /// logic: when the user toggles or renames a task whose creation is
    /// still queued, we mute the queued `.createTask` draft in place
    /// instead of stacking an `.updateTask` behind it. Returns the
    /// mutated payload, or `nil` if no entry with `id` exists (e.g. the
    /// drainer raced ahead and removed it).
    @discardableResult
    public func mutatePendingWrite(
        id: String,
        transform: @Sendable (PendingWritePayload) throws -> PendingWritePayload
    ) throws -> PendingWritePayload? {
        let encoder = encoder
        let decoder = decoder
        return try dbWriter.write { db in
            guard let record = try PendingWriteRecord
                .filter(Column("id") == id)
                .fetchOne(db) else { return nil }
            let current = try decoder.decode(PendingWritePayload.self, from: record.payload)
            let next = try transform(current)
            var updated = record
            updated.payload = try encoder.encode(next)
            updated.kind = PendingWriteRecord.kind(of: next)
            try updated.update(db)
            return next
        }
    }

    /// Locates the queued `.createTask` entry for `(accountID,
    /// clientTaskID)`, if one is still pending. Returns `nil` when the
    /// drainer has already flushed it (server-ID assigned) or when no
    /// such create was ever enqueued. The view-model calls this before
    /// applying a collapse so it knows whether to mute the queued draft
    /// or fall through to a regular `.updateTask` enqueue.
    public func findCreateTask(
        accountID: AccountID,
        clientTaskID: String
    ) throws -> PendingWrite? {
        let writes = try pendingWrites(accountID: accountID)
        return writes.first { write in
            if case let .createTask(_, queuedID, _) = write.payload {
                return queuedID == clientTaskID
            }
            return false
        }
    }

    // MARK: - Test helpers

    /// Drops every row in every table. Tests-only convenience.
    public func wipeAll() throws {
        try dbWriter.write { db in
            for table in ["lists", "tasks", "pending_writes"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}
