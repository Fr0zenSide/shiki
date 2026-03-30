import Foundation

/// Errors during merge operations.
public enum MergeError: Error, LocalizedError, Sendable {
    case rebaseFailed(String, String)
    case conflictsDetected(String, [String])
    case testsFailed(String, [TestFailure])
    case noResultsToMerge

    public var errorDescription: String? {
        switch self {
        case .rebaseFailed(let branch, let detail):
            return "Rebase failed for '\(branch)': \(detail)"
        case .conflictsDetected(let branch, let files):
            return "Conflicts in '\(branch)': \(files.joined(separator: ", "))"
        case .testsFailed(let scope, let failures):
            return "Tests failed in '\(scope)': \(failures.count) failures"
        case .noResultsToMerge:
            return "No agent results to merge"
        }
    }
}

/// A test failure with classification.
public struct TestFailure: Sendable, Codable {
    public let testName: String
    public let file: String
    public let line: Int?
    public let message: String
    /// Module/target the failure belongs to.
    public let module: String
    /// Failure scope for grouping.
    public let scope: FailureScope

    public init(
        testName: String,
        file: String = "",
        line: Int? = nil,
        message: String = "",
        module: String = "",
        scope: FailureScope = .unit
    ) {
        self.testName = testName
        self.file = file
        self.line = line
        self.message = message
        self.module = module
        self.scope = scope
    }
}

/// Classification of test failures.
public enum FailureScope: String, Sendable, Codable {
    /// Single test method failure.
    case unit
    /// Multiple tests in same file/suite.
    case suite
    /// Cross-module / architectural issue.
    case architectural
}

/// Result of a merge attempt.
public struct MergeResult: Sendable {
    public let mergedBranches: [String]
    public let conflicts: [String]
    public let testsPassed: Bool
    public let testFailures: [TestFailure]
    public let commitHash: String?

    public var isClean: Bool {
        conflicts.isEmpty && testsPassed
    }

    public init(
        mergedBranches: [String] = [],
        conflicts: [String] = [],
        testsPassed: Bool = true,
        testFailures: [TestFailure] = [],
        commitHash: String? = nil
    ) {
        self.mergedBranches = mergedBranches
        self.conflicts = conflicts
        self.testsPassed = testsPassed
        self.testFailures = testFailures
        self.commitHash = commitHash
    }
}

/// Result of a scoped test run.
public struct TestRunResult: Sendable {
    public let passed: Bool
    public let totalTests: Int
    public let failedTests: Int
    public let failures: [TestFailure]
    public let durationSeconds: Int

    public init(
        passed: Bool = true,
        totalTests: Int = 0,
        failedTests: Int = 0,
        failures: [TestFailure] = [],
        durationSeconds: Int = 0
    ) {
        self.passed = passed
        self.totalTests = totalTests
        self.failedTests = failedTests
        self.failures = failures
        self.durationSeconds = durationSeconds
    }
}

/// Merges agent worktree results back into the base branch.
///
/// Strategy: rebase each worktree in priority order (protocols first → impls → tests).
/// After each rebase, run scoped tests. Classify failures by module.
public struct MergeEngine: Sendable {

    private let projectRoot: String

    public init(projectRoot: String) {
        self.projectRoot = projectRoot
    }

