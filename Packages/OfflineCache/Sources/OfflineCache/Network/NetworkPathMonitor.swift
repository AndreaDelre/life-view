import Foundation
import Network

/// Process-wide connectivity monitor.
///
/// Wraps `NWPathMonitor` so callers can:
///
/// 1. read the current status synchronously via ``isOnline``, and
/// 2. subscribe to changes via the async stream ``statuses``.
///
/// The monitor lives in an actor and runs on its own internal queue
/// (`NWPathMonitor.start(queue:)`). Crucially, **it is decoupled from
/// any view's lifecycle**: a `NSPanel`-hosted view can be deallocated
/// when the panel closes, and the underlying `NWPathMonitor` must keep
/// running so the queue drains and reconnections trigger correctly
/// even when the user has the panel hidden.
public actor NetworkPathMonitor {
    public enum Status: Sendable, Equatable {
        case online
        case offline
    }

    private let monitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var currentStatus: Status = .online
    private var continuations: [UUID: AsyncStream<Status>.Continuation] = [:]
    private var didStart = false

    public init() {
        monitor = NWPathMonitor()
        monitorQueue = DispatchQueue(label: "fr.andreadelre.LifeView.NetworkPathMonitor")
    }

    /// Starts the underlying monitor and wires the path callback so it
    /// hops back into the actor for the broadcast. Idempotent.
    public func start() {
        guard !didStart else { return }
        didStart = true
        monitor.pathUpdateHandler = { [weak self] path in
            let next: Status = path.status == .satisfied ? .online : .offline
            Task { [weak self] in
                await self?.apply(status: next)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Stops the monitor and tears down every subscription. Tests-only.
    public func stop() {
        monitor.cancel()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        didStart = false
    }

    /// Current status as last observed by the monitor.
    public var isOnline: Bool {
        currentStatus == .online
    }

    /// Async sequence that yields the current status as its first
    /// value, then every change. Subscribers receive the same stream of
    /// events; cancelling the iterating Task unsubscribes.
    public var statuses: AsyncStream<Status> {
        let initial = currentStatus
        return AsyncStream { continuation in
            let token = UUID()
            continuation.yield(initial)
            // Register the continuation back on the actor. This needs
            // to hop because `AsyncStream`'s builder closure runs
            // synchronously on the caller, not on the actor.
            Task { [weak self] in
                await self?.register(token: token, continuation: continuation)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { [weak self] in
                    await self?.deregister(token: token)
                }
            }
        }
    }

    // MARK: - Internals

    private func apply(status: Status) {
        guard status != currentStatus else { return }
        currentStatus = status
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }

    private func register(token: UUID, continuation: AsyncStream<Status>.Continuation) {
        continuations[token] = continuation
    }

    private func deregister(token: UUID) {
        continuations.removeValue(forKey: token)
    }

    // MARK: - Test helpers

    /// Test-only hook to inject a synthetic status transition without
    /// the system network. Production code only mutates via the path
    /// callback above.
    public func testApply(status: Status) {
        apply(status: status)
    }
}
