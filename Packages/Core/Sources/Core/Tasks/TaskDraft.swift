import Foundation

/// Input shape for creating a new task.
///
/// Kept separate from ``TaskItem`` because creation has a different
/// contract: no `id` (Google assigns one), no `position` (Google places
/// the task at the top of the list), no `status` (defaults to
/// `needsAction`). Modelling these as a distinct type avoids the
/// ergonomic trap of having to invent placeholder values for fields the
/// caller cannot supply.
public struct TaskDraft: Sendable, Equatable {
    public var title: String
    public var notes: String?
    public var due: Date?

    public init(title: String, notes: String? = nil, due: Date? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
    }
}
