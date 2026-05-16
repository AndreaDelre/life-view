import Foundation

/// Per-field update intent for partial mutations.
///
/// Models the distinction the JSON-merge-PATCH spec relies on:
/// - ``unchanged`` — omit the field from the request body
/// - ``set(_:)`` with a value — write that value
/// - ``set(_:)`` with `nil` — clear the field (encoded as JSON `null`)
///
/// `Optional` alone cannot express the three states because `nil` would
/// have to double as both "don't touch" and "clear", which the API
/// reads very differently.
public enum Patch<T: Sendable>: Sendable {
    case unchanged
    case set(T?)

    /// Convenience for the clear-the-field case.
    public static var clear: Patch<T> {
        .set(nil)
    }
}

extension Patch: Equatable where T: Equatable {}

/// Partial update payload for an existing ``TaskItem``.
///
/// Used by both ``GoogleTasksClient`` (for the PATCH request body) and
/// the view-model layer (for optimistic local mutation). `position` is
/// not exposed: P5 does not reorder; reordering ships in P6.
public struct TaskPatch: Sendable, Equatable {
    public var title: Patch<String>
    public var notes: Patch<String>
    public var due: Patch<Date>
    public var status: Patch<TaskStatus>

    public init(
        title: Patch<String> = .unchanged,
        notes: Patch<String> = .unchanged,
        due: Patch<Date> = .unchanged,
        status: Patch<TaskStatus> = .unchanged
    ) {
        self.title = title
        self.notes = notes
        self.due = due
        self.status = status
    }

    /// True when no field changes — a no-op the client can short-circuit.
    public var isEmpty: Bool {
        Self.isUnchanged(title)
            && Self.isUnchanged(notes)
            && Self.isUnchanged(due)
            && Self.isUnchanged(status)
    }

    private static func isUnchanged<T>(_ patch: Patch<T>) -> Bool {
        if case .unchanged = patch { return true }
        return false
    }

    /// Applies the patch to a task in place, mirroring the semantics the
    /// server will apply. Used by the view-model to keep the optimistic
    /// UI in sync with what the API will eventually return.
    public func apply(to task: inout TaskItem) {
        if case let .set(value) = title, let value {
            task.title = value
        }
        if case let .set(value) = notes {
            task.notes = value
        }
        if case let .set(value) = due {
            task.due = value
        }
        if case let .set(value) = status, let value {
            task.status = value
        }
    }
}
