import GoogleAuth
import GoogleTasksClient

/// Owns one ``GoogleTasksClient`` instance per connected account.
///
/// We deliberately keep **one client per account** rather than a single
/// client with a switching ``TasksAuthorizing`` seam:
///
/// - Each client has its own in-memory list/task cache. Per-account
///   instances therefore give us per-account caches "for free", with
///   zero risk of a refresh on account A surfacing as account B's data
///   while a request is in flight.
/// - The client is an actor; making one instance shared across accounts
///   would mean serialising *all* network traffic for *all* accounts
///   through the same actor queue, which kills the parallelism we want
///   in the aggregated "all accounts" mode.
///
/// Lives on the main actor because:
///
/// 1. it is created and torn down from the app delegate / view-models
///    (both main-actor), and
/// 2. its operations are cheap dictionary access — no benefit in moving
///    them off the main thread.
///
/// The registry never touches the network: it just hands out clients.
@MainActor
final class AccountSessionRegistry {
    private let store: AccountStore
    private var clients: [AccountID: GoogleTasksClient] = [:]

    init(store: AccountStore) {
        self.store = store
    }

    /// Returns the client for `id`, creating it on first request. Idempotent.
    func client(for id: AccountID) -> GoogleTasksClient {
        if let cached = clients[id] { return cached }
        let client = GoogleTasksClient(
            authorizing: AccountStoreTasksAdapter(store: store, accountID: id)
        )
        clients[id] = client
        return client
    }

    /// Drops the client (and its cache) for `id`. Called after a sign-out
    /// so subsequent re-connects start with a clean cache.
    func discard(_ id: AccountID) {
        clients.removeValue(forKey: id)
    }

    /// Drops every cached client. Used as a defence-in-depth on a full
    /// reset (e.g. the user disconnects every account).
    func discardAll() {
        clients.removeAll()
    }
}
