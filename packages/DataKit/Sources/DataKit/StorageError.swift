import Foundation

public enum StorageError: Error, LocalizedError, Equatable, Sendable {
    case notFound(table: String, id: String)
    case insertFailed(String)
    case queryFailed(String)
    case migrationFailed(version: Int, reason: String)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let table, let id):
            "Item '\(id)' not found in table '\(table)'"
        case .insertFailed(let reason):
            "Insert failed: \(reason)"
        case .queryFailed(let reason):
            "Query failed: \(reason)"
        case .migrationFailed(let version, let reason):
            "Migration v\(version) failed: \(reason)"
        case .connectionFailed(let reason):
            "Connection failed: \(reason)"
        }
    }
}
