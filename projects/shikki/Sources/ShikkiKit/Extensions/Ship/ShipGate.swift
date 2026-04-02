import Foundation

// MARK: - ShipGate Protocol

/// A single quality gate in the ship pipeline.
public protocol ShipGate: Sendable {
    var name: String { get }
    var index: Int { get }
    func evaluate(context: ShipContext) async throws -> GateResult
}

// MARK: - Gate 1: CleanBranchGate

/// Verifies the working tree is clean -- no uncommitted changes, no untracked files in src/.
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

// MARK: - Gate 2: TestGate

/// Runs the full test suite. Hard gate -- failure aborts the pipeline.
public struct TestGate: ShipGate, Sendable {
    public let name = "Test"
    public let index = 1

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let result = try await context.shell(
            "swift test --package-path \(shellEscape(context.projectRoot.path))"
        )

        if result.exitCode != 0 {
            let output = result.stdout + result.stderr
            return .fail(reason: "Tests failed (exit code \(result.exitCode)):\n\(output.suffix(500))")
        }

        let testCount = parseTestCount(from: result.stdout)
        return .pass(detail: testCount.map { "\($0) tests passed" } ?? "All tests passed")
    }

    private func parseTestCount(from output: String) -> Int? {
        let pattern = /Executed (\d+) tests?/
        if let match = output.firstMatch(of: pattern) {
            return Int(match.1)
        }
        return nil
    }
}

// MARK: - Gate 3: LintGate

/// Runs SwiftLint or swift-format. Soft gate -- warnings do not block, errors fail.
public struct LintGate: ShipGate, Sendable {
    public let name = "Lint"
    public let index = 2

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Check for swiftlint first, fall back to swift-format
        let whichResult = try await context.shell("which swiftlint 2>/dev/null || which swift-format 2>/dev/null")
        let linter = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if linter.isEmpty {
            return .warn(reason: "No linter found (swiftlint or swift-format). Skipped.")
        }

        if linter.hasSuffix("swiftlint") {
            let result = try await context.shell(
                "cd \(shellEscape(context.projectRoot.path)) && swiftlint lint --quiet 2>&1"
            )
            let lines = result.stdout.split(separator: "\n")
            let errors = lines.filter { $0.contains(": error:") }
            let warnings = lines.filter { $0.contains(": warning:") }

            if !errors.isEmpty {
                return .fail(reason: "\(errors.count) lint errors found")
            }
            if !warnings.isEmpty {
                return .warn(reason: "\(warnings.count) lint warnings")
            }
            return .pass(detail: "No lint issues")
        } else {
            // swift-format --lint
            let result = try await context.shell(
                "cd \(shellEscape(context.projectRoot.path)) && swift-format lint -r Sources/ 2>&1"
            )
            if result.exitCode != 0 {
                let lineCount = result.stdout.split(separator: "\n").count
                return .warn(reason: "\(lineCount) formatting issues")
            }
            return .pass(detail: "Formatting OK")
        }
    }
}

// MARK: - Gate 4: BuildGate

/// Verifies the project builds in release mode. Hard gate.
public struct BuildGate: ShipGate, Sendable {
    public let name = "Build"
    public let index = 3

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let result = try await context.shell(
            "swift build -c release --package-path \(shellEscape(context.projectRoot.path)) 2>&1"
        )

        if result.exitCode != 0 {
            let output = result.stdout + result.stderr
            return .fail(reason: "Build failed:\n\(output.suffix(500))")
        }

        return .pass(detail: "Release build succeeded")
    }
}

// MARK: - Gate 5: ChangelogGate

/// Generates changelog from commits since last tag or scoped to an epic branch.
public struct ChangelogGate: ShipGate, Sendable {
    public let name = "Changelog"
    public let index = 4

    /// Optional scope branch for epic range.
    public let scopeBranch: String?

    /// Store generated changelog for downstream consumption.
    public let changelogStore: ChangelogStore

