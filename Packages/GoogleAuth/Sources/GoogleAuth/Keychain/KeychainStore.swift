import Foundation
import Security

/// Concrete ``KeychainStoring`` backed by the system Keychain.
///
/// One item per `(service, key)` pair, where `key` maps to
/// `kSecAttrAccount`. Items use `kSecAttrAccessibleAfterFirstUnlock` so they
/// survive reboots but only become readable once the user has unlocked the
/// session — a sensible default for refresh tokens that the app needs as
/// soon as it launches at login.
public struct KeychainStore: KeychainStoring {
    public let service: String

    public init(service: String = "fr.andreadelre.LifeView") {
        self.service = service
    }

    // MARK: - Read

    public func read(key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    // MARK: - Write

    public func write(_ data: Data, key: String) throws {
        let query = baseQuery(for: key)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try add(data: data, key: key)
        default:
            throw KeychainError.unhandled(status: updateStatus)
        }
    }

    private func add(data: Data, key: String) throws {
        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    // MARK: - Delete

    public func delete(key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    // MARK: - Helpers

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
