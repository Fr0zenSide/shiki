import Foundation

// MARK: - Pre-PR Gate Index Convention
//
// Pre-PR gates run BEFORE the standard ship gates (index 0-7).
// They use negative indices to indicate precedence:
//   -4: CtoReviewGate
//   -3: SlopScanGate
//   -2: TestValidationGate
//   -1: LintValidationGate
//
// When --pre-pr is used, the pipeline is:
//   [pre-PR gates] → [ship gates]
// The ShipService runs them all sequentially via the same ShipGate protocol.

// MARK: - Gate: CTO Review

/// Pre-PR Gate 1a/1b equivalent: CTO architecture review.
/// Invokes the ReviewProvider (LLM) to review the diff, then judges pass/fail in Swift.
/// Gate logic is compiled — the LLM is a worker, not the decision-maker.
public struct CtoReviewGate: ShipGate, Sendable {
    public let name = "CtoReview"
    public let index = -4

    private let reviewProvider: any ReviewProvider

    public init(reviewProvider: any ReviewProvider) {
        self.reviewProvider = reviewProvider
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Collect git diff
        let diffResult = try await context.shell("git diff HEAD~1 HEAD")
        let diff = diffResult.stdout

        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .warn(reason: "No diff found. Skipping CTO review.")
        }

        // Attempt to load feature spec (best-effort)
        let branchResult = try await context.shell("git branch --show-current")
        let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let featureSpec = await loadFeatureSpec(branch: branch, context: context)

        // Invoke LLM review
        let review = try await reviewProvider.runCtoReview(diff: diff, featureSpec: featureSpec)

        // Swift judges the result — not the LLM
        let criticalCount = review.findings.filter { $0.severity == .critical }.count

        if criticalCount > 0 {
            let criticals = review.findings
                .filter { $0.severity == .critical }
                .map { "  - \($0.message)" }
                .joined(separator: "\n")
            return .fail(reason: "\(criticalCount) critical finding(s):\n\(criticals)")
        }

        if !review.passed {
            return .fail(reason: "CTO review did not pass: \(review.summary)")
        }

        let warningCount = review.findings.filter { $0.severity == .warning }.count
        if warningCount > 0 {
            return .pass(detail: "CTO review passed with \(warningCount) warning(s)")
        }

        return .pass(detail: "CTO review clean")
    }

    /// Best-effort feature spec loading from features/*.md based on branch name.
    private func loadFeatureSpec(branch: String, context: ShipContext) async -> String? {
        let slug = branch.split(separator: "/").last.map(String.init) ?? branch
        let featuresDir = context.projectRoot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features").path

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: featuresDir) else { return nil }

        // Find first .md file containing the slug
        guard let matchFile = files.first(where: { $0.hasSuffix(".md") && $0.contains(slug) }) else {
            return nil
        }

        let fullPath = "\(featuresDir)/\(matchFile)"
        return try? String(contentsOfFile: fullPath, encoding: .utf8)
    }
}

// MARK: - Gate: Slop Scan

/// Pre-PR Gate 8 equivalent: AI slop scan.
/// Invokes the ReviewProvider (LLM) to scan for AI-generated markers.
/// Pass/fail determined by Swift — zero tolerance for slop markers.
public struct SlopScanGate: ShipGate, Sendable {
    public let name = "SlopScan"
    public let index = -3

    private let reviewProvider: any ReviewProvider

    public init(reviewProvider: any ReviewProvider) {
        self.reviewProvider = reviewProvider
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Collect changed source files
        let diffResult = try await context.shell(
            "git diff --name-only HEAD~1 HEAD -- '*.swift' '*.ts' '*.go' '*.rs'"
        )
        let files = diffResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        if files.isEmpty {
            return .pass(detail: "No source files changed. Slop scan skipped.")
        }

        // Read source contents
        var sources: [String] = []
        let rootPath = context.projectRoot.path
        for file in files {
            // Guard against path traversal
            guard !file.contains("..") else { continue }
            let fullPath = "\(rootPath)/\(file)"
            // Verify the resolved path is within the project root
            let resolved = URL(fileURLWithPath: fullPath).resolvingSymlinksInPath().path
            guard resolved.hasPrefix(rootPath) else { continue }
            let catResult = try await context.shell(
                "cat \(shellEscape(resolved)) 2>/dev/null"
            )
            if !catResult.stdout.isEmpty {
                sources.append("// FILE: \(file)\n\(catResult.stdout)")
            }
        }

        if sources.isEmpty {
            return .pass(detail: "No readable source files. Slop scan skipped.")
        }

        // Invoke LLM slop scan
        let scan = try await reviewProvider.runSlopScan(sources: sources)

        // Swift judges: zero tolerance
        if !scan.clean {
            let markerList = scan.markers.prefix(5).map { marker in
                "  - \(marker.file):\(marker.line) — \(marker.pattern)"
            }.joined(separator: "\n")
            return .fail(reason: "\(scan.markers.count) AI slop marker(s) found:\n\(markerList)")
        }

        return .pass(detail: "Slop scan clean (\(files.count) files scanned)")
    }
}