    public init(scopeBranch: String? = nil, changelogStore: ChangelogStore = ChangelogStore()) {
        self.scopeBranch = scopeBranch
        self.changelogStore = changelogStore
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let logRange: String

        if let scope = scopeBranch {
            logRange = "\(shellEscape(scope))..HEAD"
        } else {
            let tagResult = try await context.shell(
                "git describe --tags --abbrev=0 2>/dev/null || echo ''"
            )
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
        await changelogStore.set(changelog)

        let preview = changelog.sections.prefix(3).map { section in
            "\(section.title): \(section.entries.count) entries"
        }.joined(separator: ", ")

        return .pass(detail: "\(commits.count) commits -- \(preview)")
    }
}

/// Thread-safe store for passing changelog between gates.
public actor ChangelogStore {
    private var _changelog: Changelog?

    public init() {}

    public func set(_ changelog: Changelog) {
        _changelog = changelog
    }

    public func get() -> Changelog? {
        _changelog
    }
}

// MARK: - Gate 6: VersionBumpGate

/// Determines next version from conventional commits.
public struct VersionBumpGate: ShipGate, Sendable {
    public let name = "VersionBump"
    public let index = 5
    public let versionOverride: String?

    public init(versionOverride: String? = nil) {
        self.versionOverride = versionOverride
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let tagResult = try await context.shell(
            "git describe --tags --abbrev=0 2>/dev/null || echo '0.0.0'"
        )
        let currentVersion = tagResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")

        if currentVersion.isEmpty {
            return .pass(detail: "No previous version found, starting at 0.1.0")
        }

        let lastTag = tagResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let logResult = try await context.shell(
            "git log \(shellEscape(lastTag))..HEAD --pretty=format:%s 2>/dev/null || git log --pretty=format:%s"
        )
        let commits = logResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        let bumper = VersionBumper()
        let nextVersion = bumper.bump(from: currentVersion, commits: commits, override: versionOverride)

        return .pass(detail: "\(currentVersion) -> \(nextVersion)")
    }
}

// MARK: - Gate 7: TagGate

/// Creates a git tag for the release version.
public struct TagGate: ShipGate, Sendable {
    public let name = "Tag"
    public let index = 6
    public let versionOverride: String?

    public init(versionOverride: String? = nil) {
        self.versionOverride = versionOverride
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Determine version
        let tagResult = try await context.shell(
            "git describe --tags --abbrev=0 2>/dev/null || echo '0.0.0'"
        )
        let currentVersion = tagResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")

        let logResult = try await context.shell(
            "git log \(shellEscape(tagResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))..HEAD --pretty=format:%s 2>/dev/null || git log --pretty=format:%s"
        )
        let commits = logResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        let bumper = VersionBumper()
        let nextVersion = bumper.bump(from: currentVersion, commits: commits, override: versionOverride)
        let tag = "v\(nextVersion)"

        if context.isDryRun {
            return .pass(detail: "[dry-run] Would create tag \(tag)")
        }

        let result = try await context.shell("git tag \(shellEscape(tag))")
        if result.exitCode != 0 {
            return .fail(reason: "Failed to create tag \(tag): \(result.stderr)")
        }

        return .pass(detail: "Tagged \(tag)")
    }
}

// MARK: - Gate 8: PushGate

/// Pushes the current branch and tags to origin.
public struct PushGate: ShipGate, Sendable {
    public let name = "Push"
    public let index = 7

    /// Valid branch name pattern -- alphanumeric, slashes, dots, hyphens, underscores only.
    private nonisolated(unsafe) static let validBranchPattern = /^[a-zA-Z0-9\/_.\-]+$/

    public init() {}

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // Validate branch names
        guard context.branch.wholeMatch(of: Self.validBranchPattern) != nil else {
            return .fail(reason: "Invalid source branch name: \(context.branch)")
        }
        guard context.target.wholeMatch(of: Self.validBranchPattern) != nil else {
            return .fail(reason: "Invalid target branch name: \(context.target)")
        }

        // Reject push to main
        if context.target == "main" || context.target == "master" {
            return .fail(
                reason: "Cannot target '\(context.target)' directly. Use 'develop' or 'release/*' per git flow."
            )
        }

        if context.isDryRun {
            return .pass(detail: "[dry-run] Would push \(context.branch) and tags to origin")
        }

        // Push branch
        let pushResult = try await context.shell(
            "git push -u origin \(shellEscape(context.branch))"
        )
        if pushResult.exitCode != 0 {
            return .fail(reason: "Push failed: \(pushResult.stderr)")
        }

        // Push tags
        let tagResult = try await context.shell("git push origin --tags")
        if tagResult.exitCode != 0 {
            return .warn(reason: "Branch pushed but tag push failed: \(tagResult.stderr)")
        }

        return .pass(detail: "Pushed \(context.branch) with tags")
    }
}
