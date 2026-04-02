import ArgumentParser
import Foundation
import ShikkiKit

/// `shi spec read <file>` — Open a spec at the reviewer's last anchor position.
///
/// Finds the reviewer's anchor from frontmatter and opens with `bat` in a new
/// tmux window at the anchor line. Falls back to beginning if no anchor saved.
struct SpecReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Open a spec at the reviewer's last anchor position (or beginning)"
    )

    @Argument(help: "Spec filename (e.g., shikki-test-runner.md)")
    var file: String

    @Option(name: .long, help: "Reviewer name to look up anchor for (default: @Daimyo)")
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
        let metadata = service.parse(content: content)

        // Find anchor line for the specified reviewer
        var lineNumber = 1
        if let meta = metadata,
           let reviewerEntry = meta.reviewers.first(where: { $0.who == reviewer }),
           let anchor = reviewerEntry.anchor {
            if let anchorLine = service.findAnchorLine(in: content, anchor: anchor) {
                lineNumber = anchorLine
            }
        }

        // Open in tmux window with bat
        let filename = (specPath as NSString).lastPathComponent
        try openInTmux(specPath: specPath, lineNumber: lineNumber, windowName: filename)
    }

    // MARK: - Tmux + Bat

    /// BONUS FIX: Quote specPath for paths with spaces.
    private func openInTmux(specPath: String, lineNumber: Int, windowName: String) throws {
        let quotedPath = "\"\(specPath)\""
        let batArgs = lineNumber > 1
            ? "bat --paging=always --highlight-line \(lineNumber) \(quotedPath)"
            : "bat --paging=always \(quotedPath)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "tmux", "new-window", "-n", windowName, batArgs,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // Fallback: just print the path and line
            SpecCommandUtilities.writeStdout("Open: \(specPath) (line \(lineNumber))\n")
        }
    }
}
