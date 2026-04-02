import Foundation
import Logging

/// Phase 3: Verification service.
/// Validates that migrated memories in ShikiDB match local source files.
/// Checks: completeness (all files accounted for), integrity (content hashes match).
///
/// Depends on a ``MemoryDBClientProtocol`` for DB queries (injectable for testing).
public struct MemoryVerificationService: Sendable {

    private let scanner: MemoryFileScanner
    private let dbClient: MemoryDBClientProtocol
    private let logger: Logger

    public init(
        scanner: MemoryFileScanner,
        dbClient: MemoryDBClientProtocol,
        logger: Logger = Logger(label: "shikki.memory.verify")
    ) {
        self.scanner = scanner
        self.dbClient = dbClient
        self.logger = logger
    }

    /// Run full verification: compare every local file against its DB record.
    /// Returns a ``VerificationReport`` with per-file results.
    public func verify() async throws -> VerificationReport {
        // 1. List local files
        let localFiles = try scanner.listFiles()
        logger.info("Found \(localFiles.count) local memory files")

        // 2. Fetch all migrated records from DB
        let dbRecords = try await dbClient.fetchMigratedRecords()
        logger.info("Found \(dbRecords.count) migrated records in DB")

        // Build lookup: migratedFrom filename -> record
        var dbLookup: [String: MigratedMemoryRecord] = [:]
        for record in dbRecords {
            if let filename = record.metadata?.migratedFrom {
                dbLookup[filename] = record
            }
        }

        var results: [VerificationResult] = []

        // 3. Verify each local file
        for filename in localFiles {
            let result = try verifyFile(filename, dbRecord: dbLookup[filename])
            results.append(result)
            dbLookup.removeValue(forKey: filename)
        }

        // 4. Check for DB records with no local file (already cleaned up, or orphaned)
        for (filename, _) in dbLookup {
            results.append(VerificationResult(
                filename: filename,
                status: .missingLocal,
                message: "DB record exists but no local file found"
            ))
        }

        let report = VerificationReport(
            results: results.sorted(by: { $0.filename < $1.filename }),
            totalLocalFiles: localFiles.count,
            totalDBRecords: dbRecords.count
        )

        logger.info("Verification complete: \(report.matchedCount) matched, \(report.mismatchCount) mismatched, \(report.missingInDBCount) missing in DB")
        return report
    }

    /// Verify a single file against its DB record.
    private func verifyFile(_ filename: String, dbRecord: MigratedMemoryRecord?) throws -> VerificationResult {
        guard let record = dbRecord else {
            let localHash = try scanner.contentHash(of: filename)
            return VerificationResult(
                filename: filename,
                status: .missingInDB,
                localHash: localHash,
                message: "File not found in ShikiDB (no migratedFrom match)"
            )
        }

        let localHash = try scanner.contentHash(of: filename)
        let dbHash = record.metadata?.contentHash

        if let dbHash, dbHash == localHash {
            return VerificationResult(
                filename: filename,
                status: .matched,
                localHash: localHash,
                dbHash: dbHash,
                message: "Content hash matches"
            )
        }

        // Hash mismatch or no hash stored — compare content directly
        let localContent = try scanner.readFile(filename)
        let dbContentHash = MemoryFileScanner.sha256(record.content)

        if dbContentHash == localHash {
            return VerificationResult(
                filename: filename,
                status: .matched,
                localHash: localHash,
                dbHash: dbContentHash,
                message: "Content matches (hash recomputed from DB content)"
            )
        }

        // Content-level comparison for near-matches (whitespace normalization)
        let normalizedLocal = localContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDB = record.content.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedLocal == normalizedDB {
            return VerificationResult(
                filename: filename,
                status: .matched,
                localHash: localHash,
                dbHash: dbHash ?? dbContentHash,
                message: "Content matches (after whitespace normalization)"
            )
        }

        return VerificationResult(
            filename: filename,
            status: .mismatch,
            localHash: localHash,
            dbHash: dbHash ?? dbContentHash,
            message: "Content differs between local file and DB record"
        )
    }
}

// MARK: - DB Client Protocol

/// Abstraction over ShikiDB for memory verification/cleanup operations.
/// Injectable for testing without a real DB connection.
public protocol MemoryDBClientProtocol: Sendable {
    /// Fetch all records that have a `metadata.migratedFrom` field.
    func fetchMigratedRecords() async throws -> [MigratedMemoryRecord]

    /// Search for a specific migrated memory by its original filename.
    func fetchRecord(migratedFrom filename: String) async throws -> MigratedMemoryRecord?

    /// Health check — is the DB reachable?
    func isReachable() async -> Bool
}

// MARK: - Live DB Client (curl-based, same pattern as BackendClient)

/// Production implementation that talks to ShikiDB via HTTP.
public actor MemoryDBClient: MemoryDBClientProtocol {

    private let baseURL: String
    private let projectId: String
    private let timeoutSeconds: Int
    private let logger: Logger

    public init(
        baseURL: String = "http://localhost:3900",
        projectId: String = MemoryClassifier.projectShiki,
        timeoutSeconds: Int = 10,
        logger: Logger = Logger(label: "shikki.memory.db")
    ) {
        self.baseURL = baseURL
        self.projectId = projectId
        self.timeoutSeconds = timeoutSeconds
        self.logger = logger
    }

    public func fetchMigratedRecords() async throws -> [MigratedMemoryRecord] {
        // Query memories that have migratedFrom in metadata
        let payload: [String: Any] = [
            "projectIds": [projectId],
            "query": "migratedFrom",
            "limit": 500,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try curlRequest(method: "POST", path: "/api/memories/search", body: jsonData)

        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(MemorySearchResponse.self, from: data)
        return wrapper.memories
    }

    public func fetchRecord(migratedFrom filename: String) async throws -> MigratedMemoryRecord? {
        let all = try await fetchMigratedRecords()
        return all.first { $0.metadata?.migratedFrom == filename }
    }

    public func isReachable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["curl", "-sf", "--max-time", "3", "\(baseURL)/health"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - HTTP Helper

    private func curlRequest(method: String, path: String, body: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args = [
            "curl", "-s",
            "--max-time", "\(timeoutSeconds)",
            "-X", method,
            "-H", "Accept: application/json",
        ]

        if body != nil {
            args += ["-H", "Content-Type: application/json", "-d", "@-"]
        }

        args.append("\(baseURL)\(path)")
        process.arguments = args

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        if let bodyData = body {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            stdin.fileHandleForWriting.write(bodyData)
            stdin.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            throw MemoryDBError.requestFailed(path, Int(process.terminationStatus))
        }

        return data
    }
}

/// Response wrapper for /api/memories/search.
private struct MemorySearchResponse: Codable {
    let memories: [MigratedMemoryRecord]
}

public enum MemoryDBError: Error, CustomStringConvertible {
    case requestFailed(String, Int)
    case notReachable

    public var description: String {
        switch self {
        case .requestFailed(let path, let code):
            "DB request failed: \(path) (exit code: \(code))"
        case .notReachable:
            "ShikiDB is not reachable"
        }
    }
}
