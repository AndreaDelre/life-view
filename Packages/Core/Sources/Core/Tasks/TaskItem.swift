import Foundation

/// A single task inside a ``TaskList``.
///
/// Field set chosen to match what P3 actually displays + what P5 will need
/// for write-back. `position` is the lexicographic ordering string returned
/// by Google Tasks ("00000000000000000001"…); we keep it as `String` because
/// the API contract is "compare lexicographically", not numerically.
///
/// `parent` is the ID of the parent task when this row is a sub-task, or
/// `nil` for top-level tasks. Google Tasks only supports a single nesting
/// level today (a sub-task can't itself have sub-tasks), but the field is
/// kept as a free-form parent ID so a deeper hierarchy on the wire would
/// still round-trip correctly through the domain layer.
public struct TaskItem: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var due: Date?
    public var position: String
    public var parent: String?

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        status: TaskStatus,
        due: Date? = nil,
        position: String,
        parent: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.due = due
        self.position = position
        self.parent = parent
    }
}
