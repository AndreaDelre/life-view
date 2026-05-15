import Foundation

/// Completion state of a task. Mirrors the two values Google Tasks itself
/// exposes (`needsAction` / `completed`) — the API does not have an
/// "in progress" or "deferred" status.
public enum TaskStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case needsAction
    case completed
}