    /// Merge dispatch results back into the base branch.
    ///
    /// - Parameters:
    ///   - dispatchResult: Results from ``DispatchEngine``.
    ///   - worktrees: The worktrees that were created.
    ///   - plan: The work plan (for priority ordering).
    ///   - testScope: Test filter to run (empty = all tests).
    ///   - baseBranch: The branch to rebase onto.
    /// - Returns: The merge result.
    public func merge(
        dispatchResult: DispatchResult,
        worktrees: [Worktree],
        plan: WorkPlan,
        testScope: [String] = [],
        baseBranch: String = "HEAD"
    ) async throws -> MergeResult {
        let successfulResults = dispatchResult.agentResults.filter { $0.status == .completed }
        guard !successfulResults.isEmpty else {
            throw MergeError.noResultsToMerge
        }

        // Sort by priority (protocol units first)
        let sortedUnits = plan.units
            .filter { unit in successfulResults.contains { $0.unitId == unit.id } }
            .sorted { $0.priority < $1.priority }

        let worktreeMap = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.unitId, $0) })

        var mergedBranches: [String] = []
        var allConflicts: [String] = []

        // Rebase each branch in priority order
        for unit in sortedUnits {
            guard let worktree = worktreeMap[unit.id] else { continue }

            let rebaseResult = try await rebase(worktree: worktree, onto: baseBranch)

            if rebaseResult.hasConflicts {
                allConflicts.append(contentsOf: rebaseResult.conflictFiles)
                // Abort this rebase and continue with next
                _ = try? await runGit(["rebase", "--abort"])
            } else {
                mergedBranches.append(worktree.branch)
            }
        }

        // Run scoped tests
        let testResult = try await runTests(scope: testScope)

        // Get current commit
        let hashResult = try await runGit(["rev-parse", "HEAD"])
        let commitHash = hashResult.exitCode == 0 ? hashResult.stdout : nil

        return MergeResult(
            mergedBranches: mergedBranches,
            conflicts: allConflicts,
            testsPassed: testResult.passed,
            testFailures: testResult.failures,
            commitHash: commitHash
        )
    }

    /// Run tests with optional scope filter.
    public func runTests(scope: [String] = []) async throws -> TestRunResult {
        var args = ["test"]
        if !scope.isEmpty {
            args.append("--filter")
            args.append(scope.joined(separator: "|"))
        }

        let result = try await runSwift(args)
        let failures = parseTestFailures(result.stderr + "\n" + result.stdout)
        let (total, failed) = parseTestCounts(result.stdout + "\n" + result.stderr)

        return TestRunResult(
            passed: result.exitCode == 0,
            totalTests: total,
            failedTests: failed,
            failures: failures,
            durationSeconds: 0
        )
    }

    /// Classify failures by severity.
    ///
    /// From spec:
    /// - <5 failures → single agent fixes all (.unit)
    /// - 5-20 → split by module (.suite)
    /// - >20 → architectural issue (.architectural)
    public func classifyFailures(_ failures: [TestFailure]) -> [TestFailure] {
        let scope: FailureScope
        if failures.count > 20 {
            scope = .architectural
        } else if failures.count >= 5 {
            scope = .suite
        } else {
            scope = .unit
        }

        return failures.map { failure in
            TestFailure(
                testName: failure.testName,
                file: failure.file,
                line: failure.line,
                message: failure.message,
                module: failure.module,
                scope: scope
            )
        }
    }

    /// Group failures by module for parallel fix dispatch.
    public func groupByModule(_ failures: [TestFailure]) -> [String: [TestFailure]] {
        Dictionary(grouping: failures) { $0.module.isEmpty ? "unknown" : $0.module }
    }

    // MARK: - Rebase

    struct RebaseResult: Sendable {
        let hasConflicts: Bool
        let conflictFiles: [String]
    }

    func rebase(worktree: Worktree, onto baseBranch: String) async throws -> RebaseResult {
        // Checkout the worktree branch
        let checkoutResult = try await runGit(["checkout", worktree.branch])
        guard checkoutResult.exitCode == 0 else {
            throw MergeError.rebaseFailed(worktree.branch, checkoutResult.stderr)
        }

        // Rebase onto base
        let rebaseResult = try await runGit(["rebase", baseBranch])

        if rebaseResult.exitCode != 0 {
            // Check for conflicts
            let statusResult = try await runGit(["diff", "--name-only", "--diff-filter=U"])
            let conflictFiles = statusResult.stdout
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }

            if !conflictFiles.isEmpty {
                return RebaseResult(hasConflicts: true, conflictFiles: conflictFiles)
            }

            throw MergeError.rebaseFailed(worktree.branch, rebaseResult.stderr)
        }

        return RebaseResult(hasConflicts: false, conflictFiles: [])
    }

    // MARK: - Test Output Parsing

    func parseTestFailures(_ output: String) -> [TestFailure] {
        var failures: [TestFailure] = []

        // Match swift-testing failures: ✘ Test "name" recorded an issue at File.swift:123
        let stPattern = #"Test "([^"]+)" (?:recorded an issue|failed) at (\S+):(\d+)(?::.*)?(?:\s*:\s*(.+))?"#
        if let regex = try? NSRegularExpression(pattern: stPattern) {
            let range = NSRange(output.startIndex..., in: output)
            regex.enumerateMatches(in: output, range: range) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 1), in: output),
                      let fileRange = Range(match.range(at: 2), in: output) else { return }

                let testName = String(output[nameRange])
                let file = String(output[fileRange])
                let line = match.range(at: 3).location != NSNotFound
                    ? Range(match.range(at: 3), in: output).flatMap { Int(output[$0]) }
                    : nil
                let message = match.range(at: 4).location != NSNotFound
                    ? Range(match.range(at: 4), in: output).map { String(output[$0]) } ?? ""
                    : ""

                let module = inferModuleFromFile(file)

                failures.append(TestFailure(
                    testName: testName,
                    file: file,
                    line: line,
                    message: message,
                    module: module
                ))
            }
        }

        // Match XCTest failures: path/File.swift:123: error: -[Module.TestClass testMethod] : message
        let xcPattern = #"(\S+\.swift):(\d+): error: -\[(\S+)\.(\w+) (\w+)\] : (.+)"#
        if let regex = try? NSRegularExpression(pattern: xcPattern) {
            let range = NSRange(output.startIndex..., in: output)
            regex.enumerateMatches(in: output, range: range) { match, _, _ in
                guard let match,
                      let fileRange = Range(match.range(at: 1), in: output),
                      let testRange = Range(match.range(at: 5), in: output) else { return }

                let file = String(output[fileRange])
                let line = Range(match.range(at: 2), in: output).flatMap { Int(output[$0]) }
                let testName = String(output[testRange])
                let message = match.range(at: 6).location != NSNotFound
                    ? Range(match.range(at: 6), in: output).map { String(output[$0]) } ?? ""
                    : ""
                let module = match.range(at: 3).location != NSNotFound
                    ? Range(match.range(at: 3), in: output).map { String(output[$0]) } ?? ""
                    : ""

                failures.append(TestFailure(
                    testName: testName,
                    file: file,
                    line: line,
                    message: message,
                    module: module
                ))
            }
        }

        return failures
    }

    func parseTestCounts(_ output: String) -> (total: Int, failed: Int) {
        // swift-testing: "Test run with 88 tests in 7 suites passed"
        let stPattern = #"Test run with (\d+) tests? in \d+ suites? (passed|failed)"#
        if let regex = try? NSRegularExpression(pattern: stPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let totalRange = Range(match.range(at: 1), in: output),
           let statusRange = Range(match.range(at: 2), in: output) {
            let total = Int(output[totalRange]) ?? 0
            let status = String(output[statusRange])
            // Count failed from parsed failures if status is "failed"
            return (total, status == "failed" ? 1 : 0)
        }

        // XCTest: "Executed 10 tests, with 2 failures"
        let xcPattern = #"Executed (\d+) tests?, with (\d+) failures?"#
        if let regex = try? NSRegularExpression(pattern: xcPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let totalRange = Range(match.range(at: 1), in: output),
           let failedRange = Range(match.range(at: 2), in: output) {
            return (Int(output[totalRange]) ?? 0, Int(output[failedRange]) ?? 0)
        }

        return (0, 0)
    }

    func inferModuleFromFile(_ file: String) -> String {
        let components = file.split(separator: "/")
        // Sources/Module/... or Tests/Module/...
        if components.count >= 2 {
            let parent = String(components[0])
            if parent == "Sources" || parent == "Tests" {
                return String(components[1])
            }
        }
        return "unknown"
    }

    // MARK: - Process Runners

    struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runGit(_ arguments: [String]) async throws -> ProcessResult {
        try await runProcess("/usr/bin/git", arguments: arguments)
    }

    func runSwift(_ arguments: [String]) async throws -> ProcessResult {
        try await runProcess("/usr/bin/swift", arguments: arguments)
    }

    func runProcess(_ executablePath: String, arguments: [String]) async throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
