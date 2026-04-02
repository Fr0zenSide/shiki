import Foundation

/// BR-17: Four and only four scope levels for memory data.
public enum MemoryScope: String, Codable, Sendable, CaseIterable {
    case personal
    case project
    case company
    case global
}

/// BR-27: Deterministic category classification for memory files.
public enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case identity
    case preference
    case strategy
    case radar
    case reference
    case backlog
    case decision
    case plan
    case vision
    case infrastructure
}

/// Classification result for a single memory file per BR-27.
public struct MemoryClassification: Codable, Sendable, Equatable {
    public let filename: String
    public let scope: MemoryScope
    public let category: MemoryCategory
    public let projectId: String?

    public init(
        filename: String,
        scope: MemoryScope,
        category: MemoryCategory,
        projectId: String? = nil
    ) {
        self.filename = filename
        self.scope = scope
        self.category = category
        self.projectId = projectId
    }
}

/// Result of a single file verification against ShikiDB (Phase 3).
public struct VerificationResult: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case matched       // Content hash matches DB record
        case mismatch      // Content differs from DB record
        case missingInDB   // File exists locally but not in DB
        case missingLocal  // DB record exists but local file missing
        case skipped       // File intentionally skipped (e.g., MEMORY.md)
    }

    public let filename: String
    public let status: Status
    public let localHash: String?
    public let dbHash: String?
    public let message: String

    public init(
        filename: String,
        status: Status,
        localHash: String? = nil,
        dbHash: String? = nil,
        message: String
    ) {
        self.filename = filename
        self.status = status
        self.localHash = localHash
        self.dbHash = dbHash
        self.message = message
    }
}

/// Aggregate verification report output (BR-28, Phase 3).
public struct VerificationReport: Sendable {
    public let results: [VerificationResult]
    public let totalLocalFiles: Int
    public let totalDBRecords: Int
    public let matchedCount: Int
    public let mismatchCount: Int
    public let missingInDBCount: Int
    public let missingLocalCount: Int
    public let skippedCount: Int
    public let timestamp: Date

    public init(
        results: [VerificationResult],
        totalLocalFiles: Int,
        totalDBRecords: Int,
        timestamp: Date = Date()
    ) {
        self.results = results
        self.totalLocalFiles = totalLocalFiles
        self.totalDBRecords = totalDBRecords
        self.matchedCount = results.filter { $0.status == .matched }.count
        self.mismatchCount = results.filter { $0.status == .mismatch }.count
        self.missingInDBCount = results.filter { $0.status == .missingInDB }.count
        self.missingLocalCount = results.filter { $0.status == .missingLocal }.count
        self.skippedCount = results.filter { $0.status == .skipped }.count
        self.timestamp = timestamp
    }

    /// True if all non-skipped files matched.
    public var isComplete: Bool {
        mismatchCount == 0 && missingInDBCount == 0
    }

    /// Formatted summary for CLI output.
    public func summary() -> String {
        var lines: [String] = []
        lines.append("Verification Report (\(ISO8601DateFormatter().string(from: timestamp)))")
        lines.append(String(repeating: "\u{2500}", count: 56))
        lines.append("  Local files:      \(totalLocalFiles)")
        lines.append("  DB records:       \(totalDBRecords)")
        lines.append("  Matched:          \(matchedCount)")
        lines.append("  Mismatched:       \(mismatchCount)")
        lines.append("  Missing in DB:    \(missingInDBCount)")
        lines.append("  Missing locally:  \(missingLocalCount)")
        lines.append("  Skipped:          \(skippedCount)")
        lines.append("")

        if isComplete {
            lines.append("\u{1B}[32mVerification PASSED — all files accounted for\u{1B}[0m")
        } else {
            lines.append("\u{1B}[31mVerification FAILED\u{1B}[0m")
            let failures = results.filter { $0.status == .mismatch || $0.status == .missingInDB }
            for f in failures {
                lines.append("  [\(f.status.rawValue.uppercased())] \(f.filename): \(f.message)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Cleanup result for a single file (Phase 4).
public struct CleanupResult: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case archived    // Moved to backup archive
        case deleted     // Removed from working tree
        case skipped     // Not eligible for cleanup
        case error       // Operation failed
    }

    public let filename: String
    public let status: Status
    public let message: String

    public init(filename: String, status: Status, message: String) {
        self.filename = filename
        self.status = status
        self.message = message
    }
}

/// Aggregate cleanup report (Phase 4).
public struct CleanupReport: Sendable {
    public let results: [CleanupResult]
    public let archivePath: String?
    public let timestamp: Date

    public init(
        results: [CleanupResult],
        archivePath: String? = nil,
        timestamp: Date = Date()
    ) {
        self.results = results
        self.archivePath = archivePath
        self.timestamp = timestamp
    }

    public var archivedCount: Int { results.filter { $0.status == .archived }.count }
    public var deletedCount: Int { results.filter { $0.status == .deleted }.count }
    public var skippedCount: Int { results.filter { $0.status == .skipped }.count }
    public var errorCount: Int { results.filter { $0.status == .error }.count }

    public var isClean: Bool { errorCount == 0 }

    public func summary() -> String {
        var lines: [String] = []
        lines.append("Cleanup Report (\(ISO8601DateFormatter().string(from: timestamp)))")
        lines.append(String(repeating: "\u{2500}", count: 56))
        lines.append("  Archived:   \(archivedCount)")
        lines.append("  Deleted:    \(deletedCount)")
        lines.append("  Skipped:    \(skippedCount)")
        lines.append("  Errors:     \(errorCount)")

        if let path = archivePath {
            lines.append("")
            lines.append("  Archive:    \(path)")
        }

        lines.append("")
        if isClean {
            lines.append("\u{1B}[32mCleanup completed successfully\u{1B}[0m")
        } else {
            lines.append("\u{1B}[31mCleanup had \(errorCount) error(s)\u{1B}[0m")
            for e in results.filter({ $0.status == .error }) {
                lines.append("  [ERR] \(e.filename): \(e.message)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// DB record representing a migrated memory, returned by the search/migrated endpoint.
public struct MigratedMemoryRecord: Codable, Sendable {
    public let id: String
    public let content: String
    public let category: String?
    public let metadata: MigratedMemoryMetadata?

    public init(id: String, content: String, category: String? = nil, metadata: MigratedMemoryMetadata? = nil) {
        self.id = id
        self.content = content
        self.category = category
        self.metadata = metadata
    }
}

/// Metadata stored with each migrated memory in ShikiDB (BR-07).
public struct MigratedMemoryMetadata: Codable, Sendable {
    public let scope: String?
    public let migratedFrom: String?
    public let migratedAt: String?
    public let contentHash: String?

    public init(
        scope: String? = nil,
        migratedFrom: String? = nil,
        migratedAt: String? = nil,
        contentHash: String? = nil
    ) {
        self.scope = scope
        self.migratedFrom = migratedFrom
        self.migratedAt = migratedAt
        self.contentHash = contentHash
    }

    enum CodingKeys: String, CodingKey {
        case scope
        case migratedFrom
        case migratedAt
        case contentHash = "content_hash"
    }
}
