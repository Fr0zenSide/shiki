import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki spec progress` — Show all specs with review progress summary.
///
/// Displays a dashboard of spec review status with per-status counts
/// and a progress bar showing validation percentage.
struct SpecProgressCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "progress",
        abstract: "Show review progress summary for all specs"
    )

    @Option(name: .long, help: "Features directory path (auto-detected if omitted)")
    var featuresDir: String?

    func run() async throws {
        let directory = featuresDir ?? findFeaturesDirectory()

        guard FileManager.default.fileExists(atPath: directory) else {
            writeStderr("Error: features directory not found: \(directory)\n")
            throw ExitCode.failure
        }

        let service = SpecFrontmatterService()
        let specs = service.scanDirectory(directory)

        if specs.isEmpty {
            writeStdout("No specs found in \(directory).\n")
            return
        }

        let summary = SpecFrontmatterService.formatProgressSummary(specs)
        writeStdout(summary + "\n")

        // Show per-spec detail below summary
        writeStdout("\n")

        // Sort by status priority
        let sortOrder: [SpecLifecycleStatus] = [.validated, .partial, .review, .draft, .implementing, .shipped, .archived, .rejected, .outdated]
        let sorted = specs.sorted { a, b in
            let aIdx = sortOrder.firstIndex(of: a.status) ?? sortOrder.count
            let bIdx = sortOrder.firstIndex(of: b.status) ?? sortOrder.count
            return aIdx < bIdx
        }

        for spec in sorted {
            writeStdout(SpecFrontmatterService.formatListEntry(spec) + "\n")
        }
    }

    // MARK: - Helpers

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
