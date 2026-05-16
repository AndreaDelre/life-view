import Core
import Foundation

/// Strongly-typed payload variants for every queued mutation.
///
/// Each case carries every field needed to replay the operation against
/// `GoogleTasksClient` once the network is back. Codable so the whole
/// payload round-trips through the SQLite `BLOB` column as one JSON
/// document — the cache layer never has to know the per-case shape.
///
/// Conflict policy (cf. ADR + brief): replays are **idempotent by
/// design** for the update-flavoured cases (`updateTask`, `completeTask`,
/// `moveTask`, `renameList`) — re-applying the same write twice yields
/// the same end state. `createTask` / `createList` carry a `clientTaskID`
/// / `clientListID` so the drain can detect a successful local replay
/// (the matching local-ID row has been re-mapped) and skip the duplicate
/// — but as a fail-safe the server will tolerate a duplicate create:
/// the user can clean up in the next sync round.
public enum PendingWritePayload: Sendable, Codable, Equatable {
    /// Insert a new task at the top of `listID`. `clientTaskID` is the
    /// "local-…" sentinel the optimistic UI assigned so the drain can
    /// replace the local row with the server-assigned one after replay.
    case createTask(
        listID: String,
        clientTaskID: String,
        draft: PendingTaskDraft
    )

    /// Partial update of an existing task. Carries the full patch shape
    /// (one field set at a time in practice, but the wire payload is the
    /// same `TaskPatch` the live mutation extension already builds).
    case updateTask(
        listID: String,
        taskID: String,
        patch: PendingTaskPatch
    )

    /// Toggle completion. Modeled separately from `updateTask` so the
    /// drainer can short-circuit a stale toggle against a fresher server
    /// state without parsing a generic patch. The payload is a boolean
    /// and the boolean is idempotent: replaying twice still leaves the
    /// task in the requested state.
    case completeTask(listID: String, taskID: String, isCompleted: Bool)

    /// Hard delete of a task. Idempotent: replaying twice yields a
    /// "task not found" on the second pass which the drainer drops.
    case deleteTask(listID: String, taskID: String)

    /// Reorder. `previousTaskID == nil` means "move to the top of the
    /// list". Idempotent — Google `tasks.move` accepts the same target
    /// twice.
    case moveTask(listID: String, taskID: String, previousTaskID: String?)

    /// Create a new task list. `clientListID` plays the same role as
    /// `clientTaskID` in `createTask`.
    case createList(clientListID: String, title: String)

    /// Rename a list. Idempotent.
    case renameList(listID: String, title: String)

    /// Delete a list (server cascades the tasks).
    case deleteList(listID: String)
}

/// Serialisable mirror of ``TaskDraft``. We don't reuse `TaskDraft`
/// directly because adding `Codable` to it would commit `Core` to a
/// persistence shape; the indirection lets `TaskDraft` evolve freely
/// while the on-disk format stays stable behind this struct.
public struct PendingTaskDraft: Sendable, Codable, Equatable {
    public var title: String
    public var notes: String?
    public var due: Date?

    public init(title: String, notes: String? = nil, due: Date? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
    }

    public init(draft: TaskDraft) {
        title = draft.title
        notes = draft.notes
        due = draft.due
    }

    /// Materialises the wire-side ``TaskDraft`` used by the live client.
    public var asDraft: TaskDraft {
        TaskDraft(title: title, notes: notes, due: due)
    }
}

/// Serialisable mirror of ``TaskPatch``. Stores the three-state
/// `unchanged / set(value) / clear` semantics as an optional `Operation`
/// per field — `nil` for "unchanged", `.set(value)` to write, `.clear`
/// to null out. Symmetric with the wire model so encoding is a
/// straightforward field-by-field map.
public struct PendingTaskPatch: Sendable, Codable, Equatable {
    public enum Operation<T: Sendable & Codable & Equatable>: Sendable, Codable, Equatable {
        case set(T)
        case clear
    }

    public var title: Operation<String>?
    public var notes: Operation<String>?
    public var due: Operation<Date>?
    public var status: Operation<String>?

    public init(
        title: Operation<String>? = nil,
        notes: Operation<String>? = nil,
        due: Operation<Date>? = nil,
        status: Operation<String>? = nil
    ) {
        self.title = title
        self.notes = notes
        self.due = due
        self.status = status
    }

    public init(patch: TaskPatch) {
        title = Self.map(patch.title)
        notes = Self.map(patch.notes)
        due = Self.map(patch.due)
        status = Self.map(patch.status).map { op in
            switch op {
            case let .set(value): .set(value.rawValue)
            case .clear: .clear
            }
        }
    }

    /// Materialises back to a wire-side `TaskPatch`.
    public var asPatch: TaskPatch {
        TaskPatch(
            title: Self.unmap(title),
            notes: Self.unmap(notes),
            due: Self.unmap(due),
            status: Self.unmapStatus(status)
        )
    }

    private static func map<T>(_ patch: Patch<T>) -> Operation<T>? {
        switch patch {
        case .unchanged: nil
        case let .set(value?): .set(value)
        case .set(nil): .clear
        }
    }

    private static func unmap<T>(_ op: Operation<T>?) -> Patch<T> {
        switch op {
        case .none: .unchanged
        case let .set(value): .set(value)
        case .clear: .clear
        }
    }

    private static func unmapStatus(_ op: Operation<String>?) -> Patch<TaskStatus> {
        switch op {
        case .none: .unchanged
        case let .set(value):
            if let status = TaskStatus(rawValue: value) { .set(status) } else { .unchanged }
        case .clear: .clear
        }
    }
}
