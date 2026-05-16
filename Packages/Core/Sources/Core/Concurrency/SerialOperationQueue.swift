import Foundation

/// A per-key FIFO async queue.
///
/// Each enqueued operation for a given `Key` runs after every previously
/// enqueued operation for that same key finishes. Different keys are
/// independent — operations for key A do not block operations for key B.
///
/// In LifeView this is the building block of the per-account write
/// queue P5 wires through ``TasksViewModel``: serialising writes inside
/// one account avoids races against Google Tasks (which surfaces a
/// `412 Precondition Failed` on concurrent edits to the same task),
/// while letting different accounts make progress in parallel.
///
/// The queue itself is non-allocating in steady state: only one
/// ``Task`` per active key is retained at any time (the "tail" each
/// new enqueue awaits). An operation that fails does not break the
/// chain — subsequent enqueues for the same key still run.
public actor SerialOperationQueue<Key: Hashable & Sendable> {
    /// Per-key chain tail. The new enqueue's task awaits this before
    /// running its own operation. We store the "success-or-failure-
    /// erased" version so a thrown error in one operation does not
    /// propagate into the next enqueue's `await previousTail.value`.
    private var tails: [Key: Task<Void, Never>] = [:]

    public init() {}

    /// Enqueues `operation` to run after every previously enqueued
    /// operation for the same `key`. Suspends until `operation`
    /// completes (or throws). Different `key`s run independently.
    public func enqueue<T: Sendable>(
        for key: Key,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let previousTail = tails[key]
        let task = Task<T, Error> {
            await previousTail?.value
            return try await operation()
        }
        // Pin the tail to a Task that swallows the result so a thrown
        // error here does not poison the chain.
        tails[key] = Task { _ = try? await task.value }
        return try await task.value
    }
}
