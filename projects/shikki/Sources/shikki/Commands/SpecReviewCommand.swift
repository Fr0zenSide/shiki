import ArgumentParser
import Foundation
import ShikkiKit

/// `shi spec review <file>` — Start reviewing a spec, setting status to "review".
///
/// Adds the reviewer to the frontmatter with verdict "reading" and
/// transitions the spec status from draft to review.
struct SpecReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Start reviewing a spec — set status to review"
    )

    @Argument(help: "Spec filename (e.g., shikki-test-runner.md)")
    var file: String

    @Option(name: .long, help: "Reviewer name (default: @Daimyo)")
    var reviewer: String = "@Daimyo"

    @Option(name: .long, help: "Features directory path (auto-detected if omitted)")
    var featuresDir: String?

    func run() async throws {
        let directory = featuresDir ?? SpecCommandUtilities.findFeaturesDirectory()
        let specPath = SpecCommandUtilities.resolveSpecPath(file, in: directory)

        guard FileManager.default.fileExists(atPath: specPath) else {
            SpecCommandUtilities.writeStderr("Error: spec not found: \(specPath)\n")
            throw ExitCode.failure
        }

        let content: String
        do {
            content = try String(contentsOfFile: specPath, encoding: .utf8)
        } catch {
            SpecCommandUtilities.writeStderr("Error: cannot read \(specPath): \(error.localizedDescription)\n")
            throw ExitCode.failure
        }

        let service = SpecFrontmatterService()
        let sectionCount = service.countSections(in: content)

        // Parse existing metadata or create new
        var metadata = service.parse(content: content) ?? SpecMetadata(
            title: SpecCommandUtilities.extractTitle(from: content) ?? file,
            status: .draft
        )
        let filename = (specPath as NSString).lastPathComponent
        metadata.filename = filename

        // Validate transition
        guard metadata.status == .draft || metadata.status == .partial || metadata.status == .review else {
            SpecCommandUtilities.writeStderr("Error: cannot start review — spec is '\(metadata.status.rawValue)' (must be draft, partial, or review)\n")
            throw ExitCode.failure
        }

        // Transition to review
        metadata.status = .review
        metadata.updated = SpecCommandUtilities.todayString()

        // Set progress if not set
        if metadata.progress == nil {
            metadata.progress = "0/\(sectionCount)"
        }

        // Add or update reviewer
        if let idx = metadata.reviewers.firstIndex(where: { $0.who == reviewer }) {
            metadata.reviewers[idx].verdict = .reading
            metadata.reviewers[idx].date = SpecCommandUtilities.todayString()
        } else {
            metadata.reviewers.append(SpecReviewer(
                who: reviewer,
                date: SpecCommandUtilities.todayString(),
                verdict: .reading
            ))
        }

        // Write updated frontmatter
        let updatedContent = service.updateFrontmatter(in: content, with: metadata)
        do {
            try updatedContent.write(toFile: specPath, atomically: true, encoding: .utf8)
        } catch {
            SpecCommandUtilities.writeStderr("Error: cannot write \(specPath): \(error.localizedDescription)\n")
            throw ExitCode.failure
        }

        SpecCommandUtilities.writeStdout("\u{1B}[32mReview started:\u{1B}[0m \(filename) -> review (\(reviewer))\n")
    }
}
