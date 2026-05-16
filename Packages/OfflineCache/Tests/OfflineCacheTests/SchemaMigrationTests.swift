import Foundation
import GRDB
@testable import OfflineCache
import XCTest

final class SchemaMigrationTests: XCTestCase {
    func test_v1Migration_createsExpectedTables() async throws {
        // Black-box check: by spinning up an in-memory store the
        // migrator has run, and querying `sqlite_master` confirms the
        // expected schema is in place.
        let queue = try DatabaseQueue()
        try CacheSchema.makeMigrator().migrate(queue)

        let tables = try await queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'"
            )
        }
        XCTAssertEqual(Set(tables), Set(["lists", "tasks", "pending_writes"]))
    }

    func test_v1Migration_isIdempotent() async throws {
        let queue = try DatabaseQueue()
        try CacheSchema.makeMigrator().migrate(queue)
        // Running the migrator again must not throw — `DatabaseMigrator`
        // records the applied set and short-circuits the no-ops.
        try CacheSchema.makeMigrator().migrate(queue)
    }
}
