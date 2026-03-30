import Foundation
import Logging

/// Phase 4: Cleanup service.
/// Archives verified memory files, removes originals, updates MEMORY.md.
///
/// BR-10: Archive to ~/.cache/shikki/memory-migration-backup/ as encrypted zip.
/// BR-05: All feedback_*.md files removed post-migration.
/// BR-03: MEMORY.md rewritten to < 50 lines pointer format.
public struct MemoryCleanupService: Sendable {

    private let scanner: MemoryFileScanner
    private let archiveDirectory: String
    private let logger: Logger

    /// The new MEMORY.md content (BR-11c pointer format, < 50 lines).
    public static let pointerManifest = """
    # Shikki Memory — Query Pointers

    > This file contains NO sensitive data. All knowledge is stored in ShikiDB.
    > Claude: use `shi memory` to load context, or these queries as fallback.

    ## How to Load Context

    ### Personal preferences
    POST /api/memories/search { "scope": "personal", "category": "preference" }

    ### Current project backlog
    POST /api/memories/search { "scope": "project", "category": "backlog" }

    ### Architecture decisions
    POST /api/memories/search { "scope": "project", "category": "decision" }

    ### Company vision
    POST /api/memories/search { "scope": "company", "category": "vision" }

    ### Infrastructure & conventions
    POST /api/memories/search { "scope": "company", "category": "infrastructure" }

    ## Conventions (safe for git — generic only)

    - Branching: git flow (main <- release/* <- develop <- feature/*)
    - All PRs target develop, never main
    - SPM packages in packages/, projects in projects/
    - Testing: one simulator (latest iOS), no benchmark theater, no print() in tests
    - Docker: Colima (not Docker Desktop)
    - LM Studio: http://127.0.0.1:1234
    - Agent aliases: @shi / @t = full team, @db = ShikiDB
    - Swift 6 strict concurrency required
    """

    public init(
        scanner: MemoryFileScanner,
        archiveDirectory: String? = nil,
        logger: Logger = Logger(label: "shikki.memory.cleanup")
    ) {
        self.scanner = scanner
        self.archiveDirectory = archiveDirectory ?? Self.defaultArchiveDirectory
        self.logger = logger
    }

