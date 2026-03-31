// MARK: - TestGateEvaluator.swift
// ShikkiTestRunner — Evaluates which test level to run based on dispatch context.
// Maps: agent → scope-only, PR → scope+deps, merge → all parallel, release → all+E2E.

import Foundation

/// The dispatch context that determines test scope breadth.
///
/// Each context maps to a different test strategy:
/// - `agent`: Only the changed scopes (fastest, used in worktrees)
/// - `prGate`: Changed scopes + their dependents (catches cascading breaks)
/// - `merge`: All scopes in parallel (post-merge verification)
/// - `release`: All scopes + E2E + snapshots (full confidence gate)
public enum TestGateContext: String, Sendable, Codable, CaseIterable {
    /// Sub-agent working in a worktree. Runs `--scope <changed>` only.
    case agent

    /// Pre-PR gate. Runs `--scope <changed> + deps` to catch cascading failures.
    case prGate

    /// Merge to integration/develop. Runs `--parallel` (all scopes).
    case merge

    /// Release tag. Runs `--all` including E2E and snapshot tests.
    case release
}

/// The decision output from TestGateEvaluator — what to test and how.
public struct TestGateDecision: Sendable, Equatable {
    /// The context that produced this decision.
    public let context: TestGateContext

    /// Scopes to test. Empty means "all scopes" (for merge/release).
    public let scopes: [ScopeDefinition]

    /// Whether to run in parallel.
    public let parallel: Bool

    /// Whether to include E2E tests.
    public let includeE2E: Bool

    /// Whether to include snapshot/SUI tests.
    public let includeSnapshots: Bool

    /// Whether this is a partial run (not all scopes covered).
    public var isPartialRun: Bool {
        !scopes.isEmpty
    }

    /// Human-readable description of the decision for logging.
    public var summary: String {
        let scopeDesc: String
        if scopes.isEmpty {
            scopeDesc = "all scopes"
        } else {
            scopeDesc = scopes.map(\.name).joined(separator: ", ")
        }

        var flags: [String] = []
        if parallel { flags.append("parallel") }
        if includeE2E { flags.append("E2E") }
        if includeSnapshots { flags.append("snapshots") }

        let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"
        return "\(context.rawValue): \(scopeDesc)\(flagStr)"
    }

    public init(
        context: TestGateContext,
        scopes: [ScopeDefinition],
        parallel: Bool,
        includeE2E: Bool,
        includeSnapshots: Bool
    ) {
        self.context = context
        self.scopes = scopes
        self.parallel = parallel
        self.includeE2E = includeE2E
        self.includeSnapshots = includeSnapshots
    }
}

/// Evaluates which test level to run based on the dispatch context and changed files.
///
/// This is the bridge between the CI/dispatch pipeline and the test runner.
/// The evaluator uses `ChangedScopeDetector` for agent/prGate contexts
/// and returns all scopes for merge/release.
public struct TestGateEvaluator: Sendable {

    private let manifest: ScopeManifest
    private let detector: ChangedScopeDetector

    public init(manifest: ScopeManifest) {
        self.manifest = manifest
        self.detector = ChangedScopeDetector(manifest: manifest)
    }

    // MARK: - Public API

    /// Evaluate the test gate for a given context and set of changed files.
    ///
    /// - Parameters:
    ///   - context: The dispatch context (agent, prGate, merge, release).
    ///   - changedFiles: Files changed (from `git diff --name-only`). Used for agent/prGate.
    /// - Returns: A decision describing what to test and how.
    public func evaluateGate(
        context: TestGateContext,
        changedFiles: [String] = []
    ) -> TestGateDecision {
        switch context {
        case .agent:
            return evaluateAgent(changedFiles: changedFiles)
        case .prGate:
            return evaluatePRGate(changedFiles: changedFiles)
        case .merge:
            return evaluateMerge()
        case .release:
            return evaluateRelease()
        }
    }

    // MARK: - Context Evaluators

    /// Agent context: only changed scopes, no parallel, no extras.
    private func evaluateAgent(changedFiles: [String]) -> TestGateDecision {
        let affected = detector.affectedScopes(changedFiles: changedFiles)

        // If no scopes detected, fall back to unscoped (safety net)
        // An agent should at least test something
        if affected.isEmpty && !changedFiles.isEmpty {
            return TestGateDecision(
                context: .agent,
                scopes: [],
                parallel: false,
                includeE2E: false,
                includeSnapshots: false
            )
        }

        return TestGateDecision(
            context: .agent,
            scopes: affected,
            parallel: false,
            includeE2E: false,
            includeSnapshots: false
        )
    }

    /// PR gate: changed scopes + dependents, parallel if 2+ scopes.
    private func evaluatePRGate(changedFiles: [String]) -> TestGateDecision {
        let affected = detector.affectedWithDeps(changedFiles: changedFiles)

        // If no scopes detected from changed files, run all scopes (safe fallback)
        if affected.isEmpty && !changedFiles.isEmpty {
            return TestGateDecision(
                context: .prGate,
                scopes: [],
                parallel: true,
                includeE2E: false,
                includeSnapshots: false
            )
        }

        return TestGateDecision(
            context: .prGate,
            scopes: affected,
            parallel: affected.count >= 2,
            includeE2E: false,
            includeSnapshots: false
        )
    }

    /// Merge: all scopes in parallel, no E2E or snapshots.
    private func evaluateMerge() -> TestGateDecision {
        TestGateDecision(
            context: .merge,
            scopes: [],
            parallel: true,
            includeE2E: false,
            includeSnapshots: false
        )
    }

    /// Release: everything — all scopes in parallel + E2E + snapshots.
    private func evaluateRelease() -> TestGateDecision {
        TestGateDecision(
            context: .release,
            scopes: [],
            parallel: true,
            includeE2E: true,
            includeSnapshots: true
        )
    }
}
