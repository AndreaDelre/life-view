import Foundation
import GRDB

/// Schema migrations for the offline cache.
///
/// Versioning convention: each migration is named `vN-<short-desc>` and
/// is **append-only**. Never edit a registered migration once it has
/// shipped — add a new one instead. ``DatabaseMigrator`` records the
/// applied set, so an existing database on disk only runs the
/// migrations it has not seen yet.
enum CacheSchema {
    /// Builds the migrator with every registered migration.
    ///
    /// Add new versions below as `vN`. The migrator runs them in
    /// registration order.
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-initial") { db in
            // `lists` — one row per (accountID, listID). The composite
            // primary key gives us a free index on the most common
            // read (`WHERE accountID = ?`) without an explicit one.
            try db.create(table: "lists") { table in
                table.column("accountID", .text).notNull()
                table.column("listID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("updatedAt", .double).notNull()
                table.primaryKey(["accountID", "listID"])
            }

            // `tasks` — one row per (accountID, listID, taskID).
            // `position` is denormalised so we can `ORDER BY position`
            // at read time without re-sorting in memory.
            try db.create(table: "tasks") { table in
                table.column("accountID", .text).notNull()
                table.column("listID", .text).notNull()
                table.column("taskID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("notes", .text)
                table.column("status", .text).notNull()
                table.column("due", .double)
                table.column("position", .text).notNull()
                table.primaryKey(["accountID", "listID", "taskID"])
            }

            // `pending_writes` — append-only intent log. `id` is a UUID
            // string assigned at insertion so we never have to round
            // trip an auto-generated rowid through the queue layer.
            // `payload` is the kind-specific JSON, `kind` is the
            // discriminator so we can decode lazily.
            try db.create(table: "pending_writes") { table in
                table.column("id", .text).primaryKey()
                table.column("accountID", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("payload", .blob).notNull()
                table.column("createdAt", .double).notNull()
                table.column("attemptCount", .integer).notNull().defaults(to: 0)
            }
            try db.create(
                index: "pending_writes_by_createdAt",
                on: "pending_writes",
                columns: ["createdAt"]
            )
        }

        // Adds the `parent` column to `tasks`. NULL for top-level tasks,
        // contains the parent task ID for sub-tasks — used by the UI to
        // render hierarchy (indent + visual guide).
        migrator.registerMigration("v2-tasks-parent") { db in
            try db.alter(table: "tasks") { table in
                table.add(column: "parent", .text)
            }
        }

        return migrator
    }
}