    /// Default backup archive location (BR-10).
    public static let defaultArchiveDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.cache/shikki/memory-migration-backup"
    }()

    /// Run full cleanup: archive verified files, remove originals, rewrite MEMORY.md.
    ///
    /// - Parameter verificationReport: Must be a passing report (isComplete == true).
    /// - Parameter dryRun: If true, only log actions without modifying files.
    /// - Returns: A ``CleanupReport`` summarizing what was done.
    public func cleanup(
        verificationReport: VerificationReport,
        dryRun: Bool = false
    ) throws -> CleanupReport {
        guard verificationReport.isComplete else {
            throw MemoryCleanupError.verificationNotPassed(
                "Verification has \(verificationReport.mismatchCount) mismatches and \(verificationReport.missingInDBCount) missing in DB"
            )
        }

        var results: [CleanupResult] = []

        // Step 1: Create archive directory
        let archivePath = try createArchive(dryRun: dryRun)
        logger.info("Archive directory: \(archivePath)")

        // Step 2: Archive each matched file
        let matchedFiles = verificationReport.results.filter { $0.status == .matched }
        for result in matchedFiles {
            let cleanupResult = archiveAndRemoveFile(
                result.filename, archivePath: archivePath, dryRun: dryRun
            )
            results.append(cleanupResult)
        }

        // Step 3: Skip files that were not verified
        let skippedFiles = verificationReport.results.filter { $0.status == .skipped }
        for result in skippedFiles {
            results.append(CleanupResult(
                filename: result.filename,
                status: .skipped,
                message: "Skipped (not migrated)"
            ))
        }

        // Step 4: Rewrite MEMORY.md (BR-03, BR-11c)
        if !dryRun {
            try rewriteMemoryIndex()
            logger.info("MEMORY.md rewritten to pointer format")
        }

        // Step 5: Create the encrypted zip archive (BR-10)
        let zipPath: String?
        if !dryRun && !matchedFiles.isEmpty {
            zipPath = try createEncryptedZip(from: archivePath)
            logger.info("Encrypted archive created: \(zipPath ?? "none")")
        } else {
            zipPath = nil
        }

        return CleanupReport(
            results: results,
            archivePath: zipPath ?? archivePath
        )
    }

    /// Archive a single file: copy to backup, then remove original.
    private func archiveAndRemoveFile(
        _ filename: String, archivePath: String, dryRun: Bool
    ) -> CleanupResult {
        let sourcePath = scanner.fullPath(for: filename)
        let destPath = (archivePath as NSString).appendingPathComponent(filename)
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourcePath) else {
            return CleanupResult(
                filename: filename,
                status: .error,
                message: "Source file not found at \(sourcePath)"
            )
        }

        if dryRun {
            return CleanupResult(
                filename: filename,
                status: .archived,
                message: "[DRY RUN] Would archive to \(destPath) and remove original"
            )
        }

        do {
            // Copy to archive
            try fm.copyItem(atPath: sourcePath, toPath: destPath)

            // Remove original
            try fm.removeItem(atPath: sourcePath)

            return CleanupResult(
                filename: filename,
                status: .archived,
                message: "Archived and removed"
            )
        } catch {
            return CleanupResult(
                filename: filename,
                status: .error,
                message: "Failed: \(error.localizedDescription)"
            )
        }
    }

    /// Create the backup archive directory.
    private func createArchive(dryRun: Bool) throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let path = (archiveDirectory as NSString).appendingPathComponent("archive-\(timestamp)")

        if !dryRun {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true
            )
        }

        return path
    }

    /// Create encrypted zip of the archive (BR-10: zip -e minimum, gpg preferred).
    private func createEncryptedZip(from archivePath: String) throws -> String {
        let zipPath = archivePath + ".zip"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // Use zip with password protection.
        // Password is a placeholder — in production, derive from identity or prompt.
        process.arguments = [
            "zip", "-rj", "-P", "shikki-migration-\(ProcessInfo.processInfo.processIdentifier)",
            zipPath, archivePath,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MemoryCleanupError.archiveFailed("zip exited with code \(process.terminationStatus)")
        }

        return zipPath
    }

    /// Rewrite MEMORY.md to the pointer format (BR-03, BR-11c).
    private func rewriteMemoryIndex() throws {
        let path = (scanner.memoryDirectory as NSString).appendingPathComponent("MEMORY.md")
        try Self.pointerManifest.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Verify the new MEMORY.md meets BR-03 (< 50 lines) and BR-12 (no PII).
    public static func validatePointerManifest(_ content: String) -> [String] {
        var issues: [String] = []

        let lines = content.components(separatedBy: "\n")
        if lines.count > 50 {
            issues.append("BR-03 violation: MEMORY.md has \(lines.count) lines (max 50)")
        }

        // BR-12: PII checklist
        let piiPatterns = [
            "Jeoffrey", "Thirot", "Faustin",
            "contact@obyw.one",
            "fundraising", "valuation", "salary",
            "runway", "cap table",
        ]

        let lower = content.lowercased()
        for pattern in piiPatterns {
            if lower.contains(pattern.lowercased()) {
                issues.append("BR-12 violation: MEMORY.md contains PII/strategy term '\(pattern)'")
            }
        }

        return issues
    }
}

public enum MemoryCleanupError: Error, CustomStringConvertible {
    case verificationNotPassed(String)
    case archiveFailed(String)

    public var description: String {
        switch self {
        case .verificationNotPassed(let msg):
            "Cannot cleanup: verification not passed — \(msg)"
        case .archiveFailed(let msg):
            "Archive creation failed: \(msg)"
        }
    }
}
