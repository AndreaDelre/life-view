import GoogleAuth
import GoogleTasksClient

/// Bridges ``AccountStore`` (auth layer) to the ``TasksAuthorizing`` seam
/// expected by ``GoogleTasksClient``, **scoped to one account**.
///
/// Lives in the app target on purpose: keeping the bridge here means
/// `GoogleTasksClient` stays unaware of `GoogleAuth`, and either package
/// can be reused or swapped out without touching the other.
///
/// One adapter is instantiated per account (carried by ``accountID``) so
/// the Tasks client never needs to know which account it serves — that
/// concern lives entirely in the auth layer.
struct AccountStoreTasksAdapter: TasksAuthorizing {
    let store: AccountStore
    let accountID: AccountID

    func accessToken() async throws -> String {
        try await store.validAccessToken(for: accountID)
    }

    func refreshedAccessToken() async throws -> String {
        try await store.forceRefreshAccessToken(for: accountID)
    }
}
