import Foundation
import Testing
@testable import ShikkiKit

// MARK: - FastPipeline Tests

@Suite("FastPipeline — Quick + Ship in One Pipeline")
struct FastPipelineTests {

    // MARK: - FastPipelineStage Tests

    @Test("Fast pipeline has 4 stages")
    func stages_count() {
        #expect(FastPipelineStage.allCases.count == 4)
    }

    @Test("Stage descriptions match expected values")
    func stages_descriptions() {
        #expect(FastPipelineStage.quick.description == "quick")
        #expect(FastPipelineStage.test.description == "test")
        #expect(FastPipelineStage.prePR.description == "pre-pr")
        #expect(FastPipelineStage.ship.description == "ship")
    }

    @Test("Stage display names are human-readable")
    func stages_displayNames() {
        #expect(FastPipelineStage.quick.displayName == "Quick Flow")
        #expect(FastPipelineStage.test.displayName == "Full Test Suite")
        #expect(FastPipelineStage.prePR.displayName == "Pre-PR Gates")
        #expect(FastPipelineStage.ship.displayName == "Ship")
    }

    // MARK: - FastPipeline Integration Tests

    @Test("Fast pipeline succeeds with mock agent and no gates")
    func pipeline_noGates_succeeds() async throws {
        let agent = MockAgentProvider()
        agent.response = """
        - Problem: Simple fix needed
        - Solution: Apply the fix
        Done. 1 file changed, 5 tests passing, 1 new test.
        """

        let pipeline = FastPipeline(agent: agent)
        let result = try await pipeline.run(
            prompt: "fix the bug",
            projectPath: "/tmp/test",
            dryRun: false,
            shipContext: nil,
            shipGates: []
        )

        #expect(result.success)
        #expect(result.quickResult.stepsCompleted == 3)
        #expect(result.testsAllPassed)
        #expect(result.gatesPassed == 0)
        #expect(result.gatesTotal == 0)
        #expect(result.failedStage == nil)
        #expect(result.duration > 0)
    }

    @Test("Fast pipeline reports quick failure at stage 1")
    func pipeline_quickFails_reportsStage() async throws {
        let agent = MockAgentProvider()
        agent.shouldThrow = true

        let pipeline = FastPipeline(agent: agent)
        let result = try await pipeline.run(
            prompt: "fix something",
            projectPath: nil,
            dryRun: false,
            shipContext: nil,
            shipGates: []
        )

        #expect(!result.success)
        #expect(result.failedStage == .quick)
        #expect(result.failureReason != nil)
    }

    @Test("Fast pipeline aborts on empty prompt")
    func pipeline_emptyPrompt_failsAtQuickStage() async throws {
        let agent = MockAgentProvider()
        let pipeline = FastPipeline(agent: agent)

        let result = try await pipeline.run(
            prompt: "  ",
            projectPath: nil,
            dryRun: false,
            shipContext: nil,
            shipGates: []
        )

        #expect(!result.success)
        #expect(result.failedStage == .quick)
    }

    @Test("Fast pipeline runs ship gates when provided")
    func pipeline_withGates_runsGates() async throws {
        let agent = MockAgentProvider()
        agent.response = "- Problem: fix\nDone. 1 file changed."

        let ctx = MockShipContext()
        let gates: [any ShipGate] = [
            PassGate(name: "Test", index: 0),
            PassGate(name: "Lint", index: 1),
        ]

        let pipeline = FastPipeline(agent: agent)
        let result = try await pipeline.run(
            prompt: "fix the bug",
            projectPath: nil,
            dryRun: false,
            shipContext: ctx,
            shipGates: gates
        )

        #expect(result.success)
        #expect(result.gatesPassed == 2)
        #expect(result.gatesTotal == 2)
    }

    @Test("Fast pipeline aborts when ship gate fails")
    func pipeline_gateFails_abortsAtPrePR() async throws {
        let agent = MockAgentProvider()
        agent.response = "- Problem: fix\nDone. 1 file changed."

        let ctx = MockShipContext()
        let gates: [any ShipGate] = [
            PassGate(name: "Test", index: 0),
            FailGate(name: "Lint", index: 1, reason: "lint errors"),
        ]

        let pipeline = FastPipeline(agent: agent)
        let result = try await pipeline.run(
            prompt: "fix something",
            projectPath: nil,
            dryRun: false,
            shipContext: ctx,
            shipGates: gates
        )

        #expect(!result.success)
        #expect(result.failedStage == .prePR)
        #expect(result.failureReason?.contains("lint errors") == true)
        #expect(result.gatesPassed == 1) // Test passed, Lint failed
    }

    // MARK: - FastPipelineResult Tests

    @Test("FastPipelineResult stores all fields correctly")
    func result_storesFields() {
        let quickResult = QuickPipelineResult(
            summary: "Fixed a bug",
            filesChanged: 2,
            testsPassing: 10,
            newTests: 1,
            commitHash: "abc123",
            duration: 5.0,
            stepsCompleted: 3
        )

        let result = FastPipelineResult(
            quickResult: quickResult,
            testsAllPassed: true,
            gatesPassed: 3,
            gatesTotal: 3,
            success: true,
            duration: 10.0
        )

        #expect(result.success)
        #expect(result.quickResult.summary == "Fixed a bug")
        #expect(result.testsAllPassed)
        #expect(result.gatesPassed == 3)
        #expect(result.gatesTotal == 3)
        #expect(result.failedStage == nil)
        #expect(result.failureReason == nil)
        #expect(result.duration == 10.0)
    }

    @Test("FastPipelineResult records failure details")
    func result_failureDetails() {
        let quickResult = QuickPipelineResult(
            summary: "attempt",
            filesChanged: 0,
            testsPassing: 0,
            newTests: 0,
            commitHash: nil,
            duration: 1.0,
            stepsCompleted: 0
        )

        let result = FastPipelineResult(
            quickResult: quickResult,
            testsAllPassed: false,
            gatesPassed: 0,
            gatesTotal: 2,
            success: false,
            failedStage: .test,
            failureReason: "3 tests failed",
            duration: 2.0
        )

        #expect(!result.success)
        #expect(result.failedStage == .test)
        #expect(result.failureReason == "3 tests failed")
    }

    // MARK: - FastPipelineError Tests

    @Test("FastPipelineError supports Equatable")
    func errors_areEquatable() {
        #expect(
            FastPipelineError.quickFailed("x") == FastPipelineError.quickFailed("x")
        )
        #expect(
            FastPipelineError.testsFailed("a") != FastPipelineError.testsFailed("b")
        )
        #expect(
            FastPipelineError.prePRFailed(gate: "Lint", reason: "errors")
            == FastPipelineError.prePRFailed(gate: "Lint", reason: "errors")
        )
    }
}
