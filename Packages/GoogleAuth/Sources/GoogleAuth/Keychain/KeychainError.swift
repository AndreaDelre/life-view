import Foundation

/// Failure modes for ``KeychainStore``.
///
/// `unhandled(status:)` carries the raw `OSStatus` so callers can map it to
/// a user-facing message or just log it (without leaking item contents).
public enum KeychainError: Error, Equatable, Sendable {
    case unhandled(status: OSStatus)
    case unexpectedData
}
