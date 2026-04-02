import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki spec validate <file>` — Set spec status to "validated".
/// `shikki spec validate <file> --partial "#section-8"` — Partial validation with anchor.
///
/// Updates the YAML frontmatter in-place, transitioning the spec's lifecycle status.
struct SpecValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Set spec status to validated (or partial with --partial)"
    )

    @Argument(help: "Spec filename (e.g., shikki-test-runner.md)")
    var file: String

    @Option(name: .long, help: "Partial validation — anchor where review stopped (e.g., \"#section-8\")")
    var partial: String?

    @Option(name: .long, help: "Sections that need rework (comma-separated, e.g., \"8,9\")")
    var rework: String?

    @Option(name: .long, help: "Reviewer name (default: @Daimyo)")
    var reviewer: String = "@Daimyo"

    @Option(name: .long, help: "Review notes")
    var notes: String?

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

        var metadata = service.parse(content: content) ?? SpecMetadata(
            title: SpecCommandUtilities.extractTitle(from: content) ?? file,
            status: .draft
        )
        let filename = (specPath as NSString).lastPathComponent
        metadata.filename = filename

        let isPartial = partial != nil || rework != nil

        if isPartial {
            try applyPartialValidation(&metadata, sectionCount: sectionCount)
        } else {
            try applyFullValidation(&metadata, sectionCount: sectionCount)
        }

        metadata.updated = SpecCommandUtilities.todayString()

        // Write updated frontmatter
        let updatedContent = service.updateFrontmatter(in: content, with: metadata)
        do {
            try updatedContent.write(toFile: specPath, atomically: true, encoding: .utf8)
        } catch {
            SpecCommandUtilities.writeStderr("Error: cannot write \(specPath): \(error.localizedDescription)\n")
            throw ExitCode.failure
        }

        let statusLabel = isPartial ? "partial" : "validated"
        SpecCommandUtilities.writeStdout("\u{1B}[32mSpec \(statusLabel):\u{1B}[0m \(filename) (\(reviewer))\n")
    }

    // MARK: - Validation Logic

    private func applyFullValidation(_ metadata: inout SpecMetadata, sectionCount: Int) throws {
        // Validate transition
        guard metadata.status == .review || metadata.status == .partial || metadata.status == .draft else {
            SpecCommandUtilities.writeStderr("Error: cannot validate — spec is '\(metadata.status.rawValue)' (must be draft, review, or partial)\n")
            throw ExitCode.failure
        }

        metadata.status = .validated
        metadata.progress = "\(sectionCount)/\(sectionCount)"

        // Capture validated-commit from git HEAD
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if let _ = try? process.run() {
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let commit = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let commit, !commit.isEmpty {
                    metadata.validatedCommit = commit
                }
            }
        }

        // Update reviewer
        if let idx = metadata.reviewers.firstIndex(where: { $0.who == reviewer }) {
            metadata.reviewers[idx].verdict = .validated
            metadata.reviewers[idx].date = SpecCommandUtilities.todayString()
            metadata.reviewers[idx].anchor = nil
            metadata.reviewers[idx].sectionsRework = nil
            if sectionCount > 0 {
                metadata.reviewers[idx].sectionsValidated = Array(1...sectionCount)
            }
            if let n = notes {
                metadata.reviewers[idx].notes = n
            }
        } else {
            var rev = SpecReviewer(
                who: reviewer,
                date: SpecCommandUtilities.todayString(),
                verdict: .validated,
                anchor: nil,
                sectionsValidated: sectionCount > 0 ? Array(1...sectionCount) : nil
            )
            if let n = notes {
                rev.notes = n
            }
            metadata.reviewers.append(rev)
        }
    }

    private func applyPartialValidation(_ metadata: inout SpecMetadata, sectionCount: Int) throws {
        guard metadata.status == .review || metadata.status == .partial || metadata.status == .draft else {
            SpecCommandUtilities.writeStderr("Error: cannot partial-validate — spec is '\(metadata.status.rawValue)'\n")
            throw ExitCode.failure
        }

        metadata.status = .partial

        // Parse rework sections
        var reworkSections: [Int] = []
        if let reworkStr = rework {
            reworkSections = reworkStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        // Calculate validated sections: all sections minus rework
        let allSections = sectionCount > 0 ? Set(1...sectionCount) : Set<Int>()
        let validatedSections = allSections.subtracting(Set(reworkSections)).sorted()

        metadata.progress = "\(validatedSections.count)/\(sectionCount)"

        // Update reviewer
        if let idx = metadata.reviewers.firstIndex(where: { $0.who == reviewer }) {
            metadata.reviewers[idx].verdict = .partial
            metadata.reviewers[idx].date = SpecCommandUtilities.todayString()
            metadata.reviewers[idx].anchor = partial
            metadata.reviewers[idx].sectionsValidated = validatedSections
            metadata.reviewers[idx].sectionsRework = reworkSections.isEmpty ? nil : reworkSections
            if let n = notes {
                metadata.reviewers[idx].notes = n
            }
        } else {
            var rev = SpecReviewer(
                who: reviewer,
                date: SpecCommandUtilities.todayString(),
                verdict: .partial,
                anchor: partial,
                sectionsValidated: validatedSections,
                sectionsRework: reworkSections.isEmpty ? nil : reworkSections
            )
            if let n = notes {
                rev.notes = n
            }
            metadata.reviewers.append(rev)
        }
    }
}
