import CryptoKit
import Foundation

// MARK: - MeshTokenError

/// Errors from mesh token loading/validation.
public enum MeshTokenError: Error, Sendable {
    case notSet
    case empty
    case tooShort(length: Int)
}

// MARK: - MeshTokenProvider

/// Loads and hashes the pre-shared mesh token for node authentication.
///
/// Every node in the Shikki mesh must hold the same `SHIKKI_MESH_TOKEN`.
/// The raw token is NEVER transmitted — only its SHA-256 hash travels
/// over NATS heartbeats, so a compromised transport cannot leak the secret.
///
/// Usage:
/// ```swift
/// let token = try MeshTokenProvider.load()       // from env
/// let hash  = MeshTokenProvider.hash(token)       // SHA-256 hex
/// ```
public struct MeshTokenProvider: Sendable {

    /// Load the mesh token from the `SHIKKI_MESH_TOKEN` environment variable.
    /// - Throws: `MeshTokenError.notSet` if the variable is absent.
    /// - Throws: `MeshTokenError.empty` if the variable is empty.
    public static func load() throws -> String {
        guard let value = ProcessInfo.processInfo.environment["SHIKKI_MESH_TOKEN"] else {
            throw MeshTokenError.notSet
        }
        try validate(value)
        return value
    }

    /// Minimum acceptable token length for security.
    public static let minimumTokenLength = 8

    /// Load a token from a provided value (useful for tests and config injection).
    /// - Throws: `MeshTokenError.empty` if the value is blank.
    /// - Throws: `MeshTokenError.tooShort` if the value is shorter than `minimumTokenLength`.
    public static func loadFromValue(_ value: String) throws -> String {
        try validate(value)
        return value
    }

    /// Validate that a token is non-empty and meets minimum length.
    /// - Throws: `MeshTokenError.empty` if the token is blank.
    /// - Throws: `MeshTokenError.tooShort` if the token is shorter than `minimumTokenLength`.
    public static func validate(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeshTokenError.empty
        }
        guard trimmed.count >= minimumTokenLength else {
            throw MeshTokenError.tooShort(length: trimmed.count)
        }
    }

    /// Compute the SHA-256 hex digest of a token.
    /// This hash is included in every heartbeat — the raw token never leaves the node.
    public static func hash(_ token: String) -> String {
        let data = Data(token.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
