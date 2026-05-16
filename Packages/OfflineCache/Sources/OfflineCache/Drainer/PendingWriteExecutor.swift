import Foundation
import GoogleAuth

/// Bridge between the persistent queue and whatever actor knows how to
/// actually talk to Google.
///
/// Defined here (rather than inside the app target) so the drainer can
/// be unit-tested in isolation. The app target supplies a concrete
/// implementation that resolves the right `GoogleTasksClient` for the
/// account and invokes the matching method.
public protocol PendingWriteExecutor: Sendable {
    /// Replays `write` against the live service. Throws on transport /
    /// HTTP errors so the drainer can classify them and decide between
    /// retry-with-backoff and drop.
    ///
    /// The implementation MUST be idempotent for the update-flavoured
    /// variants (`updateTask`, `completeTask`, `moveTask`, `renameList`)
    /// — replaying the same write twice should not corrupt state.
    func execute(_ write: PendingWrite) async throws
}

/// Classification of an executor failure, returned by the drainer's
/// internal error mapper. Surface intentionally narrow: every error
/// either retries (transient) or drops (permanent).
public enum PendingWriteErrorClass: Sendable, Equatable {
    /// Network was unreachable, server returned 5xx, or another
    /// transient symptom — retry with backoff.
    case transient
    /// 4xx other than 401: the request will never succeed as-is.
    /// Drop the entry from the queue with a log.
    case permanent
    /// Authentication failed even after a refresh attempt. The drainer
    /// stops the current pass and surfaces this so the UI can react
    /// (typically by prompting a re-sign-in).
    case authentication
}

/// Convenience adapter so executors can hand the drainer a typed
/// classification of a thrown error without leaking GoogleTasksClient
/// specifics into this module. The executor wraps the call in a
/// `do/catch` and rethrows as a ``PendingWriteExecutionError`` when the
/// classification is known; otherwise it lets the raw error escape and
/// the drainer treats it as `.transient` (safe default).
public struct PendingWriteExecutionError: Error, Sendable, Equatable {
    public let classification: PendingWriteErrorClass
    public let message: String

    public init(classification: PendingWriteErrorClass, message: String) {
        self.classification = classification
        self.message = message
    }
}
