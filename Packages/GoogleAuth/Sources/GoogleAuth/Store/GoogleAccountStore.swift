import Foundation

/// Single source of truth for the persisted account and its tokens.
///
/// Actor-isolated because three call sites converge on the same Keychain
/// item (sign-in, refresh, sign-out) and we don't want concurrent reads to
/// race on a half-written token blob. The interceptor-pattern that P3 will
/// add for the Tasks API client will call ``validAccessToken()`` from
/// arbitrary contexts; serialising through the actor is what makes that
/// safe.
public actor GoogleAccountStore {
    private let keychain: KeychainStoring
    private let activeAccount: ActiveAccountStorage
    private let refresher: TokenRefreshing
    private let revoker: TokenRevoking
    private let clock: @Sendable () -> Date

    private var cache: (account: Account, tokens: TokenSet)?

    public init(
        keychain: KeychainStoring,
        activeAccount: ActiveAccountStorage,
        refresher: TokenRefreshing,
        revoker: TokenRevoking,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.activeAccount = activeAccount
        self.refresher = refresher
        self.revoker = revoker
        self.clock = clock
    }

    // MARK: - Load / save / remove

    /// Returns the persisted account, or `nil` if none is on record.
    ///
    /// Triggers a Keychain read at most once; subsequent calls use the
    /// in-actor cache.
    public func loadAccount() throws -> Account? {
        if let cache { return cache.account }
        guard let accountID = activeAccount.read() else { return nil }
        guard let secrets: StoredAccountSecrets = try keychain.read(StoredAccountSecrets.self, key: accountID.rawValue) else {
            // Pointer in UserDefaults but no Keychain item: stale state from a
            // crash or a manual `security delete`. Self-heal by clearing.
            activeAccount.write(nil)
            return nil
        }
        let account = Account(id: accountID, profile: secrets.profile)
        cache = (account, secrets.tokens)
        return account
    }

    public func saveAccount(_ account: Account, tokens: TokenSet) throws {
        let secrets = StoredAccountSecrets(profile: account.profile, tokens: tokens)
        try keychain.write(secrets, key: account.id.rawValue)
        activeAccount.write(account.id)
        cache = (account, tokens)
    }

    /// Revokes the refresh token server-side, then wipes the Keychain item.
    ///
    /// Network failure during revocation is logged but does NOT block the
    /// local purge — the user requested a disconnect and the local state
    /// must not be left holding tokens just because Google is unreachable.
    public func removeAccount() async throws {
        if cache == nil {
            _ = try? loadAccount()
        }
        let snapshot = cache

        if let tokens = snapshot?.tokens {
            do {
                try await revoker.revoke(token: tokens.refreshToken)
            } catch {
                // Soft-fail: the user asked to disconnect — proceed with the
                // local purge even if Google is unreachable. The token will
                // expire on its own; nothing leaks because the Keychain item
                // is wiped a few lines below.
            }
        }

        if let id = snapshot?.account.id ?? activeAccount.read() {
            try keychain.delete(key: id.rawValue)
        }
        activeAccount.write(nil)
        cache = nil
    }

    // MARK: - Token access

    /// Returns a non-expired access token, refreshing it if necessary.
    ///
    /// Throws ``GoogleOAuthError/noAccount`` if no account is persisted.
    public func validAccessToken() async throws -> String {
        guard try loadAccount() != nil, let entry = cache else {
            throw GoogleOAuthError.noAccount
        }

        if !entry.tokens.isAccessTokenExpired(now: clock()) {
            return entry.tokens.accessToken
        }

        let refreshed = try await refresher.refresh(refreshToken: entry.tokens.refreshToken)
        let updatedTokens = TokenSet(
            accessToken: refreshed.accessToken,
            refreshToken: entry.tokens.refreshToken,
            accessTokenExpiresAt: refreshed.expiresAt
        )
        try saveAccount(entry.account, tokens: updatedTokens)
        return updatedTokens.accessToken
    }
}