// MARK: - Gate: Test Validation

/// Pre-PR Gate 3 equivalent: Run tests and verify green.
/// Pure Swift — no LLM. Uses the same test command as TestGate but with
/// additional validation: checks that test count > 0 (prevents empty test suites).
public struct TestValidationGate: ShipGate, Sendable {
    public let name = "TestValidation"
    public let index = -2

    /// Optional custom test command. Defaults to `swift test`.
    private let testCommand: String?

    public init(testCommand: String? = nil) {
        self.testCommand = testCommand
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let command = testCommand ?? "swift test --package-path \(shellEscape(context.projectRoot.path))"
        let result = try await context.shell(command)

        if result.exitCode != 0 {
            let output = (result.stdout + result.stderr).suffix(500)
            return .fail(reason: "Tests failed (exit code \(result.exitCode)):\n\(output)")
        }

        // Parse test count — reject empty test suites
        let testCount = parseTestCount(from: result.stdout)

        if let count = testCount, count == 0 {
            return .fail(reason: "Test suite is empty (0 tests executed). Add tests before shipping.")
        }

        let detail: String
        if let count = testCount {
            detail = "\(count) tests passed"
        } else {
            detail = "All tests passed"
        }

        return .pass(detail: detail)
    }

    private func parseTestCount(from output: String) -> Int? {
        // Swift Testing format: "X tests passed"
        let swiftTestingPattern = /(\d+) tests? (passed|completed)/
        if let match = output.firstMatch(of: swiftTestingPattern) {
            return Int(match.1)
        }
        // XCTest format: "Executed X test(s)"
        let xcTestPattern = /Executed (\d+) tests?/
        if let match = output.firstMatch(of: xcTestPattern) {
            return Int(match.1)
        }
        return nil
    }
}

// MARK: - Gate: Lint Validation

/// Pre-PR Gate: Lint check.
/// Pure Swift — no LLM. Runs the linter and requires zero errors.
/// Warnings are allowed but reported. Stricter than the standard LintGate
/// in that it also checks for TODO/FIXME markers in changed files.
public struct LintValidationGate: ShipGate, Sendable {
    public let name = "LintValidation"
    public let index = -1

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Step 1: Run linter (same as LintGate)
        let whichResult = try await context.shell(
            "which swiftlint 2>/dev/null || which swift-format 2>/dev/null"
        )
        let linter = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        var warnings: [String] = []

        if linter.isEmpty {
            warnings.append("No linter found (swiftlint or swift-format)")
        } else if linter.hasSuffix("swiftlint") {
            let lintResult = try await context.shell(
                "cd \(shellEscape(context.projectRoot.path)) && swiftlint lint --quiet 2>&1"
            )
            let lines = lintResult.stdout.split(separator: "\n")
            let errors = lines.filter { $0.contains(": error:") }
            let lintWarnings = lines.filter { $0.contains(": warning:") }

            if !errors.isEmpty {
                return .fail(reason: "\(errors.count) lint error(s) found")
            }
            if !lintWarnings.isEmpty {
                warnings.append("\(lintWarnings.count) lint warning(s)")
            }
        } else {
            let lintResult = try await context.shell(
                "cd \(shellEscape(context.projectRoot.path)) && swift-format lint -r Sources/ 2>&1"
            )
            if lintResult.exitCode != 0 {
                let lineCount = lintResult.stdout.split(separator: "\n").count
                warnings.append("\(lineCount) formatting issue(s)")
            }
        }

