import GoogleAuth
import GoogleTasksClient

/// Bridges ``GoogleAccountStore`` (auth layer) to the ``TasksAuthorizing``
/// seam expected by ``GoogleTasksClient``.
///
/// Lives in the app target on purpose: keeping the bridge here means
/// `GoogleTasksClient` stays unaware of `GoogleAuth`, and either package
/// can be reused or swapped out without touching the other.
struct GoogleAccountStoreTasksAdapter: TasksAuthorizing {
    let store: GoogleAccountStore

    func accessToken() async throws -> String {
        try await store.validAccessToken()
    }

    func refreshedAccessToken() async throws -> String {
        try await store.forceRefreshAccessToken()
    }
}
