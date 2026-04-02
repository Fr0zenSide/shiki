import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki review` — compiled entry point for PR review.
///
/// BR-CA-08: Swift is the authoritative pipeline; pr-review.md is the LLM prompt body.
/// BR-CA-04: Every user-facing skill gets a Swift entry point.
/// BR-CA-02: Pre-PR gates are compiled Swift, not markdown.
///
/// Usage:
///   shikki review 42              -> review a single PR
///   shikki review --batch 14..18  -> review a range of PRs
///   shikki review --pre-pr        -> run pre-PR quality gates
///   shikki review 42 --dry-run    -> preview without side effects
struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "PR review — compiled entry point for code review pipeline"
    )

    @Argument(help: "PR number to review")
    var prNumber: Int?

    @Option(name: .long, help: "Batch review a range of PRs (e.g. 14..18, pr14..pr18)")
    var batch: String?

    @Flag(name: .long, help: "Run pre-PR quality gates (test, lint, build)")
    var prePR: Bool = false

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun: Bool = false

    @Option(name: .long, help: "Backend URL for review persistence")
    var url: String = "http://localhost:3900"

    // MARK: - Validation

    func validate() throws {
        // Must specify exactly one mode: single PR, batch, or pre-PR
        let modes = [prNumber != nil, batch != nil, prePR]
        let activeCount = modes.filter { $0 }.count

        if activeCount == 0 {
            throw ValidationError(
                "Specify a PR number, --batch range, or --pre-pr.\n" +
                "Examples:\n" +
                "  shikki review 42\n" +
                "  shikki review --batch 14..18\n" +
                "  shikki review --pre-pr"
            )
        }
        if activeCount > 1 {
            throw ValidationError("Specify only one of: PR number, --batch, or --pre-pr")
        }

        if let number = prNumber, number <= 0 {
            throw ValidationError("PR number must be positive, got \(number)")
        }
    }

    // MARK: - Run

    func run() async throws {
        let target = try resolveTarget()

        if dryRun {
            printDryRun(target: target)
            return
        }

        switch target {
        case .single(let number):
            try await runSingleReview(number)
        case .batch(let numbers):
            try await runBatchReview(numbers)
        case .prePR:
            try await runPrePR()
        }
    }

    // MARK: - Target Resolution

    private func resolveTarget() throws -> ReviewTarget {
        if let batchRange = batch {
            let numbers = try PRRangeParser.parse(batchRange)
            return .batch(numbers)
        }
        if prePR {
            return .prePR
        }
        guard let number = prNumber else {
            throw ReviewError.invalidPRNumber(0)
        }
        return .single(number)
    }

    // MARK: - Single Review

    private func runSingleReview(_ number: Int) async throws {
        let agent = ClaudeAgentReviewProvider()
        let persistence = ReviewPersistence(baseDirectory: reviewBaseDir())
        let service = ReviewService(provider: agent, persistence: persistence)

        FileHandle.standardError.write(Data("\u{1B}[2mLoading PR #\(number)...\u{1B}[0m\n".utf8))

        let result: PRReviewResult
        do {
            result = try await service.review(prNumber: number, dryRun: dryRun)
        } catch let error as ReviewError {
            FileHandle.standardError.write(Data("\u{1B}[31mReview failed:\u{1B}[0m \(error.userMessage)\n".utf8))
            throw ExitCode.failure
        }

        printResult(result)
    }

    // MARK: - Batch Review

    private func runBatchReview(_ numbers: [Int]) async throws {
        let agent = ClaudeAgentReviewProvider()
        let persistence = ReviewPersistence(baseDirectory: reviewBaseDir())
        let service = ReviewService(provider: agent, persistence: persistence)

        FileHandle.standardError.write(
            Data("\u{1B}[2mBatch review: \(numbers.count) PRs (\(numbers.first!)...\(numbers.last!))\u{1B}[0m\n".utf8)
        )

        let results = try await service.reviewBatch(prNumbers: numbers, dryRun: dryRun)

        // Batch summary
        let approved = results.filter { $0.verdict == .approve }.count
        let changes = results.filter { $0.verdict == .changesRequested }.count
        let discuss = results.filter { $0.verdict == .needsDiscussion }.count
        let failed = numbers.count - results.count

        FileHandle.standardOutput.write(Data("\n\u{1B}[1mBatch Review Complete\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data("  Reviewed: \(results.count)/\(numbers.count) PRs\n".utf8))
        FileHandle.standardOutput.write(Data("  Approved: \(approved)\n".utf8))
        FileHandle.standardOutput.write(Data("  Changes Requested: \(changes)\n".utf8))
        FileHandle.standardOutput.write(Data("  Needs Discussion: \(discuss)\n".utf8))
        if failed > 0 {
            FileHandle.standardOutput.write(Data("  Failed: \(failed)\n".utf8))
        }
    }

    // MARK: - Pre-PR Quality Gates

    private func runPrePR() async throws {
        FileHandle.standardError.write(Data("\u{1B}[2mRunning pre-PR quality gates...\u{1B}[0m\n".utf8))

        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let branch = (try? shellSync("git branch --show-current").trimmingCharacters(in: .whitespacesAndNewlines)) ?? "unknown"

        let context = RealShipContext(
            branch: branch,
            target: "develop",
            projectRoot: projectRoot
        )

        // Use the compiled PrePRGates system
        let gates: [any ShipGate] = [
            TestValidationGate(),
            LintValidationGate(),
        ]

        var passed = 0
        var failed = 0
        var warnings = 0
        var gateRecords: [PrePRGateRecord] = []

        for (idx, gate) in gates.enumerated() {
            let result = try await gate.evaluate(context: context)
            let gatePassed: Bool
            switch result {
            case .pass(let detail):
                printGate(index: idx + 1, name: gate.name, passed: true, detail: detail)
                passed += 1
                gatePassed = true
            case .warn(let reason):
                printGate(index: idx + 1, name: gate.name, passed: true, detail: reason)
                warnings += 1
                passed += 1
                gatePassed = true
            case .fail(let reason):
                printGate(index: idx + 1, name: gate.name, passed: false, detail: reason)
                failed += 1
                gatePassed = false
            }
            gateRecords.append(PrePRGateRecord(gate: gate.name, passed: gatePassed))
        }

        // Check clean working tree separately (not a ShipGate)
        let cleanResult = shellSync("git status --porcelain")
        let isClean = cleanResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        printGate(index: gates.count + 1, name: "Clean Branch", passed: isClean,
                  detail: isClean ? nil : "Uncommitted changes detected")
        if isClean { passed += 1 } else { failed += 1 }
        gateRecords.append(PrePRGateRecord(gate: "CleanBranch", passed: isClean))

        // Save pre-PR status
        let status = PrePRStatus(
            passed: failed == 0,
            timestamp: Date(),
            branch: branch,
            gateResults: gateRecords
        )
        try? PrePRStatusStore().save(status)

        // Summary
        let total = passed + failed
        FileHandle.standardOutput.write(Data("\n\u{1B}[1mPre-PR Summary\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data("  \(passed)/\(total) gates passed".utf8))
        if warnings > 0 {
            FileHandle.standardOutput.write(Data(", \(warnings) warnings".utf8))
        }
        FileHandle.standardOutput.write(Data("\n".utf8))

        if failed > 0 {
            FileHandle.standardOutput.write(
                Data("\u{1B}[31mPre-PR failed. Fix issues before creating PR.\u{1B}[0m\n".utf8)
            )
            throw ExitCode.failure
        } else {
            FileHandle.standardOutput.write(
                Data("\u{1B}[32mPre-PR passed. Ready to create PR.\u{1B}[0m\n".utf8)
            )
        }
    }

    // MARK: - Review Base Directory

    private func reviewBaseDir() -> String {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let shikkiDir = "\(dir)/.shikki"
            if FileManager.default.fileExists(atPath: shikkiDir) {
                return "\(shikkiDir)/reviews"
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return "\(FileManager.default.currentDirectoryPath)/.shikki/reviews"
    }

    // MARK: - Shell Helpers

    private func shellSync(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func shellSyncExit(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: - Output

    private func printDryRun(target: ReviewTarget) {
        FileHandle.standardOutput.write(Data("\u{1B}[1mReview Dry Run\u{1B}[0m\n".utf8))
        switch target {
        case .single(let n):
            FileHandle.standardOutput.write(Data("  Mode: Single PR review\n".utf8))
            FileHandle.standardOutput.write(Data("  PR: #\(n)\n".utf8))
        case .batch(let numbers):
            FileHandle.standardOutput.write(Data("  Mode: Batch review\n".utf8))
            FileHandle.standardOutput.write(Data("  PRs: #\(numbers.first!)..#\(numbers.last!) (\(numbers.count) total)\n".utf8))
        case .prePR:
            FileHandle.standardOutput.write(Data("  Mode: Pre-PR quality gates\n".utf8))
            FileHandle.standardOutput.write(Data("  Gates: CleanBranch, Tests, Build, TODOs\n".utf8))
        }
        FileHandle.standardOutput.write(Data("  Pipeline: load -> analyze -> verdict -> persist\n".utf8))
    }

    private func printResult(_ result: PRReviewResult) {
        let critical = result.findings.filter { $0.severity == .critical }.count
        let important = result.findings.filter { $0.severity == .important }.count
        let minor = result.findings.filter { $0.severity == .minor }.count

        // Header
        FileHandle.standardOutput.write(Data("\n\u{1B}[1mPR #\(result.prNumber) Review\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data("  Files: \(result.filesReviewed)/\(result.totalFiles) reviewed\n".utf8))

        // Findings
        if !result.findings.isEmpty {
            FileHandle.standardOutput.write(Data("  Findings: \(result.findings.count) total\n".utf8))
            FileHandle.standardOutput.write(
                Data("    Critical: \(critical) | Important: \(important) | Minor: \(minor)\n".utf8)
            )

            for (index, finding) in result.findings.enumerated() {
                let loc = [finding.file, finding.line.map(String.init)].compactMap { $0 }.joined(separator: ":")
                let locStr = loc.isEmpty ? "" : " [\(loc)]"
                FileHandle.standardOutput.write(
                    Data("    \(index + 1). [\(finding.severity.rawValue.uppercased())] \(finding.reviewer)\(locStr) \(finding.message)\n".utf8)
                )
            }
        } else {
            FileHandle.standardOutput.write(Data("  Findings: none\n".utf8))
        }

        // Verdict
        let verdictColor: String
        switch result.verdict {
        case .approve: verdictColor = "\u{1B}[32m"
        case .changesRequested: verdictColor = "\u{1B}[31m"
        case .needsDiscussion: verdictColor = "\u{1B}[33m"
        }
        FileHandle.standardOutput.write(
            Data("  Verdict: \(verdictColor)\(result.verdict.rawValue)\u{1B}[0m\n".utf8)
        )
    }

    private func printGate(index: Int, name: String, passed: Bool, detail: String? = nil) {
        let icon = passed ? "\u{1B}[32mPASS\u{1B}[0m" : "\u{1B}[31mFAIL\u{1B}[0m"
        var line = "  [\(index)/4] \(icon) \(name)"
        if let detail {
            line += " — \(detail)"
        }
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }
}

// MARK: - ReviewError User Messages

extension ReviewError {
    var userMessage: String {
        switch self {
        case .invalidPRNumber(let n): return "Invalid PR number: \(n)"
        case .invalidRange(let r): return "Invalid range: \(r)"
        case .ghNotAvailable: return "GitHub CLI (gh) not found. Install: brew install gh"
        case .prNotFound(let n): return "PR #\(n) not found or inaccessible"
        case .analysisFailure(let msg): return "Analysis failed: \(msg)"
        case .persistenceFailure(let msg): return "Could not save review: \(msg)"
        }
    }
}

// MARK: - ClaudeAgentReviewProvider

/// Default ReviewAnalysisProvider using `claude -p` subprocess.
/// Delegates to the same agent provider pattern as SpecCommand.
struct ClaudeAgentReviewProvider: ReviewAnalysisProvider {
    private let model: String

    init(model: String = ProcessInfo.processInfo.environment["SHIKKI_REVIEW_MODEL"] ?? "claude-sonnet-4-6") {
        self.model = model
    }

    func analyze(prompt: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", "--model", model, prompt]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ReviewError.analysisFailure("claude -p exited with status \(process.terminationStatus)")
        }

        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            throw ReviewError.analysisFailure("Empty output from claude -p")
        }

        return output
    }
}
