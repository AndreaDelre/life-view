import Foundation

/// A Google Tasks list (the top-level container the user sees in the
/// sidebar of `tasks.google.com`).
///
/// Domain type used across LifeView — intentionally decoupled from any
/// transport DTO so that swapping out the underlying client (or replaying
/// from a cache) does not ripple through the UI.
public struct TaskList: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var updatedAt: Date

    public init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}
