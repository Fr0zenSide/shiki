import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki spec-migrate` — Migrate spec files to v2 enhanced frontmatter.
///
/// Scans `features/` for .md files and adds missing v2 metadata fields:
/// progress, updated, tags, flsh block, reviewers, and normalizes status.
struct SpecMigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spec-migrate",
        abstract: "Migrate spec files to v2 enhanced frontmatter"
    )

    @Flag(name: .long, help: "Show what would change without writing files")
    var dryRun: Bool = false

    @Option(name: .long, help: "Migrate a single file instead of all specs")
    var file: String?

    @Option(name: .long, help: "Path to features/ directory (auto-detected if omitted)")
    var directory: String?

    func run() async throws {
        let service = SpecMigrationService()

        if let singleFile = file {
            let path = resolvePath(singleFile)
            guard FileManager.default.fileExists(atPath: path) else {
                writeStderr("\u{1B}[31mError:\u{1B}[0m file not found: \(path)\n")
                throw ExitCode.failure
            }

            let report = try service.migrateFile(at: path, dryRun: dryRun)
            printFileReport(report)
        } else {
            let dir = directory ?? findFeaturesDirectory()
            guard FileManager.default.fileExists(atPath: dir) else {
                writeStderr("\u{1B}[31mError:\u{1B}[0m features directory not found: \(dir)\n")
                throw ExitCode.failure
            }

            let report = try service.migrateAll(directory: dir, dryRun: dryRun)
            printReport(report)
        }
    }

    // MARK: - Output

    private func printFileReport(_ report: SpecMigrationFileReport) {
        if report.alreadyUpToDate {
            writeStdout("\u{1B}[32m✓\u{1B}[0m \(report.filename) — already up-to-date\n")
        } else {
            let mode = dryRun ? " \u{1B}[33m(dry-run)\u{1B}[0m" : ""
            writeStdout("\u{1B}[34m↑\u{1B}[0m \(report.filename)\(mode)\n")
            for field in report.fieldsAdded {
                writeStdout("  + \(field)\n")
            }
            if report.statusNormalized {
                writeStdout("  ~ status normalized\n")
            }
        }
    }

    private func printReport(_ report: SpecMigrationReport) {
        let mode = dryRun ? " \u{1B}[33m(dry-run)\u{1B}[0m" : ""
        writeStdout("\n\u{1B}[1mSpec Migration v2\u{1B}[0m\(mode)\n")
        writeStdout("  Scanned:    \(report.scanned)\n")
        writeStdout("  Updated:    \(report.updated)\n")
        writeStdout("  Up-to-date: \(report.upToDate)\n\n")

        for fileReport in report.files {
            printFileReport(fileReport)
        }
    }

    // MARK: - Helpers

    private func resolvePath(_ input: String) -> String {
        if input.hasPrefix("/") { return input }
        return "\(FileManager.default.currentDirectoryPath)/\(input)"
    }

    private func findFeaturesDirectory() -> String {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let featuresPath = "\(dir)/features"
            if FileManager.default.fileExists(atPath: featuresPath) {
                return featuresPath
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return "\(FileManager.default.currentDirectoryPath)/features"
    }

    private func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
