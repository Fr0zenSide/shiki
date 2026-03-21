import Foundation

// MARK: - ShipGate Protocol

/// A single quality gate in the ship pipeline.
public protocol ShipGate: Sendable {
    var name: String { get }
    var index: Int { get }
    func evaluate(context: ShipContext) async throws -> GateResult
}

// MARK: - Gate 1: CleanBranchGate (BR-01)

/// Verifies the working tree is clean — no uncommitted changes, no untracked files in src/.
public struct CleanBranchGate: ShipGate, Sendable {
    public let name = "CleanBranch"
    public let index = 0

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let result = try await context.shell("git status --porcelain")
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if !output.isEmpty {
            return .fail(reason: "Working tree is not clean. Uncommitted changes:\n\(output)")
        }

        return .pass(detail: "Working tree clean")
    }
}

// MARK: - Gate 2: TestGate (BR-02)

/// Runs the full test suite. Hard gate — failure aborts the pipeline.
public struct TestGate: ShipGate, Sendable {
    public let name = "Test"
    public let index = 1

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let result = try await context.shell("swift test --package-path \(shellEscape(context.projectRoot.path))")

        if result.exitCode != 0 {
            let output = result.stdout + result.stderr
            return .fail(reason: "Tests failed (exit code \(result.exitCode)):\n\(output.suffix(500))")
        }

        // Try to parse test count from output
        let testCount = parseTestCount(from: result.stdout)
        return .pass(detail: testCount.map { "\($0) tests passed" } ?? "All tests passed")
    }

    private func parseTestCount(from output: String) -> Int? {
        // Match "Executed N tests"
        let pattern = /Executed (\d+) tests?/
        if let match = output.firstMatch(of: pattern) {
            return Int(match.1)
        }
        return nil
    }
}

// MARK: - Gate 3: CoverageGate (BR-03)

/// Soft gate. Below threshold = warn. Drop >5% from previous = warn with risk.
public struct CoverageGate: ShipGate, Sendable {
    public let name = "Coverage"
    public let index = 2
    public let threshold: Double
    public let currentCoverage: Double?
    public let previousCoverage: Double?

    public init(threshold: Double = 80.0, currentCoverage: Double? = nil, previousCoverage: Double? = nil) {
        self.threshold = threshold
        self.currentCoverage = currentCoverage
        self.previousCoverage = previousCoverage
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Use injected coverage if available, otherwise try to parse
        let coverage: Double
        if let injected = currentCoverage {
            coverage = injected
        } else {
            // Try to get coverage from swift test output (best effort)
            let result = try await context.shell("swift test --enable-code-coverage --package-path \(shellEscape(context.projectRoot.path)) 2>&1 | tail -1")
            if let parsed = Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
                coverage = parsed
            } else {
                // Coverage unavailable — pass with note
                return .pass(detail: "Coverage data unavailable — skipped")
            }
        }

        // Check for >5% drop from previous
        if let previous = previousCoverage, previous - coverage > 5.0 {
            return .warn(reason: "Coverage dropped from \(String(format: "%.1f", previous))% to \(String(format: "%.1f", coverage))% (risk: >5% decrease)")
        }

        // Check against threshold
        if coverage < threshold {
            return .warn(reason: "Coverage \(String(format: "%.1f", coverage))% is below threshold \(String(format: "%.1f", threshold))%")
        }

        return .pass(detail: "Coverage \(String(format: "%.1f", coverage))%")
    }
}

// MARK: - Gate 4: RiskGate (BR-04)

/// Lightweight diff risk scorer. Informational only — always passes.
public struct RiskGate: ShipGate, Sendable {
    public let name = "Risk"
    public let index = 3

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let result = try await context.shell("git diff --stat \(shellEscape(context.target))...HEAD")
        let output = result.stdout

        // Parse summary line: "N files changed, N insertions(+), N deletions(-)"
        let files = parseStat(output, pattern: /(\d+) files? changed/)
        let insertions = parseStat(output, pattern: /(\d+) insertions?\(\+\)/)
        let deletions = parseStat(output, pattern: /(\d+) deletions?\(-\)/)

        let totalChurn = insertions + deletions
        let score: String
        if totalChurn < 100 {
            score = "low"
        } else if totalChurn < 500 {
            score = "medium"
        } else {
            score = "high"
        }

        return .pass(detail: "Risk: \(score) — \(files) files, +\(insertions)/-\(deletions)")
    }

    private func parseStat(_ text: String, pattern: some RegexComponent<(Substring, Substring)>) -> Int {
        if let match = text.firstMatch(of: pattern) {
            return Int(match.1) ?? 0
        }
        return 0
    }
}

// MARK: - Gate 5: ChangelogGate (BR-05)

/// Generates changelog from commits since last tag or scoped to an epic branch.
public struct ChangelogGate: ShipGate, Sendable {
    public let name = "Changelog"
    public let index = 4

    /// Optional scope branch. When set, changelog covers `scopeBranch..HEAD` (epic range).
    /// When nil, falls back to `lastTag..HEAD` (default behavior).
    public let scopeBranch: String?

