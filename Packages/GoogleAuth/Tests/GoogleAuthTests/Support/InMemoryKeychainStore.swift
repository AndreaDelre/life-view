import Foundation
@testable import GoogleAuth

/// In-memory ``KeychainStoring`` fake used to drive the upper layers without
/// touching the real Keychain in unit tests.
final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let queue = DispatchQueue(label: "InMemoryKeychainStore")
    private var storage: [String: Data] = [:]

    func read(key: String) throws -> Data? {
        queue.sync { storage[key] }
    }

    func write(_ data: Data, key: String) throws {
        queue.sync { storage[key] = data }
    }

    func delete(key: String) throws {
        queue.sync { storage.removeValue(forKey: key) }
    }

    var snapshot: [String: Data] {
        queue.sync { storage }
    }
}
