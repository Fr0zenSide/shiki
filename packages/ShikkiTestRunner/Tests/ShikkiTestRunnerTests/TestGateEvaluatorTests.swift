import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("TestGateEvaluator")
struct TestGateEvaluatorTests {

    // MARK: - Helpers

    private static let testManifest = ScopeManifest(
        scopes: [
            ScopeDefinition(
                name: "nats",
                modulePatterns: ["NATSClient"],
                typePatterns: ["EventBus", "NATSConnection"],
                testFilePatterns: ["**/NATS*Tests.swift"]
            ),
            ScopeDefinition(
                name: "kernel",
                modulePatterns: ["ShikkiKit"],
                typePatterns: ["ShikkiKernel", "ManagedService"],
                testFilePatterns: ["**/Kernel*Tests.swift"]
            ),
            ScopeDefinition(
                name: "tui",
                modulePatterns: ["TUI"],
                typePatterns: ["TerminalOutput"],
                testFilePatterns: ["**/TUI*Tests.swift"],
                dependsOn: ["kernel"]
            ),
            ScopeDefinition(
                name: "safety",
                modulePatterns: ["Safety"],
                typePatterns: ["BudgetACL"],
                testFilePatterns: ["**/Safety*Tests.swift"]
            ),
            ScopeDefinition(
                name: "ship",
                modulePatterns: ["Ship"],
                typePatterns: ["ShipGate"],
                testFilePatterns: ["**/Ship*Tests.swift"],
                dependsOn: ["kernel", "safety"]
            ),
        ],
        source: .defaultFallback
    )

    private var evaluator: TestGateEvaluator {
        TestGateEvaluator(manifest: Self.testManifest)
    }

    // MARK: - Agent Context

    @Test("Agent context returns only changed scopes")
    func agentOnlyChangedScopes() {
        let decision = evaluator.evaluateGate(
            context: .agent,
            changedFiles: ["Sources/NATSClient/EventBus.swift"]
        )

        #expect(decision.context == .agent)
        #expect(decision.scopes.map(\.name) == ["nats"])
        #expect(decision.parallel == false)
        #expect(decision.includeE2E == false)
        #expect(decision.includeSnapshots == false)
        #expect(decision.isPartialRun == true)
    }

    @Test("Agent context with unrecognized files falls back to all")
    func agentUnrecognizedFilesFallback() {
        let decision = evaluator.evaluateGate(
            context: .agent,
            changedFiles: ["README.md"]
        )

        #expect(decision.context == .agent)
        #expect(decision.scopes.isEmpty)
        #expect(decision.isPartialRun == false)
    }

    @Test("Agent context with no changed files returns empty")
    func agentNoChangedFiles() {
        let decision = evaluator.evaluateGate(
            context: .agent,
            changedFiles: []
        )

        #expect(decision.scopes.isEmpty)
    }

    // MARK: - PR Gate Context

    @Test("PR gate expands to include dependents")
    func prGateExpandsDeps() {
        let decision = evaluator.evaluateGate(
            context: .prGate,
            changedFiles: ["Sources/ShikkiKit/Kernel/ShikkiKernel.swift"]
        )

        #expect(decision.context == .prGate)
        let names = decision.scopes.map(\.name)
        #expect(names.contains("kernel"))
        #expect(names.contains("tui"))   // depends on kernel
        #expect(names.contains("ship"))  // depends on kernel
    }

    @Test("PR gate enables parallel for 2+ scopes")
    func prGateParallelMultipleScopes() {
        let decision = evaluator.evaluateGate(
            context: .prGate,
            changedFiles: ["Sources/ShikkiKit/Kernel/ShikkiKernel.swift"]
        )

        // kernel + tui + ship = 3 scopes
        #expect(decision.parallel == true)
    }

    @Test("PR gate single scope not parallel")
    func prGateSingleScopeNotParallel() {
        // tui has no dependents, and only depends on kernel (not affected here)
        let decision = evaluator.evaluateGate(
            context: .prGate,
            changedFiles: ["Tests/TUIRenderTests.swift"]
        )

        #expect(decision.scopes.count == 1)
        #expect(decision.parallel == false)
    }

    @Test("PR gate excludes E2E and snapshots")
    func prGateNoExtras() {
        let decision = evaluator.evaluateGate(
            context: .prGate,
            changedFiles: ["Sources/ShikkiKit/Kernel/ShikkiKernel.swift"]
        )

        #expect(decision.includeE2E == false)
        #expect(decision.includeSnapshots == false)
    }

    // MARK: - Merge Context

    @Test("Merge context runs all scopes in parallel")
    func mergeAllParallel() {
        let decision = evaluator.evaluateGate(context: .merge)

        #expect(decision.context == .merge)
        #expect(decision.scopes.isEmpty)  // empty = all scopes
        #expect(decision.parallel == true)
        #expect(decision.includeE2E == false)
        #expect(decision.includeSnapshots == false)
        #expect(decision.isPartialRun == false)
    }

    @Test("Merge ignores changed files")
    func mergeIgnoresChangedFiles() {
        let decision = evaluator.evaluateGate(
            context: .merge,
            changedFiles: ["Sources/NATSClient/EventBus.swift"]
        )

        #expect(decision.scopes.isEmpty)
        #expect(decision.parallel == true)
    }

    // MARK: - Release Context

    @Test("Release runs everything including E2E and snapshots")
    func releaseRunsEverything() {
        let decision = evaluator.evaluateGate(context: .release)

        #expect(decision.context == .release)
        #expect(decision.scopes.isEmpty)  // empty = all scopes
        #expect(decision.parallel == true)
        #expect(decision.includeE2E == true)
        #expect(decision.includeSnapshots == true)
        #expect(decision.isPartialRun == false)
    }

    // MARK: - Summary

    @Test("Summary describes agent context correctly")
    func summaryAgent() {
        let decision = evaluator.evaluateGate(
            context: .agent,
            changedFiles: ["Sources/NATSClient/EventBus.swift"]
        )

        let summary = decision.summary
        #expect(summary.contains("agent"))
        #expect(summary.contains("nats"))
    }

    @Test("Summary describes release context correctly")
    func summaryRelease() {
        let decision = evaluator.evaluateGate(context: .release)

        let summary = decision.summary
        #expect(summary.contains("release"))
        #expect(summary.contains("all scopes"))
        #expect(summary.contains("parallel"))
        #expect(summary.contains("E2E"))
        #expect(summary.contains("snapshots"))
    }

    // MARK: - TestGateContext

    @Test("All gate contexts are enumerable")
    func allContexts() {
        let contexts = TestGateContext.allCases
        #expect(contexts.count == 4)
        #expect(contexts.contains(.agent))
        #expect(contexts.contains(.prGate))
        #expect(contexts.contains(.merge))
        #expect(contexts.contains(.release))
    }
}
