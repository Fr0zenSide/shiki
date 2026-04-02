import Foundation

/// Errors during fix loop.
public enum FixError: Error, LocalizedError, Sendable {
    case maxIterationsReached(Int, [TestFailure])
    case architecturalFailure([TestFailure])
    case noFailuresToFix

    public var errorDescription: String? {
        switch self {
        case .maxIterationsReached(let iterations, let remaining):
            return "Max \(iterations) fix iterations reached, \(remaining.count) failures remain"
        case .architecturalFailure(let failures):
            return "Architectural issue: \(failures.count) failures (>20) — developer intervention needed"
        case .noFailuresToFix:
            return "No failures to fix"
        }
    }
}

/// Result of a fix loop iteration.
public struct FixIterationResult: Sendable {
    public let iteration: Int
    public let fixedCount: Int
    public let remainingFailures: [TestFailure]
    public let agentResults: [AgentResult]

    public var allFixed: Bool { remainingFailures.isEmpty }

    public init(
        iteration: Int,
        fixedCount: Int = 0,
        remainingFailures: [TestFailure] = [],
        agentResults: [AgentResult] = []
    ) {
        self.iteration = iteration
        self.fixedCount = fixedCount
        self.remainingFailures = remainingFailures
        self.agentResults = agentResults
    }
}

/// Result of the complete fix loop.
public struct FixResult: Sendable {
    public let iterations: [FixIterationResult]
    public let finallyPassed: Bool
    public let totalFixedCount: Int
    public let remainingFailures: [TestFailure]

    public init(
        iterations: [FixIterationResult] = [],
        finallyPassed: Bool = false,
        totalFixedCount: Int = 0,
        remainingFailures: [TestFailure] = []
    ) {
        self.iterations = iterations
        self.finallyPassed = finallyPassed
        self.totalFixedCount = totalFixedCount
        self.remainingFailures = remainingFailures
    }
}

// MARK: - Protocols for Testability

/// Abstracts git operations for snapshot/rollback/diff.
public protocol GitOperationsProvider: Sendable {
    /// Snapshot HEAD commit hash via `git rev-parse HEAD`.
    func snapshotHead() async throws -> String
    /// Hard-reset to a specific commit hash via `git reset --hard <hash>`.
    func resetHard(to hash: String) async throws
    /// List modified files via `git diff --name-only`.
    func diffNameOnly() async throws -> [String]
}

/// Abstracts contract verification for injection.
public protocol ContractVerifierProtocol: Sendable {
    /// Run static analysis on the protocol layer.
    func verify(_ layer: ProtocolLayer) -> ContractResult
}

/// Abstracts test running for injection.
public protocol TestRunnerProtocol: Sendable {
    /// Run tests with optional scope filter.
    func runTests(scope: [String]) async throws -> TestRunResult
}

// MARK: - Default Implementations

/// Default git operations using MergeEngine.
struct DefaultGitOps: GitOperationsProvider {
    private let mergeEngine: MergeEngine

    init(mergeEngine: MergeEngine) {
        self.mergeEngine = mergeEngine
    }

    func snapshotHead() async throws -> String {
        let result = try await mergeEngine.runGit(["rev-parse", "HEAD"])
        return result.stdout
    }

    func resetHard(to hash: String) async throws {
        _ = try await mergeEngine.runGit(["reset", "--hard", hash])
    }

    func diffNameOnly() async throws -> [String] {
        let result = try await mergeEngine.runGit(["diff", "--name-only"])
        return result.stdout
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }
}

/// Default contract verifier wrapping the real ContractVerifier.
struct DefaultContractVerifierAdapter: ContractVerifierProtocol {
    private let verifier: ContractVerifier

    init(_ verifier: ContractVerifier) {
        self.verifier = verifier
    }

    func verify(_ layer: ProtocolLayer) -> ContractResult {
        verifier.verify(layer)
    }
}

/// Default test runner wrapping MergeEngine.
struct DefaultTestRunner: TestRunnerProtocol {
    private let mergeEngine: MergeEngine

    init(mergeEngine: MergeEngine) {
        self.mergeEngine = mergeEngine
    }

