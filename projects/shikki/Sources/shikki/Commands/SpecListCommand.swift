import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki spec list` — List all specs in features/ with status, progress, and reviewer.
///
/// Supports filtering by lifecycle state: `shikki spec list --status draft`.
/// Output markers: validated, partial/rework, draft, implementing, shipped.
struct SpecListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all specs with lifecycle status, progress, and reviewer"
    )

    @Option(name: .long, help: "Filter by lifecycle status (draft, review, partial, validated, implementing, shipped)")
    var status: String?

    @Option(name: .long, help: "Features directory path (auto-detected if omitted)")
    var featuresDir: String?

    func run() async throws {
        let directory = featuresDir ?? SpecCommandUtilities.findFeaturesDirectory()

        guard FileManager.default.fileExists(atPath: directory) else {
            SpecCommandUtilities.writeStderr("Error: features directory not found: \(directory)\n")
            throw ExitCode.failure
        }

        let service = SpecFrontmatterService()
        var specs = service.scanDirectory(directory)

        // Filter by status if specified
        if let statusFilter = status {
            guard let targetStatus = SpecLifecycleStatus(rawValue: statusFilter) else {
                SpecCommandUtilities.writeStderr("Error: invalid status '\(statusFilter)'. Valid: \(SpecLifecycleStatus.allCases.map(\.rawValue).joined(separator: ", "))\n")
                throw ExitCode.failure
            }
            specs = specs.filter { $0.status == targetStatus }
        }

        if specs.isEmpty {
            if let statusFilter = status {
                SpecCommandUtilities.writeStdout("No specs with status '\(statusFilter)' found.\n")
            } else {
                SpecCommandUtilities.writeStdout("No specs found in \(directory).\n")
            }
            return
        }

        // Sort: validated first, then partial, review, draft, implementing, shipped
        let sortOrder: [SpecLifecycleStatus] = [.validated, .partial, .review, .draft, .implementing, .shipped, .archived, .rejected, .outdated]
        specs.sort { a, b in
            let aIdx = sortOrder.firstIndex(of: a.status) ?? sortOrder.count
            let bIdx = sortOrder.firstIndex(of: b.status) ?? sortOrder.count
            return aIdx < bIdx
        }

        for spec in specs {
            SpecCommandUtilities.writeStdout(SpecFrontmatterService.formatListEntry(spec) + "\n")
        }
    }
}
