import Foundation
import Testing
@testable import ShikkiCore

@Suite("E2E Lifecycle")
struct E2ELifecycleTests {

    @Test("Full lifecycle: idle through done with all transitions")
    func fullLifecycle() async throws {
        let lifecycle = FeatureLifecycle(featureId: "e2e-full")

        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "Start")
        #expect(await lifecycle.state == .specDrafting)

        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "Spec done")
        #expect(await lifecycle.state == .specPendingApproval)

        try await lifecycle.transition(to: .building, actor: .user(id: "daimyo"), reason: "Approved")
        #expect(await lifecycle.state == .building)

        try await lifecycle.transition(to: .gating, actor: .system, reason: "Build done")
        try await lifecycle.transition(to: .shipping, actor: .system, reason: "Gates passed")
        try await lifecycle.transition(to: .done, actor: .system, reason: "PR created")
        #expect(await lifecycle.state == .done)
    }

    @Test("Lifecycle with decisions branch")
    func decisionsPath() async throws {
        let lifecycle = FeatureLifecycle(featureId: "e2e-decisions")

        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "Start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "Spec done")
        try await lifecycle.transition(to: .decisionsNeeded, actor: .user(id: "d"), reason: "Questions")
        #expect(await lifecycle.state == .decisionsNeeded)

        try await lifecycle.transition(to: .building, actor: .user(id: "d"), reason: "Answered")
        #expect(await lifecycle.state == .building)
    }

    @Test("Lifecycle blocked and resume")
    func blockedResume() async throws {
        let lifecycle = FeatureLifecycle(featureId: "e2e-blocked")

        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "Start")
        try await lifecycle.transition(to: .blocked, actor: .system, reason: "External blocker")
        #expect(await lifecycle.state == .blocked)
    }

    @Test("Checkpoint save and restore round-trip")
    func checkpointRoundTrip() async throws {
        let tmpDir = NSTemporaryDirectory() + "shiki-e2e-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let lifecycle = FeatureLifecycle(featureId: "e2e-checkpoint")
        try await lifecycle.transition(to: .specDrafting, actor: .system, reason: "Start")
        try await lifecycle.transition(to: .specPendingApproval, actor: .system, reason: "Done")
        try await lifecycle.transition(to: .building, actor: .user(id: "d"), reason: "OK")

        let path = "\(tmpDir)/e2e-checkpoint.json"
        try await lifecycle.checkpoint(to: path)

        let restored = try FeatureLifecycle.restore(from: path)
        #expect(restored != nil)
        #expect(await restored!.state == .building)
    }

    @Test("CompanyManager manages multiple lifecycles")
    func companyManagerMulti() async throws {
        let manager = CompanyManager()
        let lc1 = await manager.register(featureId: "feat-1")
        let lc2 = await manager.register(featureId: "feat-2")

        #expect(await manager.activeCount == 2)

        try await lc1.transition(to: .specDrafting, actor: .system, reason: "Go")
        try await lc2.transition(to: .specDrafting, actor: .system, reason: "Go")

        #expect(await lc1.state == .specDrafting)
        #expect(await lc2.state == .specDrafting)

        await manager.remove(featureId: "feat-1")
        #expect(await manager.activeCount == 1)
    }

    @Test("DependencyTree wave scheduling")
    func dependencyTreeScheduling() {
        var tree = DependencyTree(waves: [
            WaveNode(id: "1a", name: "MCP", branch: "mcp", baseBranch: "dev", testCount: 33),
            WaveNode(id: "1b", name: "Ship", branch: "ship", baseBranch: "dev", testCount: 24),
            WaveNode(id: "2a", name: "Integration", branch: "int", baseBranch: "dev", testCount: 15, dependsOn: ["1a", "1b"]),
        ])

        let ready0 = tree.readyWaves(completed: [])
        #expect(ready0.count == 2) // 1a, 1b

        tree.complete(waveId: "1a")
        tree.complete(waveId: "1b")
        let ready1 = tree.readyWaves(completed: ["1a", "1b"])
        #expect(ready1.count == 1)
        #expect(ready1[0].id == "2a")
    }

    @Test("PipelineRunner all pass")
    func pipelineAllPass() async throws {
        struct PassGate: PipelineGate {
            let name: String
            let index: Int
            func evaluate(context: PipelineContext) async throws -> PipelineGateResult { .pass(detail: "ok") }
        }
        struct MockCtx: PipelineContext {
            let isDryRun = false
            let featureId = "test"
            let projectRoot = URL(fileURLWithPath: "/tmp")
            func shell(_ command: String) async throws -> PipelineShellResult {
                PipelineShellResult(stdout: "", stderr: "", exitCode: 0)
            }
        }

        let runner = PipelineRunner()
        let result = try await runner.run(gates: [PassGate(name: "A", index: 0), PassGate(name: "B", index: 1)], context: MockCtx())
        #expect(result.success)
        #expect(result.gateResults.count == 2)
    }

    @Test("PipelineRunner aborts on failure")
    func pipelineAbortOnFail() async throws {
        struct PassGate: PipelineGate {
            let name: String
            let index: Int
            func evaluate(context: PipelineContext) async throws -> PipelineGateResult { .pass(detail: "ok") }
        }
        struct FailGate: PipelineGate {
            let name: String
            let index: Int
            func evaluate(context: PipelineContext) async throws -> PipelineGateResult { .fail(reason: "nope") }
        }
        struct MockCtx: PipelineContext {
            let isDryRun = false
            let featureId = "test"
            let projectRoot = URL(fileURLWithPath: "/tmp")
            func shell(_ command: String) async throws -> PipelineShellResult {
                PipelineShellResult(stdout: "", stderr: "", exitCode: 0)
            }
        }

        let runner = PipelineRunner()
        let result = try await runner.run(
            gates: [PassGate(name: "A", index: 0), FailGate(name: "B", index: 1), PassGate(name: "C", index: 2)],
            context: MockCtx()
        )
        #expect(!result.success)
        #expect(result.failedGate == "B")
        #expect(result.gateResults.count == 2) // C never ran
    }
}
