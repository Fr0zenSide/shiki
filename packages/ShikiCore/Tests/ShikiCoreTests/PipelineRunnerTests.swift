import Testing
import Foundation
@testable import ShikiCore

@Suite("PipelineRunner")
struct PipelineRunnerTests {

    // MARK: - Helpers

    struct PassGate: PipelineGate {
        let name: String
        let index: Int
        func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
            .pass(detail: "ok")
        }
    }

    struct WarnGate: PipelineGate {
        let name: String
        let index: Int
        func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
            .warn(reason: "heads up")
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

    actor SpyPersister: EventPersisting {
        var events: [LifecycleEventPayload] = []
        func persist(_ event: LifecycleEventPayload) async {
            events.append(event)
        }
    }

    // MARK: - Tests

    @Test("Executes all gates in order when all pass")
    func allGatesPass() async throws {
        let runner = PipelineRunner()
        let gates: [PipelineGate] = [
            PassGate(name: "A", index: 0),
            PassGate(name: "B", index: 1),
            WarnGate(name: "C", index: 2),
        ]
        let result = try await runner.run(gates: gates, context: FakeContext())
        #expect(result.success)
        #expect(result.gateResults.count == 3)
        #expect(result.failedGate == nil)
    }

    @Test("Aborts on first failure")
    func abortsOnFailure() async throws {
        let runner = PipelineRunner()
        let gates: [PipelineGate] = [
            PassGate(name: "A", index: 0),
            FailGate(name: "B", index: 1),
            PassGate(name: "C", index: 2),
        ]
        let result = try await runner.run(gates: gates, context: FakeContext())
        #expect(!result.success)
        #expect(result.gateResults.count == 2)
        #expect(result.failedGate == "B")
    }

    @Test("Records duration per gate")
    func recordsDuration() async throws {
        let runner = PipelineRunner()
        let gates: [PipelineGate] = [PassGate(name: "A", index: 0)]
        let result = try await runner.run(gates: gates, context: FakeContext())
        #expect(result.gateResults[0].duration >= .zero)
    }

    @Test("Persists events when persister available")
    func persistsEvents() async throws {
        let spy = SpyPersister()
        let runner = PipelineRunner(persister: spy)
        let gates: [PipelineGate] = [
            PassGate(name: "A", index: 0),
            PassGate(name: "B", index: 1),
        ]
        _ = try await runner.run(gates: gates, context: FakeContext())
        let events = await spy.events
        #expect(events.count == 2)
    }

    @Test("Skips persistence gracefully when no persister")
    func noPersister() async throws {
        let runner = PipelineRunner()
        let gates: [PipelineGate] = [PassGate(name: "A", index: 0)]
        let result = try await runner.run(gates: gates, context: FakeContext())
        #expect(result.success)
    }

    // MARK: - Codable Tests (Fix 1: tuple -> struct)

    @Test("PipelineResult Codable round-trip preserves all fields")
    func pipelineResultCodableRoundTrip() async throws {
        let runner = PipelineRunner()
        let gates: [PipelineGate] = [
            PassGate(name: "Build", index: 0),
            WarnGate(name: "Coverage", index: 1),
        ]
        let original = try await runner.run(gates: gates, context: FakeContext())

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(PipelineResult.self, from: data)

        #expect(decoded.success == original.success)
        #expect(decoded.failedGate == original.failedGate)
        #expect(decoded.gateResults.count == original.gateResults.count)
        #expect(decoded.gateResults[0].gate == "Build")
        #expect(decoded.gateResults[1].gate == "Coverage")
        #expect(decoded.gateResults[0].result.passed)
        #expect(decoded.gateResults[1].result.passed) // warn still passes
    }

    @Test("GateEvaluation preserves duration through Codable")
    func gateEvaluationDurationPreservation() throws {
        let eval = GateEvaluation(
            gate: "TestGate",
            result: .pass(detail: "all green"),
            duration: .milliseconds(1234)
        )

        let data = try JSONEncoder().encode(eval)
        let decoded = try JSONDecoder().decode(GateEvaluation.self, from: data)

        #expect(decoded.gate == "TestGate")
        #expect(decoded.duration == .milliseconds(1234))
        #expect(decoded.result.passed)
    }

    @Test("PipelineResult with failure is Codable")
    func pipelineResultFailureCodable() async throws {
        let runner = PipelineRunner()
        let gates: [PipelineGate] = [
            PassGate(name: "A", index: 0),
            FailGate(name: "B", index: 1),
        ]
        let original = try await runner.run(gates: gates, context: FakeContext())

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PipelineResult.self, from: data)

        #expect(!decoded.success)
        #expect(decoded.failedGate == "B")
        #expect(decoded.gateResults.count == 2)
        #expect(!decoded.gateResults[1].result.passed)
    }
}
