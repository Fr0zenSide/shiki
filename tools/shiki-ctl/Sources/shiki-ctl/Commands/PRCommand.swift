import ArgumentParser
import Foundation
import ShikiCtlKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct PRCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Interactive TUI for reviewing PR documents"
    )

    @Argument(help: "PR number to review (looks for docs/pr<N>-review.md)")
    var number: Int

    @Flag(name: .long, help: "Resume previous review from saved state")
    var resume: Bool = false

    @Flag(name: .long, help: "Quick mode: skip mode selection, go straight to sections")
    var quick: Bool = false

    @Flag(name: .long, help: "Build/rebuild PR cache from git diff")
    var build: Bool = false

    @Option(name: .long, help: "Base branch for diff (default: develop)")
    var base: String = "develop"

    func run() throws {
        let config = PRConfig.load()

        // Build cache if requested
        if build {
            try buildCache(config: config)
            return
        }

        let reviewPath = findReviewFile()
        guard let reviewPath else {
            print("\(ANSI.red)Error:\(ANSI.reset) No review file found for PR #\(number)")
            print("  Expected: docs/pr\(number)-review.md")
            print("  Tip: run \(ANSI.dim)shiki pr \(number) --build\(ANSI.reset) to generate cache first")
            throw ExitCode.failure
        }

        let markdown = try String(contentsOfFile: reviewPath, encoding: .utf8)
        let review = try PRReviewParser.parse(markdown)

        // Load risk map if cache exists
        let riskFiles = loadRiskFiles()

        let statePath = stateFilePath()
        var engine: PRReviewEngine

        if resume, let savedState = PRReviewState.load(from: statePath) {
            engine = PRReviewEngine(review: review, state: savedState, riskFiles: riskFiles, config: config)
            print("\(ANSI.green)Resumed\(ANSI.reset) review from saved state (\(savedState.reviewedCount)/\(review.sections.count) reviewed)")
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            engine = PRReviewEngine(review: review, quickMode: quick, riskFiles: riskFiles, config: config)
        }

        // Non-interactive fallback
        guard isatty(STDIN_FILENO) == 1 else {
            renderNonInteractive(review: review, riskFiles: riskFiles)
            return
        }

        // Interactive TUI loop
        let raw = RawMode()
        defer {
            raw.restore()
            TerminalOutput.showCursor()
        }

        TerminalOutput.hideCursor()

        while true {
            PRReviewRenderer.render(engine: engine)

            if case .done = engine.currentScreen {
                break
            }

            let key = TerminalInput.readKey()
            engine.handle(key: key)
        }

        // Save state on exit
        TerminalOutput.clearScreen()
        TerminalOutput.showCursor()

        do {
            try engine.state.save(to: statePath)
            let counts = engine.state.verdictCounts()
            print("\(ANSI.bold)Review saved.\(ANSI.reset)")
            print("  \(ANSI.green)\(counts.approved) approved\(ANSI.reset), \(ANSI.yellow)\(counts.comment) comments\(ANSI.reset), \(ANSI.red)\(counts.requestChanges) changes requested\(ANSI.reset)")
            print("  State: \(statePath)")
            print("  Resume: \(ANSI.dim)shiki pr \(number) --resume\(ANSI.reset)")
        } catch {
            print("\(ANSI.yellow)Warning:\(ANSI.reset) Could not save review state: \(error)")
        }
    }

    // MARK: - Build Cache

    private func buildCache(config: PRConfig) throws {
        let cacheDir = "docs/pr\(number)-cache"
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        print("\(ANSI.bold)Building PR cache...\(ANSI.reset)")
        print("  Base: \(base)")
        print("  Head: HEAD")

        let meta = try PRCacheBuilder.build(
            prNumber: number,
            base: base,
            head: "HEAD",
            outputDir: cacheDir
        )

        // Generate risk map
        let filesPath = "\(cacheDir)/files.json"
        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        let files = try JSONDecoder().decode([PRFileEntry].self, from: filesData)
        let assessed = PRRiskEngine.assessAll(files: files)

        // Save risk map
        let riskEntries = assessed.map { entry in
            RiskMapEntry(path: entry.file.path, risk: entry.risk, reasons: entry.reasons)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let riskData = try encoder.encode(riskEntries)
        try riskData.write(to: URL(fileURLWithPath: "\(cacheDir)/risk-map.json"))

        // Summary
        let high = assessed.filter { $0.risk == .high }.count
        let medium = assessed.filter { $0.risk == .medium }.count
        let low = assessed.filter { $0.risk == .low }.count
        let skip = assessed.filter { $0.risk == .skip }.count

        print()
        print("  \(ANSI.green)Cache built.\(ANSI.reset)")
        print("  Files: \(meta.fileCount) | +\(meta.totalInsertions)/-\(meta.totalDeletions)")
        print("  Risk: \(ANSI.red)\(high) high\(ANSI.reset), \(ANSI.yellow)\(medium) medium\(ANSI.reset), \(ANSI.green)\(low) low\(ANSI.reset), \(ANSI.dim)\(skip) skip\(ANSI.reset)")
        print("  Cache: \(cacheDir)/")
        print()
        print("  Next: \(ANSI.dim)shiki pr \(number)\(ANSI.reset)")
    }

    // MARK: - Risk Map Loading

    private func loadRiskFiles() -> [AssessedFile] {
        let cacheDir = "docs/pr\(number)-cache"
        let riskPath = "\(cacheDir)/risk-map.json"
        let filesPath = "\(cacheDir)/files.json"

        guard let riskData = FileManager.default.contents(atPath: riskPath),
              let filesData = FileManager.default.contents(atPath: filesPath) else {
            return []
        }

        do {
            let riskEntries = try JSONDecoder().decode([RiskMapEntry].self, from: riskData)
            let files = try JSONDecoder().decode([PRFileEntry].self, from: filesData)

            return riskEntries.compactMap { entry in
                guard let file = files.first(where: { $0.path == entry.path }) else { return nil }
                return AssessedFile(file: file, risk: entry.risk, reasons: entry.reasons)
            }
        } catch {
            return []
        }
    }

    // MARK: - File Resolution

    private func findReviewFile() -> String? {
        let candidates = [
            "docs/pr\(number)-review.md",
            "docs/pr\(number)-code-walkthrough.md",
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        let workspaceRoot = findWorkspaceRoot() ?? "."
        for candidate in candidates {
            let fullPath = "\(workspaceRoot)/\(candidate)"
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    private func stateFilePath() -> String {
        let dir = "docs"
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        return "\(dir)/pr\(number)-review-state.json"
    }

    private func findWorkspaceRoot() -> String? {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            if FileManager.default.fileExists(atPath: "\(dir)/.git") {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    // MARK: - Non-Interactive Fallback

    private func renderNonInteractive(review: PRReview, riskFiles: [AssessedFile]) {
        print(review.title)
        print("Branch: \(review.branch) | Files: \(review.filesChanged) | Tests: \(review.testsInfo)")

        if !riskFiles.isEmpty {
            print()
            print("Risk Triage:")
            for level in [RiskLevel.high, .medium, .low] {
                let files = riskFiles.filter { $0.risk == level }
                guard !files.isEmpty else { continue }
                print("  \(level.rawValue.uppercased()) (\(files.count)):")
                for f in files {
                    print("    \(f.file.path) +\(f.file.insertions)/-\(f.file.deletions)")
                }
            }
        }

        print()
        for section in review.sections {
            print("Section \(section.index): \(section.title)")
            if !section.questions.isEmpty {
                print("  Questions:")
                for (i, q) in section.questions.enumerated() {
                    print("    \(i + 1). \(q.text)")
                }
            }
            print()
        }

        if !review.checklist.isEmpty {
            print("Checklist:")
            for item in review.checklist {
                print("  [ ] \(item)")
            }
        }
    }
}

// MARK: - Risk Map Persistence

struct RiskMapEntry: Codable {
    let path: String
    let risk: RiskLevel
    let reasons: [String]
}
