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

/// Converts test failures into fix work units and dispatches fix agents.
///
/// Strategy (from challenge session):
/// - <5 failures → single agent fixes all
/// - 5-20 failures → split by module, parallel fix agents
/// - >20 failures → architectural issue, escalate to developer
/// - Max 3 iterations → then ask the developer
public struct FixEngine: Sendable {

    public static let maxIterations = 3

    private let mergeEngine: MergeEngine
    private let agentRunner: AgentRunner
    private let projectRoot: String

    public init(projectRoot: String, agentRunner: AgentRunner) {
        self.projectRoot = projectRoot
        self.mergeEngine = MergeEngine(projectRoot: projectRoot)
        self.agentRunner = agentRunner
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

            // Convert failures to fix work units
            let fixUnits = createFixUnits(from: currentFailures, iteration: iteration)

            // Dispatch fix agents
            var agentResults: [AgentResult] = []
            for unit in fixUnits {
                let prompt = generateFixPrompt(
                    unit: unit,
                    failures: currentFailures.filter { failure in
                        unit.modules.contains(failure.module) || unit.modules.contains("all")
                    },
                    layer: layer,
                    cache: cache
                )

                let result = try await agentRunner.run(
                    prompt: prompt,
                    workingDirectory: projectRoot,
                    unitId: unit.id
                )
                agentResults.append(result)
            }

            // Re-run tests
            let testResult = try await mergeEngine.runTests(scope: testScope)

            let previousCount = currentFailures.count
            currentFailures = testResult.failures
            let fixedThisIteration = previousCount - currentFailures.count

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

        return FixResult(
            iterations: iterations,
            finallyPassed: false,
            totalFixedCount: totalFixed,
            remainingFailures: currentFailures
        )
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
        lines.append("You must fix the following test failures. Do NOT change the test expectations —")
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
                detail += " — \(failure.message)"
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
        lines.append("- Keep changes minimal — fix only what's broken")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Fix Progress Events

public enum FixProgressEvent: Sendable {
    case iterationStarted(iteration: Int, failureCount: Int)
    case iterationCompleted(iteration: Int, fixed: Int, remaining: Int)
    case noProgress(iteration: Int)
}
