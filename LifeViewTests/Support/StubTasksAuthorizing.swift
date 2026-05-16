import Foundation
import GoogleTasksClient

/// Minimal `TasksAuthorizing` stub: always returns a fixed access token.
/// LifeViewTests doesn't exercise the 401-refresh path (that's covered
/// by `GoogleTasksClientTests`); these tests focus on the view-model's
/// optimistic / rollback behaviour against deterministic responses.
final class StubTasksAuthorizing: TasksAuthorizing, @unchecked Sendable {
    func accessToken() async throws -> String {
        "tok-lifeview"
    }

    func refreshedAccessToken() async throws -> String {
        "tok-lifeview"
    }
}
