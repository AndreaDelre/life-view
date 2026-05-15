import Foundation

/// A single task inside a ``TaskList``.
///
/// Field set chosen to match what P3 actually displays + what P5 will need
/// for write-back. `position` is the lexicographic ordering string returned
/// by Google Tasks ("00000000000000000001"…); we keep it as `String` because
/// the API contract is "compare lexicographically", not numerically.
public struct TaskItem: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var due: Date?
    public var position: String

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        status: TaskStatus,
        due: Date? = nil,
        position: String
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.due = due
        self.position = position
    }
}
