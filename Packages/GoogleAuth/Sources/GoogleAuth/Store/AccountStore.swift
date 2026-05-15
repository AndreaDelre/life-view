import Foundation

/// Single source of truth for the set of connected accounts and the access
/// tokens that go with them.
///
/// Actor-isolated for two reasons:
///
/// 1. The Keychain item layer is one record per ``AccountID`` but the
///    in-memory index that decides *which* records exist is shared
///    mutable state. Serialising mutations through the actor keeps
///    "add + select" and "remove + reselect" atomic without ad-hoc
///    locking.
/// 2. Token reads from every per-account ``GoogleTasksClient`` converge
///    here. The actor lets a long-running refresh suspend without
///    blocking concurrent token reads for *other* accounts (each call
///    only re-enters the actor briefly to read state, then suspends on
///    the network).
///
/// Refresh is independent per account: a failing refresh on account A
/// must not block reads from account B. That's a natural fit for the
/// actor model — the network call happens off-isolation and yields the
/// actor between awaits.
public actor AccountStore {
    private let keychain: KeychainStoring
    private let indexStorage: AccountIndexStorage
    private let refresher: TokenRefreshing
    private let revoker: TokenRevoking
    private let migrator: MonoAccountMigrating?
    private let clock: @Sendable () -> Date

    /// `nil` until ``loadAll()`` has run at least once. We avoid touching
    /// the Keychain in `init` so the actor can be assembled on launch
    /// from the main thread without paying for I/O before the panel even
    /// opens.
    private var index: AccountIndex?
    /// Lazy cache of the (profile, tokens) tuple for each known account.
    /// Populated on demand by ``record(for:)``.
    private var records: [AccountID: Record] = [:]

    /// Live subscribers to ``snapshots``. Keyed by token so we can drop
    /// continuations cleanly on cancellation without a linear scan.
    private var continuations: [UUID: AsyncStream<AccountsSnapshot>.Continuation] = [:]

    private struct Record: Sendable {
        var account: Account
        var tokens: TokenSet
    }

    public init(
        keychain: KeychainStoring,
        indexStorage: AccountIndexStorage,
        refresher: TokenRefreshing,
        revoker: TokenRevoking,
        migrator: MonoAccountMigrating? = nil,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.indexStorage = indexStorage
        self.refresher = refresher
        self.revoker = revoker
        self.migrator = migrator
        self.clock = clock
    }

    // MARK: - Loading

    /// Hydrates the in-memory state from disk and publishes the resulting
    /// snapshot. Idempotent: subsequent calls just return the cached
    /// snapshot without re-reading the Keychain.
    @discardableResult
    public func loadAll() throws -> AccountsSnapshot {
        if let index {
            return snapshot(from: index)
        }

        var loaded = indexStorage.read()

        // First launch on a P2 install: pull the legacy mono-account record
        // forward and persist it under the new id shape. We do this *before*
        // hydrating records so the legacy keychain item is gone by the time
        // any caller observes the snapshot.
        if loaded.orderedIDs.isEmpty, let migrator {
            if let migrated = try migrator.runIfNeeded() {
                let secrets = StoredAccountSecrets(profile: migrated.account.profile, tokens: migrated.tokens)
                try keychain.write(secrets, key: migrated.account.id.rawValue)
                records[migrated.account.id] = Record(account: migrated.account, tokens: migrated.tokens)
                loaded = AccountIndex(
                    orderedIDs: [migrated.account.id],
                    selectedID: migrated.account.id
                )
                indexStorage.write(loaded)
            }
        }

        // Drop ids that point at missing Keychain items. This can happen if
        // the user wiped the Keychain manually or if a previous crash
        // interrupted a write. Self-heal rather than fail.
        let surviving = try loaded.orderedIDs.filter { id in
            guard try keychain.read(StoredAccountSecrets.self, key: id.rawValue) != nil else { return false }
            return true
        }
        var healed = loaded
        if surviving.count != loaded.orderedIDs.count {
            healed.orderedIDs = surviving
            if let selected = healed.selectedID, !surviving.contains(selected) {
                healed.selectedID = surviving.first
            }
            indexStorage.write(healed)
        }

        index = healed
        return snapshot(from: healed)
    }

    /// Returns the current snapshot without forcing a Keychain read when
    /// the store is already hydrated. Callers that may run before the
    /// first load should prefer ``loadAll()``.
    public func currentSnapshot() throws -> AccountsSnapshot {
        try loadAll()
    }

    // MARK: - Mutation

    /// Adds a new account, or refreshes the tokens/profile of an existing
    /// one when the Google `subject` matches a record we already have.
    ///
    /// The id carried by `account` is the freshly-generated local UUID
    /// produced by ``GoogleSignInService``; we keep it only for genuinely
    /// new accounts. When a duplicate is detected by `subject`, we
    /// preserve the existing local id so the user's avatar order and
    /// downstream caches don't reshuffle on a re-consent.
    @discardableResult
    public func addAccount(_ account: Account, tokens: TokenSet) throws -> AccountsSnapshot {
        try ensureLoaded()

        if let subject = account.subject,
           let existingID = try findID(matching: subject) {
            // Existing account re-authorising — keep the local id, refresh
            // everything that may have changed (profile, tokens).
            var updatedProfile = account.profile
            updatedProfile.displayName = updatedProfile.displayName ?? records[existingID]?.account.profile.displayName
            let updatedAccount = Account(id: existingID, profile: updatedProfile)
            try persistRecord(Record(account: updatedAccount, tokens: tokens))
            var current = index ?? .empty
            current.selectedID = existingID
            try persistIndex(current)
            return publish()
        }

        // Brand-new account.
        try persistRecord(Record(account: account, tokens: tokens))
        var current = index ?? .empty
        current.orderedIDs.append(account.id)
        current.selectedID = account.id
        try persistIndex(current)
        return publish()
    }

    /// Removes one account: revokes its refresh token best-effort, then
    /// wipes the Keychain item and updates the index. If the removed
    /// account was selected, selection falls to the next account in
    /// display order (or `nil` if the roster is now empty).
    @discardableResult
    public func removeAccount(_ id: AccountID) async throws -> AccountsSnapshot {
        try ensureLoaded()

        // Soft-fail revocation: the user asked to disconnect, the local
        // purge must proceed even if Google is unreachable. The token
        // expires on its own; nothing leaks because the Keychain item is
        // wiped below.
        if let record = try await record(for: id) {
            do {
                try await revoker.revoke(token: record.tokens.refreshToken)
            } catch {
                // Intentional swallow — see comment above.
            }
        }

        try keychain.delete(key: id.rawValue)
        records.removeValue(forKey: id)

        var current = index ?? .empty
        current.orderedIDs.removeAll(where: { $0 == id })
        if current.selectedID == id {
            current.selectedID = current.orderedIDs.first
        }
        try persistIndex(current)
        return publish()
    }

    /// Updates the persisted display name. `nil` clears the override and
    /// re-exposes whatever name Google supplied at sign-in.
    @discardableResult
    public func renameAccount(_ id: AccountID, displayName: String?) throws -> AccountsSnapshot {
        try ensureLoaded()
        guard var record = records[id] ?? loadRecord(id: id) else { return publish() }
        record.account.profile.displayName = displayName?.isEmpty == true ? nil : displayName
        try persistRecord(record)
        return publish()
    }

    /// Switches the selected account. No-op (but still publishes) if `id`
    /// is already selected. Throws when the id is unknown.
    @discardableResult
    public func select(_ id: AccountID) throws -> AccountsSnapshot {
        try ensureLoaded()
        var current = index ?? .empty
        guard current.orderedIDs.contains(id) else { throw GoogleOAuthError.noAccount }
        guard current.selectedID != id else { return snapshot(from: current) }
        current.selectedID = id
        try persistIndex(current)
        return publish()
    }

    // MARK: - Token vending

    /// Returns a non-expired access token for `id`, refreshing if needed.
    public func validAccessToken(for id: AccountID) async throws -> String {
        guard let record = try await record(for: id) else { throw GoogleOAuthError.noAccount }
        if !record.tokens.isAccessTokenExpired(now: clock()) {
            return record.tokens.accessToken
        }
        return try await refresh(record: record)
    }

    /// Forces a refresh regardless of the cached expiry. Used by the Tasks
    /// client on a `401` retry — see comment in the P3 client.
    public func forceRefreshAccessToken(for id: AccountID) async throws -> String {
        guard let record = try await record(for: id) else { throw GoogleOAuthError.noAccount }
        return try await refresh(record: record)
    }

    // MARK: - Read accessors

    public func account(for id: AccountID) async throws -> Account? {
        try await record(for: id)?.account
    }

    // MARK: - Publication

    /// Async stream of snapshots. The current snapshot is emitted
    /// synchronously to the subscriber on subscription; subsequent
    /// snapshots arrive after every successful mutation.
    public var snapshots: AsyncStream<AccountsSnapshot> {
        AsyncStream { continuation in
            let token = UUID()
            // The builder closure runs synchronously inside the actor
            // because ``snapshots`` is an actor-isolated property getter,
            // so registration is a same-isolation call. The termination
            // handler, however, is `@Sendable` and may fire from any
            // context: it hops back via a Task.
            register(token: token, continuation: continuation)
            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(token: token) }
            }
        }
    }

    private func register(token: UUID, continuation: AsyncStream<AccountsSnapshot>.Continuation) {
        continuations[token] = continuation
        // Replay the current state so the new subscriber doesn't have to
        // wait until the next mutation to render.
        if let index {
            continuation.yield(snapshot(from: index))
        }
    }

    private func unregister(token: UUID) {
        continuations.removeValue(forKey: token)
    }

    // MARK: - Internals

    private func ensureLoaded() throws {
        if index == nil { _ = try loadAll() }
    }

    /// Fast accessor for an account record: returns the cached entry if
    /// available, otherwise reads it from the Keychain on demand.
    private func record(for id: AccountID) async throws -> Record? {
        try ensureLoaded()
        if let cached = records[id] { return cached }
        guard let loaded = loadRecord(id: id) else { return nil }
        records[id] = loaded
        return loaded
    }

    private func loadRecord(id: AccountID) -> Record? {
        guard let secrets = try? keychain.read(StoredAccountSecrets.self, key: id.rawValue) else { return nil }
        let account = Account(id: id, profile: secrets.profile)
        return Record(account: account, tokens: secrets.tokens)
    }

    private func findID(matching subject: String) throws -> AccountID? {
        try ensureLoaded()
        for id in index?.orderedIDs ?? [] {
            let record = records[id] ?? loadRecord(id: id)
            if let record {
                records[id] = record
                if record.account.subject == subject { return id }
            }
        }
        return nil
    }

    private func persistRecord(_ record: Record) throws {
        let secrets = StoredAccountSecrets(profile: record.account.profile, tokens: record.tokens)
        try keychain.write(secrets, key: record.account.id.rawValue)
        records[record.account.id] = record
    }

    private func persistIndex(_ next: AccountIndex) throws {
        indexStorage.write(next)
        index = next
    }

    private func refresh(record: Record) async throws -> String {
        let refreshed = try await refresher.refresh(refreshToken: record.tokens.refreshToken)
        let updated = TokenSet(
            accessToken: refreshed.accessToken,
            refreshToken: record.tokens.refreshToken,
            accessTokenExpiresAt: refreshed.expiresAt
        )
        var updatedRecord = record
        updatedRecord.tokens = updated
        try persistRecord(updatedRecord)
        _ = publish()
        return updated.accessToken
    }

    @discardableResult
    private func publish() -> AccountsSnapshot {
        let snap = snapshot(from: index ?? .empty)
        for continuation in continuations.values {
            continuation.yield(snap)
        }
        return snap
    }

    private func snapshot(from index: AccountIndex) -> AccountsSnapshot {
        let ordered = index.orderedIDs.compactMap { id -> Account? in
            if let cached = records[id] { return cached.account }
            guard let loaded = loadRecord(id: id) else { return nil }
            records[id] = loaded
            return loaded.account
        }
        let selected = index.selectedID.flatMap { id in ordered.contains(where: { $0.id == id }) ? id : nil }
            ?? ordered.first?.id
        return AccountsSnapshot(accounts: ordered, selectedID: selected)
    }
}