        // Step 2: Check for TODO/FIXME in changed files
        let diffResult = try await context.shell("git diff --name-only HEAD~1 HEAD -- '*.swift'")
        let changedFiles = diffResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        var todoCount = 0
        for file in changedFiles {
            let grepResult = try await context.shell(
                "grep -nc 'TODO\\|FIXME\\|HACK\\|XXX' \(shellEscape(context.projectRoot.path))/\(shellEscape(file)) 2>/dev/null || true"
            )
            if let count = Int(grepResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
               count > 0 {
                todoCount += count
            }
        }

        if todoCount > 0 {
            warnings.append("\(todoCount) TODO/FIXME marker(s) in changed files")
        }

        if warnings.isEmpty {
            return .pass(detail: "Lint validation clean")
        }

        return .warn(reason: warnings.joined(separator: "; "))
    }
}

// MARK: - PrePRStatus

/// Tracks whether pre-PR gates have been run and passed.
/// Used by ShipCommand to enforce the "pre-PR required" rule.
public struct PrePRStatus: Sendable, Codable {
    public let passed: Bool
    public let timestamp: Date
    public let branch: String
    public let gateResults: [PrePRGateRecord]

    public init(passed: Bool, timestamp: Date, branch: String, gateResults: [PrePRGateRecord]) {
        self.passed = passed
        self.timestamp = timestamp
        self.branch = branch
        self.gateResults = gateResults
    }

    /// Check if this status is still valid (same branch, not too old).
    public func isValid(forBranch currentBranch: String, maxAge: TimeInterval = 3600) -> Bool {
        guard branch == currentBranch else { return false }
        guard passed else { return false }
        return Date().timeIntervalSince(timestamp) < maxAge
    }
}

// MARK: - PrePRGateRecord

/// Record of a single pre-PR gate evaluation.
public struct PrePRGateRecord: Sendable, Codable {
    public let gate: String
    public let passed: Bool
    public let detail: String?

    public init(gate: String, passed: Bool, detail: String? = nil) {
        self.gate = gate
        self.passed = passed
        self.detail = detail
    }
}

// MARK: - PrePRStatusStore

/// Persists pre-PR status at ~/.shikki/pre-pr-status.json.
/// Ship gates check this to verify pre-PR has passed.
public struct PrePRStatusStore: Sendable {
    private let path: String

    public init(path: String? = nil) {
        if let path {
            self.path = path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.path = "\(home)/.shikki/pre-pr-status.json"
        }
    }

    /// Save pre-PR status after gate evaluation.
    public func save(_ status: PrePRStatus) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(status)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Load the most recent pre-PR status.
    public func load() throws -> PrePRStatus? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PrePRStatus.self, from: data)
    }

    /// Delete the status file (used after successful ship or branch change).
    public func clear() throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}

// MARK: - PrePRRequiredGate

/// Meta-gate that checks if pre-PR has already passed.
/// Used as the first gate in the standard ship pipeline when --pre-pr is NOT specified.
/// If pre-PR status is missing or invalid, the ship pipeline aborts with a clear message.
public struct PrePRRequiredGate: ShipGate, Sendable {
    public let name = "PrePRRequired"
    public let index = -10

    private let statusStore: PrePRStatusStore

    public init(statusStore: PrePRStatusStore = PrePRStatusStore()) {
        self.statusStore = statusStore
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        guard let status = try statusStore.load() else {
            return .fail(
                reason: "Pre-PR gates have not been run. Run `shi ship --pre-pr` first."
            )
        }

        guard status.isValid(forBranch: context.branch) else {
            if status.branch != context.branch {
                return .fail(
                    reason: "Pre-PR status is for branch '\(status.branch)', "
                        + "but current branch is '\(context.branch)'. "
                        + "Run `shi ship --pre-pr` first."
                )
            }
            if !status.passed {
                return .fail(
                    reason: "Pre-PR gates did not pass. Run `shi ship --pre-pr` to fix quality gates first."
                )
            }
            return .fail(
                reason: "Pre-PR status has expired. Run `shi ship --pre-pr` first."
            )
        }

        let passedGates = status.gateResults.filter(\.passed).count
        let totalGates = status.gateResults.count
        return .pass(detail: "Pre-PR passed (\(passedGates)/\(totalGates) gates)")
    }
}
