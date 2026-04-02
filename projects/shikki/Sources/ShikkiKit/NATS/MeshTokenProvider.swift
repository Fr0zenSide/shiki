import CryptoKit
import Foundation

// MARK: - MeshTokenError

/// Errors from mesh token loading/validation.
public enum MeshTokenError: Error, Sendable {
    case notSet
    case empty
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

    /// Load a token from a provided value (useful for tests and config injection).
    public static func loadFromValue(_ value: String) -> String {
        value
    }

    /// Validate that a token is non-empty.
    /// - Throws: `MeshTokenError.empty` if the token is blank.
    public static func validate(_ token: String) throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshTokenError.empty
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
