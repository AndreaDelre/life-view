import Foundation
import GoogleAuth

/// Public, Sendable representation of a queued write read off the
/// `pending_writes` table.
///
/// Carries enough metadata for the drainer to: order entries by
/// `createdAt`, scope a drain pass per `accountID`, and apply a retry
/// policy keyed on `attemptCount`. Values are immutable: the drainer
/// either deletes the row (success / drop) or bumps `attemptCount` via
/// the dedicated cache method (retry).
public struct PendingWrite: Sendable, Equatable, Identifiable {
    public let id: String
    public let accountID: AccountID
    public let payload: PendingWritePayload
    public let createdAt: Date
    public let attemptCount: Int

    public init(
        id: String,
        accountID: AccountID,
        payload: PendingWritePayload,
        createdAt: Date,
        attemptCount: Int
    ) {
        self.id = id
        self.accountID = accountID
        self.payload = payload
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }
}
