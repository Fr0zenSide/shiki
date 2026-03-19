import Testing
import Foundation
@testable import ShikiCore

@Suite("FeatureLifecycle")
struct FeatureLifecycleTests {

    // MARK: - Helpers

    struct PassGate: PipelineGate {
        let name: String
        let index: Int
        func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
            .pass(detail: "ok")
        }
    }

    struct FailGate: PipelineGate {
        let name: String
        let index: Int
        func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
            .fail(reason: "nope")
        }
    }

    struct FakeContext: PipelineContext {
        let isDryRun = false
        let featureId = "test-feature"
        let projectRoot = URL(fileURLWithPath: "/tmp")
        func shell(_ command: String) async throws -> PipelineShellResult {
            PipelineShellResult(stdout: "", stderr: "", exitCode: 0)
        }
    }

    // MARK: - Tests

    @Test("Full flow: idle through done")
    func fullFlow() async throws {
        let lifecycle = FeatureLifecycle(featureId: "wave2a")
        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "spec done")
        try await lifecycle.transition(to: .building, actor: .user(id: "jeoffrey"), reason: "approved")
        try await lifecycle.transition(to: .gating, actor: .system, reason: "built")
        try await lifecycle.transition(to: .shipping, actor: .system, reason: "gates passed")
        try await lifecycle.transition(to: .done, actor: .system, reason: "shipped")
        let state = await lifecycle.state
        #expect(state == .done)
    }

    @Test("runGates transitions to onSuccess when all pass")
    func runGatesSuccess() async throws {
        let lifecycle = FeatureLifecycle(featureId: "wave2a")
        // Move to gating state first
        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "spec done")
        try await lifecycle.transition(to: .building, actor: .system, reason: "approved")
        try await lifecycle.transition(to: .gating, actor: .system, reason: "built")

        let gates: [PipelineGate] = [
            PassGate(name: "A", index: 0),
            PassGate(name: "B", index: 1),
        ]
        let result = try await lifecycle.runGates(
            gates, context: FakeContext(),
            onSuccess: .shipping, onFail: .failed
        )
        #expect(result.success)
        let state = await lifecycle.state
        #expect(state == .shipping)
    }

    @Test("runGates transitions to onFail when gate fails")
    func runGatesFail() async throws {
        let lifecycle = FeatureLifecycle(featureId: "wave2a")
        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "spec done")
        try await lifecycle.transition(to: .building, actor: .system, reason: "approved")
        try await lifecycle.transition(to: .gating, actor: .system, reason: "built")

        let gates: [PipelineGate] = [
            FailGate(name: "A", index: 0),
        ]
        let result = try await lifecycle.runGates(
            gates, context: FakeContext(),
            onSuccess: .shipping, onFail: .failed
        )
        #expect(!result.success)
        let state = await lifecycle.state
        #expect(state == .failed)
    }

    @Test("Checkpoint saves and restores state")
    func checkpointRoundtrip() async throws {
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-cp-\(UUID().uuidString).json").path

        let lifecycle = FeatureLifecycle(featureId: "wave2a")
        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "spec done")
        try await lifecycle.checkpoint(to: tmpPath)

        let restored = try FeatureLifecycle.restore(from: tmpPath)
        let restoredState = await restored?.state
        let restoredId = await restored?.featureId
        #expect(restoredState == .specPendingApproval)
        #expect(restoredId == "wave2a")

        try? FileManager.default.removeItem(atPath: tmpPath)
    }

    @Test("Invalid transition throws error")
    func invalidTransitionThrows() async throws {
        let lifecycle = FeatureLifecycle(featureId: "wave2a")
        // idle -> building is invalid (must go through specDrafting first)
        await #expect(throws: TransitionError.self) {
            try await lifecycle.transition(to: .building, actor: .system, reason: "skip")
        }
    }

    @Test("Governor gate blocks via specPendingApproval")
    func governorGate() async throws {
        let lifecycle = FeatureLifecycle(featureId: "wave2a")
        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "spec done")
        // Cannot go directly to gating — must go through building first
        await #expect(throws: TransitionError.self) {
            try await lifecycle.transition(to: .gating, actor: .system, reason: "skip building")
        }
    }
}