    func runTests(scope: [String]) async throws -> TestRunResult {
        try await mergeEngine.runTests(scope: scope)
    }
}

/// Converts test failures into fix work units and dispatches fix agents.
///
/// Strategy (from challenge session):
/// - <5 failures -> single agent fixes all
/// - 5-20 failures -> split by module, parallel fix agents
/// - >20 failures -> architectural issue, escalate to developer
/// - Max 3 iterations -> then ask the developer
///
/// Safety guards (hardening):
/// - BR-01: Snapshot HEAD before each iteration
/// - BR-02: Contract verification after each fix, rollback if invalid
/// - BR-03: Regression detection (more failures than before), rollback
/// - BR-04: Test file modification guard, rollback if `*Tests.swift` touched
/// - BR-05: Exhaustion event when all iterations used with failures remaining
/// - BR-06: Per-iteration timeout with rollback
public struct FixEngine: Sendable {

    public static let maxIterations = 3

    private let mergeEngine: MergeEngine
    private let agentRunner: AgentRunner
    private let projectRoot: String
    private let gitOps: GitOperationsProvider
    private let contractVerifier: ContractVerifierProtocol
    private let testRunner: TestRunnerProtocol
    private let iterationTimeoutSeconds: Int

    /// Create a FixEngine with default dependencies (production use).
    ///
    /// - Parameters:
    ///   - projectRoot: Absolute path to the project root.
    ///   - agentRunner: The agent runner to dispatch fix agents.
    ///   - contractVerifier: Contract verifier for protocol layer checks.
    ///   - iterationTimeoutSeconds: Per-iteration timeout in seconds (default: 300).
    public init(
        projectRoot: String,
        agentRunner: AgentRunner,
        contractVerifier: ContractVerifier = ContractVerifier(),
        iterationTimeoutSeconds: Int = 300
    ) {
        self.projectRoot = projectRoot
        self.agentRunner = agentRunner
        let merge = MergeEngine(projectRoot: projectRoot)
        self.mergeEngine = merge
        self.gitOps = DefaultGitOps(mergeEngine: merge)
        self.contractVerifier = DefaultContractVerifierAdapter(contractVerifier)
        self.testRunner = DefaultTestRunner(mergeEngine: merge)
        self.iterationTimeoutSeconds = iterationTimeoutSeconds
    }

    /// Create a FixEngine with injectable dependencies (testing use).
    init(
        projectRoot: String,
        agentRunner: AgentRunner,
        contractVerifier: ContractVerifierProtocol,
        iterationTimeoutSeconds: Int = 300,
        gitOps: GitOperationsProvider,
        testRunner: TestRunnerProtocol
    ) {
        self.projectRoot = projectRoot
        self.agentRunner = agentRunner
        self.mergeEngine = MergeEngine(projectRoot: projectRoot)
        self.gitOps = gitOps
        self.contractVerifier = contractVerifier
        self.testRunner = testRunner
        self.iterationTimeoutSeconds = iterationTimeoutSeconds
    }

