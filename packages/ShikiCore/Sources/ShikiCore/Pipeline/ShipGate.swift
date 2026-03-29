import Foundation

// MARK: - ShipGate

/// Pipeline gate that validates a feature is ready to ship.
/// Wraps the 8 sub-gates from the ship pipeline into a single PipelineGate:
///   1. Clean branch (no uncommitted changes)
///   2. Tests pass
///   3. Coverage above threshold
///   4. Risk assessment
///   5. Changelog generated
///   6. Version bump determined
///   7. Commit strategy applied
///   8. PR created
///
/// In ShikiCore, ShipGate runs the essential checks (clean + tests)
/// and delegates the rest to the CLI-level ship pipeline.
public struct ShipGate: PipelineGate, Sendable {
    public let name = "Ship"
    public let index: Int
    public let targetBranch: String

    public init(index: Int, targetBranch: String = "develop") {
        self.index = index
        self.targetBranch = targetBranch
    }

    public func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
        // Sub-gate 1: Clean branch
        let statusResult = try await context.shell("git status --porcelain")
        let status = statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty {
            return .fail(reason: "Working tree not clean: \(status.prefix(200))")
        }

        // Sub-gate 2: Tests pass
        let testResult = try await context.shell(
            "swift test --package-path \(context.projectRoot.path) 2>&1"
        )
        if testResult.exitCode != 0 {
            return .fail(reason: "Tests failed (exit \(testResult.exitCode))")
        }

        // Sub-gate 3: Target branch validation (git flow)
        if targetBranch == "main" || targetBranch == "master" {
            return .fail(
                reason: "Cannot target '\(targetBranch)' directly. Use 'develop' or 'release/*' per git flow."
            )
        }

        // Sub-gate 4: Diff stat for risk assessment
        let diffResult = try await context.shell("git diff --stat \(targetBranch)...HEAD 2>/dev/null || echo 'no diff'")
        let diffOutput = diffResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if context.isDryRun {
            return .pass(detail: "[dry-run] Ship checks passed. Diff: \(diffOutput.prefix(100))")
        }

        return .pass(detail: "Ship ready — branch clean, tests pass, target: \(targetBranch)")
    }
}
