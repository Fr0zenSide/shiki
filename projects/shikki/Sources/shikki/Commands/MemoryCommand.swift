import ArgumentParser
import Foundation
import ShikkiKit

/// `shi memory` — Memory migration management.
/// Subcommands: verify, cleanup, status.
struct MemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "Memory migration management — verify, cleanup, and status",
        subcommands: [
            MemoryVerifyCommand.self,
            MemoryCleanupCommand.self,
            MemoryStatusCommand.self,
        ],
        defaultSubcommand: MemoryStatusCommand.self
    )
}

// MARK: - Verify

/// `shi memory verify` — Phase 3: Validate migrated memories match local files.
struct MemoryVerifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify migrated memories in ShikiDB match local source files"
    )

    @Option(name: .long, help: "Memory directory path")
    var memoryDir: String = MemoryFileScanner.defaultMemoryDirectory

    @Option(name: .long, help: "ShikiDB base URL")
    var dbURL: String = "http://localhost:3900"

    @Flag(name: .long, help: "Output raw JSON instead of formatted report")
    var json: Bool = false

    func run() async throws {
        let scanner = MemoryFileScanner(memoryDirectory: memoryDir)
        let dbClient = MemoryDBClient(baseURL: dbURL)
        let service = MemoryVerificationService(scanner: scanner, dbClient: dbClient)

        let report = try await service.verify()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonReport = VerificationJSON(report: report)
            let data = try encoder.encode(jsonReport)
            let output = String(data: data, encoding: .utf8) ?? "{}"
            FileHandle.standardOutput.write(Data(output.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            FileHandle.standardOutput.write(Data(report.summary().utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        if !report.isComplete {
            throw ExitCode(1)
        }
    }
}

// MARK: - Cleanup

/// `shi memory cleanup` — Phase 4: Archive verified files, remove originals, update MEMORY.md.
struct MemoryCleanupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Archive migrated files and rewrite MEMORY.md to pointer format"
    )

    @Option(name: .long, help: "Memory directory path")
    var memoryDir: String = MemoryFileScanner.defaultMemoryDirectory

    @Option(name: .long, help: "ShikiDB base URL")
    var dbURL: String = "http://localhost:3900"

    @Flag(name: .long, help: "Show what would be done without modifying files")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Skip verification step (dangerous — use only if already verified)")
    var skipVerify: Bool = false

    func run() async throws {
        let scanner = MemoryFileScanner(memoryDirectory: memoryDir)
        let dbClient = MemoryDBClient(baseURL: dbURL)

        // Step 1: Verify first (unless skipped)
        let report: VerificationReport
        if skipVerify {
            FileHandle.standardOutput.write(Data("\u{1B}[33mWarning: Skipping verification\u{1B}[0m\n".utf8))
            // Build a synthetic "all matched" report from local files
            let files = try scanner.listFiles()
            let results = files.map {
                VerificationResult(
                    filename: $0,
                    status: .matched,
                    message: "Verification skipped by user"
                )
            }
            report = VerificationReport(
                results: results,
                totalLocalFiles: files.count,
                totalDBRecords: files.count
            )
        } else {
            let verifyService = MemoryVerificationService(scanner: scanner, dbClient: dbClient)
            report = try await verifyService.verify()
            FileHandle.standardOutput.write(Data(report.summary().utf8))
            FileHandle.standardOutput.write(Data("\n\n".utf8))

            guard report.isComplete else {
                FileHandle.standardOutput.write(
                    Data("\u{1B}[31mAborted: Verification failed. Fix issues before cleanup.\u{1B}[0m\n".utf8)
                )
                throw ExitCode(1)
            }
        }

        // Step 2: Cleanup
        let cleanupService = MemoryCleanupService(scanner: scanner)
        let cleanupReport = try cleanupService.cleanup(
            verificationReport: report,
            dryRun: dryRun
        )

        FileHandle.standardOutput.write(Data(cleanupReport.summary().utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))

        if !cleanupReport.isClean {
            throw ExitCode(1)
        }
    }
}

// MARK: - Status

/// `shi memory status` — Show current memory migration status.
struct MemoryStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show memory migration status"
    )

    @Option(name: .long, help: "Memory directory path")
    var memoryDir: String = MemoryFileScanner.defaultMemoryDirectory

    func run() async throws {
        let scanner = MemoryFileScanner(memoryDirectory: memoryDir)

        FileHandle.standardOutput.write(Data("\u{1B}[1m\u{1B}[36mMemory Migration Status\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data(String(repeating: "\u{2500}", count: 56).utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))

        do {
            let files = try scanner.listFiles()
            let classifier = MemoryClassifier()
            let classifications = files.compactMap { classifier.classify($0) }

            let scopeCounts = Dictionary(grouping: classifications, by: \.scope)
            let categoryCounts = Dictionary(grouping: classifications, by: \.category)

            FileHandle.standardOutput.write(Data("  Total .md files:    \(files.count + (scanner.hasMemoryIndex() ? 1 : 0))\n".utf8))
            FileHandle.standardOutput.write(Data("  Migratable files:   \(files.count)\n".utf8))
            FileHandle.standardOutput.write(Data("  MEMORY.md present:  \(scanner.hasMemoryIndex() ? "yes" : "no")\n".utf8))
            FileHandle.standardOutput.write(Data("\n  By scope:\n".utf8))

            for scope in MemoryScope.allCases {
                let count = scopeCounts[scope]?.count ?? 0
                FileHandle.standardOutput.write(Data("    \(scope.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(count)\n".utf8))
            }

            FileHandle.standardOutput.write(Data("\n  By category:\n".utf8))
            for category in MemoryCategory.allCases {
                let count = categoryCounts[category]?.count ?? 0
                if count > 0 {
                    FileHandle.standardOutput.write(Data("    \(category.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \(count)\n".utf8))
                }
            }

        } catch {
            FileHandle.standardOutput.write(Data("  \u{1B}[31mError: \(error)\u{1B}[0m\n".utf8))
        }
    }
}

// MARK: - JSON Serialization Helper

private struct VerificationJSON: Encodable {
    let totalLocalFiles: Int
    let totalDBRecords: Int
    let matchedCount: Int
    let mismatchCount: Int
    let missingInDBCount: Int
    let missingLocalCount: Int
    let skippedCount: Int
    let isComplete: Bool
    let results: [ResultJSON]

    init(report: VerificationReport) {
        self.totalLocalFiles = report.totalLocalFiles
        self.totalDBRecords = report.totalDBRecords
        self.matchedCount = report.matchedCount
        self.mismatchCount = report.mismatchCount
        self.missingInDBCount = report.missingInDBCount
        self.missingLocalCount = report.missingLocalCount
        self.skippedCount = report.skippedCount
        self.isComplete = report.isComplete
        self.results = report.results.map { ResultJSON(result: $0) }
    }

    struct ResultJSON: Encodable {
        let filename: String
        let status: String
        let localHash: String?
        let dbHash: String?
        let message: String

        init(result: VerificationResult) {
            self.filename = result.filename
            self.status = result.status.rawValue
            self.localHash = result.localHash
            self.dbHash = result.dbHash
            self.message = result.message
        }
    }
}