    public init(scopeBranch: String? = nil) {
        self.scopeBranch = scopeBranch
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let logRange: String

        if let scope = scopeBranch {
            // Epic scoping: commits since the epic branch point
            logRange = "\(shellEscape(scope))..HEAD"
        } else {
            // Default: commits since last tag
            let tagResult = try await context.shell("git describe --tags --abbrev=0 2>/dev/null || echo ''")
            let lastTag = tagResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            logRange = lastTag.isEmpty ? "HEAD" : "\(shellEscape(lastTag))..HEAD"
        }

        let logResult = try await context.shell("git log \(logRange) --pretty=format:%s")
        let commits = logResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        if commits.isEmpty {
            return .warn(reason: "No commits found since last tag")
        }

        let generator = ChangelogGenerator()
        let changelog = generator.generate(from: commits)
        let preview = changelog.sections.prefix(3).map { section in
            "\(section.title): \(section.entries.count) entries"
        }.joined(separator: ", ")

        return .pass(detail: "\(commits.count) commits — \(preview)")
    }
}

// MARK: - Gate 6: VersionBumpGate (BR-06)

/// Determines next version from conventional commits.
public struct VersionBumpGate: ShipGate, Sendable {
    public let name = "VersionBump"
    public let index = 5
    public let versionOverride: String?

    public init(versionOverride: String? = nil) {
        self.versionOverride = versionOverride
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Get current version from last tag
        let tagResult = try await context.shell("git describe --tags --abbrev=0 2>/dev/null || echo '0.0.0'")
        let currentVersion = tagResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")

        if currentVersion.isEmpty {
            return .pass(detail: "No previous version found, starting at 0.1.0")
        }

        // Get commits since last tag
        let lastTag = tagResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let logResult = try await context.shell("git log \(shellEscape(lastTag))..HEAD --pretty=format:%s 2>/dev/null || git log --pretty=format:%s")
        let commits = logResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        let bumper = VersionBumper()
        let nextVersion = bumper.bump(from: currentVersion, commits: commits, override: versionOverride)

        return .pass(detail: "\(currentVersion) -> \(nextVersion)")
    }
}

// MARK: - Gate 7: CommitGate (BR-07)

/// Optional squash commit. In dry-run: no-op.
public struct CommitGate: ShipGate, Sendable {
    public let name = "Commit"
    public let index = 6
    public let squash: Bool

    public init(squash: Bool = false) {
        self.squash = squash
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Guard: never squash on the target branch itself (would rewrite shared history)
        let branchResult = try await context.shell("git rev-parse --abbrev-ref HEAD")
        let currentBranch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentBranch != context.target else {
            return .fail(reason: "Cannot squash on target branch '\(context.target)'. Must be on a feature branch.")
        }

        if context.isDryRun {
            let mode = squash ? "squash" : "preserve history"
            return .pass(detail: "[dry-run] Would commit with mode: \(mode)")
        }

        if squash {
            // Squash all commits on current branch into one
            let baseResult = try await context.shell("git merge-base \(shellEscape(context.target)) HEAD")
            let base = baseResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty {
                _ = try await context.shell("git reset --soft \(shellEscape(base))")
                _ = try await context.shell("git commit -m 'squash: prepare for ship'")
            }
            return .pass(detail: "Squashed commits")
        }

        return .pass(detail: "Preserving commit history")
    }
}

// MARK: - Gate 8: PRGate (BR-08, BR-11)

/// Creates a PR targeting the specified branch. Rejects main.
public struct PRGate: ShipGate, Sendable {
    public let name = "PR"
    public let index = 7

    public init() {}

    /// Valid branch name pattern — alphanumeric, slashes, dots, hyphens, underscores only.
    private nonisolated(unsafe) static let validBranchPattern = /^[a-zA-Z0-9\/_.\-]+$/

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Validate branch names contain no shell metacharacters
        guard context.target.wholeMatch(of: Self.validBranchPattern) != nil else {
            return .fail(reason: "Invalid target branch name: \(context.target)")
        }
        guard context.branch.wholeMatch(of: Self.validBranchPattern) != nil else {
            return .fail(reason: "Invalid source branch name: \(context.branch)")
        }

        // BR-11: Reject main target
        if context.target == "main" || context.target == "master" {
            return .fail(reason: "Cannot target '\(context.target)' directly. Use 'develop' or 'release/*' per git flow.")
        }

        // Validate target is develop, release/*, epic/*, or story/*
        if context.target != "develop"
            && !context.target.hasPrefix("release/")
            && !context.target.hasPrefix("epic/")
            && !context.target.hasPrefix("story/") {
            return .fail(reason: "Target must be 'develop', 'release/*', 'epic/*', or 'story/*'. Got: '\(context.target)'")
        }

        if context.isDryRun {
            return .pass(detail: "[dry-run] Would create PR: \(context.branch) -> \(context.target)")
        }

        // Create PR via gh CLI
        let result = try await context.shell("gh pr create --base \(shellEscape(context.target)) --fill --head \(shellEscape(context.branch))")

        if result.exitCode != 0 {
            let error = result.stderr.isEmpty ? result.stdout : result.stderr
            return .fail(reason: "gh pr create failed: \(error)")
        }

        let prURL = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .pass(detail: "PR created: \(prURL)")
    }
}
