import ArgumentParser
import Foundation
import ShikkiKit

/// `shi spec progress` — Show all specs with review progress summary.
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
        let directory = featuresDir ?? SpecCommandUtilities.findFeaturesDirectory()

        guard FileManager.default.fileExists(atPath: directory) else {
            SpecCommandUtilities.writeStderr("Error: features directory not found: \(directory)\n")
            throw ExitCode.failure
        }

        let service = SpecFrontmatterService()
        let specs = service.scanDirectory(directory)

        if specs.isEmpty {
            SpecCommandUtilities.writeStdout("No specs found in \(directory).\n")
            return
        }

        let summary = SpecFrontmatterService.formatProgressSummary(specs)
        SpecCommandUtilities.writeStdout(summary + "\n")

        // Show per-spec detail below summary
        SpecCommandUtilities.writeStdout("\n")

        // Sort by status priority
        let sortOrder: [SpecLifecycleStatus] = [.validated, .partial, .review, .draft, .implementing, .shipped, .archived, .rejected, .outdated]
        let sorted = specs.sorted { a, b in
            let aIdx = sortOrder.firstIndex(of: a.status) ?? sortOrder.count
            let bIdx = sortOrder.firstIndex(of: b.status) ?? sortOrder.count
            return aIdx < bIdx
        }

        for spec in sorted {
            SpecCommandUtilities.writeStdout(SpecFrontmatterService.formatListEntry(spec) + "\n")
        }
    }
}
