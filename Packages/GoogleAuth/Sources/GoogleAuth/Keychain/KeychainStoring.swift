import Foundation

/// Abstract interface over the platform Keychain.
///
/// Defined as a protocol so the persistence layer can be substituted with an
/// in-memory mock in tests — touching the real Keychain in unit tests is
/// brittle (sandboxed test runners, codesign requirements, leaked items on
/// CI) and the protocol seam keeps round-trip tests pure.
public protocol KeychainStoring: Sendable {
    func read(key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func delete(key: String) throws
}

public extension KeychainStoring {
    /// Convenience: encode + write a `Codable` value as JSON.
    func write<Value: Encodable & Sendable>(_ value: Value, key: String) throws {
        let data = try JSONEncoder().encode(value)
        try write(data, key: key)
    }

    /// Convenience: read + decode a `Codable` value. Returns `nil` when the
    /// key is absent. Throws when the underlying blob is malformed — that
    /// signals a real bug or a corrupted Keychain item, not a missing one.
    func read<Value: Decodable & Sendable>(_ type: Value.Type, key: String) throws -> Value? {
        guard let data = try read(key: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}