    /// Run the fix loop on test failures.
    ///
    /// - Parameters:
    ///   - failures: Initial test failures to fix.
    ///   - layer: The protocol layer for context.
    ///   - cache: Optional architecture cache.
    ///   - testScope: Tests to re-run after each fix.
    ///   - onProgress: Progress callback.
    /// - Returns: The fix result.
    public func fix(
        failures: [TestFailure],
        layer: ProtocolLayer,
        cache: ArchitectureCache? = nil,
        testScope: [String] = [],
        onProgress: (@Sendable (FixProgressEvent) -> Void)? = nil
    ) async throws -> FixResult {
        guard !failures.isEmpty else {
            throw FixError.noFailuresToFix
        }

        // >20 failures = architectural, escalate immediately
        if failures.count > 20 {
            throw FixError.architecturalFailure(failures)
        }

        var currentFailures = failures
        var iterations: [FixIterationResult] = []
        var totalFixed = 0

        for iteration in 1...Self.maxIterations {
            onProgress?(.iterationStarted(iteration: iteration, failureCount: currentFailures.count))

            // BR-01: Snapshot HEAD before each iteration
            let snapshot = try await gitOps.snapshotHead()

            // Convert failures to fix work units
            let fixUnits = createFixUnits(from: currentFailures, iteration: iteration)

            // BR-06: Per-iteration timeout wrapping agent dispatch
            // Capture mutable state as let to satisfy Sendable requirements
            let failuresSnapshot = currentFailures
            let iterationResult: IterationOutcome
            do {
                iterationResult = try await withThrowingTaskGroup(of: IterationOutcome.self) { group in
                    group.addTask {
                        // Dispatch fix agents
                        var agentResults: [AgentResult] = []
                        for unit in fixUnits {
                            let prompt = self.generateFixPrompt(
                                unit: unit,
                                failures: failuresSnapshot.filter { failure in
                                    unit.modules.contains(failure.module) || unit.modules.contains("all")
                                },
                                layer: layer,
                                cache: cache
                            )

                            let result = try await self.agentRunner.run(
                                prompt: prompt,
                                workingDirectory: self.projectRoot,
                                unitId: unit.id
                            )
                            agentResults.append(result)
                        }
                        return .completed(agentResults)
                    }

                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(self.iterationTimeoutSeconds) * 1_000_000_000)
                        return .timedOut
                    }

                    // First task to finish wins
                    let first = try await group.next()!
                    group.cancelAll()
                    return first
                }
            } catch {
                // If the task group throws (e.g. cancellation), rollback and rethrow
                try? await gitOps.resetHard(to: snapshot)
                throw error
            }

            // Handle timeout
            if case .timedOut = iterationResult {
                try await gitOps.resetHard(to: snapshot)
                onProgress?(.timedOut(iteration: iteration))

                let iterResult = FixIterationResult(
                    iteration: iteration,
                    fixedCount: 0,
                    remainingFailures: currentFailures,
                    agentResults: []
                )
                iterations.append(iterResult)
                break
            }

            guard case .completed(let agentResults) = iterationResult else {
                break
            }

            // BR-04: Check for test file modifications before running tests
            let modifiedFiles = try await gitOps.diffNameOnly()
            let testFiles = modifiedFiles.filter { $0.hasSuffix("Tests.swift") }
            if !testFiles.isEmpty {
                try await gitOps.resetHard(to: snapshot)
                onProgress?(.testFileModification(iteration: iteration, files: testFiles))

                let iterResult = FixIterationResult(
                    iteration: iteration,
                    fixedCount: 0,
                    remainingFailures: currentFailures,
                    agentResults: agentResults
                )
                iterations.append(iterResult)
                // Skip this iteration, continue to next
                continue
            }

            // BR-02: Contract verification after agent changes
            let contractResult = contractVerifier.verify(layer)
            if !contractResult.isValid {
                try await gitOps.resetHard(to: snapshot)
                onProgress?(.contractViolation(iteration: iteration, issues: contractResult.issues))

                let iterResult = FixIterationResult(
                    iteration: iteration,
                    fixedCount: 0,
                    remainingFailures: currentFailures,
                    agentResults: agentResults
                )
                iterations.append(iterResult)
                // Skip this iteration, continue to next
                continue
            }

            // Re-run tests
            let testResult = try await testRunner.runTests(scope: testScope)

            let previousCount = currentFailures.count
            currentFailures = testResult.failures
            let fixedThisIteration = previousCount - currentFailures.count

            // BR-03: Regression detection -- more failures than before
            if fixedThisIteration < 0 {
                try await gitOps.resetHard(to: snapshot)
                onProgress?(.regression(iteration: iteration, delta: fixedThisIteration))

                // Restore previous failure list (rollback undid changes)
                currentFailures = iterations.last?.remainingFailures ?? failures

                let iterResult = FixIterationResult(
                    iteration: iteration,
                    fixedCount: 0,
                    remainingFailures: currentFailures,
                    agentResults: agentResults
                )
                iterations.append(iterResult)
                break
            }

            let iterResult = FixIterationResult(
                iteration: iteration,
                fixedCount: max(0, fixedThisIteration),
                remainingFailures: currentFailures,
                agentResults: agentResults
            )
            iterations.append(iterResult)
            totalFixed += max(0, fixedThisIteration)

