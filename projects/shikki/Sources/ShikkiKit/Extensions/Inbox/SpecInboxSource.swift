import Foundation

/// Scans `features/` directory for spec markdown files with YAML frontmatter
/// and surfaces those in `draft` or `review` status as inbox items.
/// Priority weight: review > draft.
public struct SpecInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .spec }

    private let shellRunner: ShellRunner
    private let parser: SpecFrontmatterParser

    public init(shellRunner: ShellRunner = DefaultShellRunner(), parser: SpecFrontmatterParser = SpecFrontmatterParser()) {
        self.shellRunner = shellRunner
        self.parser = parser
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.spec) { return [] }

        do {
            // Locate features/ directory relative to git root
            let rootOutput = try shellRunner.run(
                "/usr/bin/env",
                arguments: ["git", "rev-parse", "--show-toplevel"]
            )
            let gitRoot = rootOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let featuresDir = "\(gitRoot)/features"

            let fm = FileManager.default
            guard fm.fileExists(atPath: featuresDir) else { return [] }

            guard let files = try? fm.contentsOfDirectory(atPath: featuresDir) else { return [] }
            let mdFiles = files.filter { $0.hasSuffix(".md") }

            var items: [InboxItem] = []

            for file in mdFiles {
                let filePath = "\(featuresDir)/\(file)"
                guard let metadata = try? parser.parse(filePath: filePath) else { continue }

                // Only surface draft and review specs
                guard metadata.status == .draft || metadata.status == .review else { continue }

                let slug = file.replacingOccurrences(of: ".md", with: "")

                // Review specs are more urgent than drafts
                let priorityWeight: Int
                switch metadata.status {
                case .review: priorityWeight = 25
                case .draft: priorityWeight = 10
                default: priorityWeight = 5
                }

                // Use file modification date for age
                let attrs = try? fm.attributesOfItem(atPath: filePath)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                let age = max(0, Date().timeIntervalSince(modDate))

                let urgency = UrgencyCalculator.score(
                    age: age,
                    priorityWeight: priorityWeight,
                    isBlocking: false
                )

                items.append(InboxItem(
                    id: "spec:\(slug)",
                    type: .spec,
                    title: metadata.title,
                    subtitle: "Status: \(metadata.status.rawValue)",
                    age: age,
                    companySlug: metadata.project,
                    urgencyScore: urgency,
                    metadata: [
                        "status": metadata.status.rawValue,
                        "priority": metadata.priority ?? "",
                        "project": metadata.project ?? "",
                        "file": file,
                    ]
                ))
            }

            return items
        } catch {
            // Graceful fallback — shell command failure (e.g. not in a git repo)
            return []
        }
    }
}
