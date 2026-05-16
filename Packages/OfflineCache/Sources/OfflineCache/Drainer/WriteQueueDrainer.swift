import Foundation
import GoogleAuth
import os

/// Drains the persistent write queue for one account on demand.
///
/// One instance per app; ``drain(accountID:)`` is the entry point and
/// is idempotent — call it after a successful mutation (to clear any
/// backlog), on reconnect (the main trigger), and at launch (to handle
/// writes that were queued on the previous run).
///
/// Concurrency contract:
///
/// - Each drain pass for a given account runs serially inside the
///   actor, gated by a per-account "in-flight" flag. A second call
///   for the same account while one is running becomes a no-op (the
///   running pass will pick up the freshly-enqueued write).
/// - Different accounts drain in parallel — the actor only serialises
///   the bookkeeping, not the network calls themselves.
public actor WriteQueueDrainer {
    private let cache: OfflineCacheStore
    private let executor: any PendingWriteExecutor
    private let clock: any DrainerClock
    private let logger: Logger
    private var inFlight: Set<AccountID> = []
    /// Notified each time a drain pass for an account completes
    /// (success or stop-on-auth). Mostly useful in tests.
    private var observers: [@Sendable (AccountID, DrainOutcome) -> Void] = []

    /// Maximum retries before we give up on a transient error and put
    /// the write back into the queue with the bumped attempt count
    /// (the next reconnect will try again). Chosen so a flaky network
    /// hiccup of a few seconds is absorbed, but a sustained outage
    /// doesn't burn CPU.
    public static let maxRetriesPerPass = 3

    /// Backoff base (doubled per attempt). With base 0.5 s the sequence
    /// is 0.5, 1, 2 — total ~3.5 s of waits before yielding the pass.
    public static let backoffBase: Duration = .milliseconds(500)

    public enum DrainOutcome: Sendable, Equatable {
        case completed(processed: Int, dropped: Int)
        case stoppedOnAuthentication(processed: Int)
        case skippedAlreadyDraining
    }

    public init(
        cache: OfflineCacheStore,
        executor: any PendingWriteExecutor,
        clock: (any DrainerClock)? = nil
    ) {
        self.cache = cache
        self.executor = executor
        self.clock = clock ?? RealDrainerClock()
        logger = Logger(subsystem: "fr.andreadelre.LifeView", category: "WriteQueueDrainer")
    }

    /// Registers an observer for drain completions. Returns a token —
    /// not currently used to deregister (the drainer outlives every
    /// observer in practice), but reserved for future symmetry.
    @discardableResult
    public func addObserver(_ observer: @Sendable @escaping (AccountID, DrainOutcome) -> Void) -> UUID {
        observers.append(observer)
        return UUID()
    }

    /// Drains every queued write for `accountID`, in `createdAt` order.
    /// Returns when the queue is empty, when authentication fails, or
    /// when the per-pass retry budget is exhausted for the head entry.
    @discardableResult
    public func drain(accountID: AccountID) async -> DrainOutcome {
        if inFlight.contains(accountID) {
            return .skippedAlreadyDraining
        }
        inFlight.insert(accountID)
        defer { inFlight.remove(accountID) }

        var processed = 0
        var dropped = 0

        while true {
            let writes: [PendingWrite]
            do {
                writes = try await cache.pendingWrites(accountID: accountID)
            } catch {
                logger.error("Failed to read pending writes: \(error.localizedDescription, privacy: .public)")
                let outcome: DrainOutcome = .completed(processed: processed, dropped: dropped)
                notify(accountID, outcome)
                return outcome
            }
            guard let head = writes.first else {
                let outcome: DrainOutcome = .completed(processed: processed, dropped: dropped)
                notify(accountID, outcome)
                return outcome
            }

            let result = await attemptReplay(head)
            switch result {
            case .success:
                processed += 1
            case .dropped:
                dropped += 1
            case .auth:
                let outcome: DrainOutcome = .stoppedOnAuthentication(processed: processed)
                notify(accountID, outcome)
                return outcome
            case .deferRetry:
                // Head couldn't be processed even after the in-pass
                // retries: surface back to caller; the next reconnect
                // (or next manual drain) will try again.
                let outcome: DrainOutcome = .completed(processed: processed, dropped: dropped)
                notify(accountID, outcome)
                return outcome
            }
        }
    }

    // MARK: - Replay

    private enum ReplayResult {
        case success
        case dropped
        case auth
        case deferRetry
    }

    private func attemptReplay(_ write: PendingWrite) async -> ReplayResult {
        for attempt in 0 ..< Self.maxRetriesPerPass {
            do {
                try await executor.execute(write)
                try? await cache.removeWrite(id: write.id)
                return .success
            } catch let executionError as PendingWriteExecutionError {
                switch executionError.classification {
                case .permanent:
                    logger.error("Dropping pending write \(write.id, privacy: .public): \(executionError.message, privacy: .public)")
                    try? await cache.removeWrite(id: write.id)
                    return .dropped
                case .authentication:
                    logger.info("Auth failure during drain — stopping pass for account")
                    try? await cache.bumpAttempt(id: write.id)
                    return .auth
                case .transient:
                    try? await cache.bumpAttempt(id: write.id)
                    if attempt + 1 == Self.maxRetriesPerPass { return .deferRetry }
                    await sleepForBackoff(attempt: attempt)
                }
            } catch {
                // Unknown error class: treat as transient (safer than
                // dropping user data on a misclassified error).
                try? await cache.bumpAttempt(id: write.id)
                if attempt + 1 == Self.maxRetriesPerPass { return .deferRetry }
                await sleepForBackoff(attempt: attempt)
            }
        }
        return .deferRetry
    }

    private func sleepForBackoff(attempt: Int) async {
        // 0.5s, 1s, 2s, … capped naturally by `maxRetriesPerPass`.
        let factor = 1 << attempt
        let backoff = Self.backoffBase * factor
        try? await clock.sleep(for: backoff)
    }

    private func notify(_ accountID: AccountID, _ outcome: DrainOutcome) {
        for observer in observers {
            observer(accountID, outcome)
        }
    }
}

/// Test seam for the drainer's `Task.sleep` so unit tests don't have to
/// burn real seconds on the retry backoff. Production uses
/// `RealDrainerClock`, tests supply an instant-return stub.
public protocol DrainerClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct RealDrainerClock: DrainerClock {
    public init() {}
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