            onProgress?(.iterationCompleted(
                iteration: iteration,
                fixed: max(0, fixedThisIteration),
                remaining: currentFailures.count
            ))

            // All fixed?
            if currentFailures.isEmpty {
                return FixResult(
                    iterations: iterations,
                    finallyPassed: true,
                    totalFixedCount: totalFixed,
                    remainingFailures: []
                )
            }

            // No progress? Don't loop more
            if fixedThisIteration <= 0 && iteration > 1 {
                onProgress?(.noProgress(iteration: iteration))
                break
            }
        }

        // BR-05: If all iterations exhausted with failures remaining
        if iterations.count == Self.maxIterations && !currentFailures.isEmpty {
            onProgress?(.exhausted(remaining: currentFailures))
        }

        return FixResult(
            iterations: iterations,
            finallyPassed: false,
            totalFixedCount: totalFixed,
            remainingFailures: currentFailures
        )
    }

    // MARK: - Iteration Outcome

    private enum IterationOutcome: Sendable {
        case completed([AgentResult])
        case timedOut
    }

    // MARK: - Fix Unit Creation

    struct FixUnit: Sendable {
        let id: String
        let modules: [String]
        let description: String
    }

    func createFixUnits(from failures: [TestFailure], iteration: Int) -> [FixUnit] {
        if failures.count < 5 {
            // Single agent fixes all
            return [FixUnit(
                id: "fix-all-iter\(iteration)",
                modules: ["all"],
                description: "Fix all \(failures.count) test failures"
            )]
        }

        // Split by module
        let grouped = mergeEngine.groupByModule(failures)
        return grouped.map { (module, moduleFailures) in
            FixUnit(
                id: "fix-\(module)-iter\(iteration)",
                modules: [module],
                description: "Fix \(moduleFailures.count) failures in \(module)"
            )
        }
    }

    // MARK: - Fix Prompt Generation

    func generateFixPrompt(
        unit: FixUnit,
        failures: [TestFailure],
        layer: ProtocolLayer,
        cache: ArchitectureCache?
    ) -> String {
        var lines: [String] = []

        lines.append("# Fix Task: \(unit.description)")
        lines.append("")
        lines.append("You must fix the following test failures. Do NOT change the test expectations \u{2014}")
        lines.append("fix the implementation code to make the tests pass.")
        lines.append("")

        // List failures
        lines.append("## Failures")
        for failure in failures {
            var detail = "- **\(failure.testName)**"
            if !failure.file.isEmpty {
                detail += " at `\(failure.file)"
                if let line = failure.line { detail += ":\(line)" }
                detail += "`"
            }
            if !failure.message.isEmpty {
                detail += " \u{2014} \(failure.message)"
            }
            lines.append(detail)
        }
        lines.append("")

        // Protocol context (don't modify these)
        if !layer.protocols.isEmpty {
            lines.append("## Protocol Contracts (do NOT modify)")
            let verifier = ContractVerifier()
            lines.append("```swift")
            lines.append(verifier.generateSource(layer))
            lines.append("```")
            lines.append("")
        }

        // Architecture context
        if let cache {
            lines.append("## Project Context")
            lines.append(ContextBuilder.agentSummary(cache))
            lines.append("")
        }

        // Constraints
        lines.append("## Rules")
        lines.append("- Fix implementation code, NOT tests")
        lines.append("- Do not modify protocol definitions")
        lines.append("- Run `swift test` to verify your fix before finishing")
        lines.append("- Keep changes minimal \u{2014} fix only what's broken")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Fix Progress Events

public enum FixProgressEvent: Sendable {
    case iterationStarted(iteration: Int, failureCount: Int)
    case iterationCompleted(iteration: Int, fixed: Int, remaining: Int)
    case noProgress(iteration: Int)
    case regression(iteration: Int, delta: Int)
    case contractViolation(iteration: Int, issues: [String])
    case testFileModification(iteration: Int, files: [String])
    case exhausted(remaining: [TestFailure])
    case timedOut(iteration: Int)
}
