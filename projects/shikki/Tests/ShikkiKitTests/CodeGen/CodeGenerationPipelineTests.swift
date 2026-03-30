import Testing
import Foundation
@testable import ShikkiKit

// MARK: - Mock CodeGen Context

actor MockCodeGenContext: CodeGenContext {
    let isDryRun: Bool
    let projectRoot: URL
    let baseBranch: String
    let verbose: Bool

    private var _emittedEvents: [ShikkiEvent] = []
    private var _shellCommands: [String] = []

    var emittedEvents: [ShikkiEvent] { _emittedEvents }
    var shellCommands: [String] { _shellCommands }

    init(isDryRun: Bool = false, projectRoot: URL = URL(fileURLWithPath: "/tmp/test"), baseBranch: String = "HEAD") {
        self.isDryRun = isDryRun
        self.projectRoot = projectRoot
        self.baseBranch = baseBranch
        self.verbose = false
    }

    func shell(_ command: String) async throws -> ShellResult {
        _shellCommands.append(command)
        return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }

    func emit(_ event: ShikkiEvent) async {
        _emittedEvents.append(event)
    }
}

// MARK: - Mock Agent Runner for Pipeline

final class PipelineMockRunner: AgentRunner, @unchecked Sendable {
    var runCount = 0

    func run(prompt: String, workingDirectory: String, unitId: String) async throws -> AgentResult {
        runCount += 1
        return AgentResult(unitId: unitId, status: .completed, durationSeconds: 1)
    }
}

// MARK: - Tests

@Suite("CodeGenerationPipeline")
struct CodeGenerationPipelineTests {

    // MARK: - Protocol Conformance

    @Test("ShikkiCodeGenPipeline conforms to CodeGenerationPipeline")
    func conformance() {
        let ctx = MockCodeGenContext()
        let runner = PipelineMockRunner()
        let pipeline: any CodeGenerationPipeline = ShikkiCodeGenPipeline(context: ctx, agentRunner: runner)
        _ = pipeline // Compiles = conforms
    }

    // MARK: - Parse Stage

    @Test("parseSpec emits event and returns ProtocolLayer")
    func parseStage() async throws {
        let ctx = MockCodeGenContext()
        let runner = PipelineMockRunner()
        let pipeline = ShikkiCodeGenPipeline(context: ctx, agentRunner: runner)

        // Create temp spec file
        let specContent = """
        # Test Feature
        module: TestModule

        ```swift
        protocol FooProvider: Sendable {
            func doStuff() async throws
        }
        ```
        """
        let tempPath = NSTemporaryDirectory() + "test-spec-\(UUID().uuidString).md"
        try specContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let layer = try await pipeline.parseSpec(at: tempPath)
        #expect(layer.featureName == "Test Feature")
        #expect(layer.protocols.count == 1)

        // Should have emitted specParsed event
        let eventTypes = await ctx.emittedEvents.map(\.type)
        #expect(eventTypes.contains(.codeGenSpecParsed))
    }

    // MARK: - Verify Stage

    @Test("verifyContracts emits event with result")
    func verifyStage() async throws {
        let ctx = MockCodeGenContext()
        let runner = PipelineMockRunner()
        let pipeline = ShikkiCodeGenPipeline(context: ctx, agentRunner: runner)

        let layer = ProtocolLayer(
            featureName: "Test",
            protocols: [ProtocolSpec(name: "Foo", methods: ["func bar()"])]
        )

        let result = try await pipeline.verifyContracts(layer, cache: nil)
        #expect(result.isValid)

        let eventTypes = await ctx.emittedEvents.map(\.type)
        #expect(eventTypes.contains(.codeGenContractVerified))

        // Check payload
        let verifyEvent = await ctx.emittedEvents.first { $0.type == .codeGenContractVerified }
        #expect(verifyEvent?.payload["valid"] == .bool(true))
    }

    @Test("verifyContracts reports failures via event")
    func verifyFailure() async throws {
        let ctx = MockCodeGenContext()
        let runner = PipelineMockRunner()
        let pipeline = ShikkiCodeGenPipeline(context: ctx, agentRunner: runner)

        let layer = ProtocolLayer(
            protocols: [ProtocolSpec(name: "Dup"), ProtocolSpec(name: "Dup")]
        )

        let result = try await pipeline.verifyContracts(layer, cache: nil)
        #expect(!result.isValid)

        let verifyEvent = await ctx.emittedEvents.first { $0.type == .codeGenContractVerified }
        #expect(verifyEvent?.payload["valid"] == .bool(false))
        #expect(verifyEvent?.payload["issues"] == .int(1))
    }

    // MARK: - Plan Stage

    @Test("planWork emits event with strategy")
    func planStage() async throws {
        let ctx = MockCodeGenContext()
        let runner = PipelineMockRunner()
        let pipeline = ShikkiCodeGenPipeline(context: ctx, agentRunner: runner)

        let layer = ProtocolLayer(
            featureName: "Small",
            protocols: [ProtocolSpec(name: "P", targetFile: "p.swift")],
            types: [TypeSpec(name: "T", targetFile: "t.swift")]
        )

        let plan = try await pipeline.planWork(layer, cache: nil)
        #expect(plan.strategy == .sequential)

        let planEvent = await ctx.emittedEvents.first { $0.type == .codeGenPlanCreated }
        #expect(planEvent?.payload["strategy"] == .string("sequential"))
        #expect(planEvent?.payload["units"] == .int(1))
    }

    // MARK: - Event Source

    @Test("all events have process:codegen source")
    func eventSource() async throws {
        let ctx = MockCodeGenContext()
        let runner = PipelineMockRunner()
        let pipeline = ShikkiCodeGenPipeline(context: ctx, agentRunner: runner)

        let layer = ProtocolLayer(
            featureName: "Test",
            protocols: [ProtocolSpec(name: "P", methods: ["func x()"])]
        )
        _ = try await pipeline.verifyContracts(layer, cache: nil)

        for event in await ctx.emittedEvents {
            if case .process(let name) = event.source {
                #expect(name == "codegen")
            } else {
                Issue.record("Event source should be .process(codegen), got \(event.source)")
            }
        }
    }

    // MARK: - Pipeline Result

    @Test("pipeline result tracks all stages")
    func pipelineResult() {
        let result = CodeGenPipelineResult(
            featureName: "Payment",
            stage: .done,
            protocolLayer: ProtocolLayer(featureName: "Payment"),
            contractResult: ContractResult(isValid: true),
            workPlan: WorkPlan(units: [WorkUnit(id: "u1")], strategy: .sequential),
            success: true,
            durationSeconds: 42
        )

        #expect(result.featureName == "Payment")
        #expect(result.success)
        #expect(result.stage == .done)
        #expect(result.durationSeconds == 42)
        #expect(result.protocolLayer != nil)
        #expect(result.contractResult != nil)
        #expect(result.workPlan != nil)
    }

    @Test("failed pipeline result captures reason")
    func failedResult() {
        let result = CodeGenPipelineResult(
            featureName: "Broken",
            stage: .verifying,
            success: false,
            failureReason: "Duplicate protocol: Widget"
        )

        #expect(!result.success)
        #expect(result.stage == .verifying)
        #expect(result.failureReason?.contains("Widget") == true)
    }

    // MARK: - CodeGen Stages

    @Test("all stages are defined")
    func allStages() {
        let stages: [CodeGenStage] = [.parsing, .verifying, .planning, .dispatching, .merging, .fixing, .caching, .done]
        #expect(stages.count == 8)
    }

    // MARK: - Context Implementations

    @Test("DryRunCodeGenContext captures commands without executing")
    func dryRunContext() async {
        let ctx = DryRunCodeGenContext(projectRoot: URL(fileURLWithPath: "/tmp"))
        let result = try? await ctx.shell("echo hello")
        #expect(result?.exitCode == 0)
        #expect(result?.stdout == "")
        let commands = await ctx.capturedCommands
        #expect(commands == ["echo hello"])
    }

    @Test("MockCodeGenContext tracks emitted events")
    func mockContextEvents() async {
        let ctx = MockCodeGenContext()
        await ctx.emit(ShikkiEvent(source: .system, type: .codeGenStarted, scope: .global))
        await ctx.emit(ShikkiEvent(source: .system, type: .codeGenPipelineCompleted, scope: .global))

        #expect(await ctx.emittedEvents.count == 2)
        #expect(await ctx.emittedEvents[0].type == .codeGenStarted)
        #expect(await ctx.emittedEvents[1].type == .codeGenPipelineCompleted)
    }

    // MARK: - Event Types

    @Test("CodeGen event types exist on EventType")
    func codeGenEventTypes() {
        let types: [EventType] = [
            .codeGenStarted,
            .codeGenSpecParsed,
            .codeGenContractVerified,
            .codeGenPlanCreated,
            .codeGenAgentDispatched,
            .codeGenAgentCompleted,
            .codeGenMergeStarted,
            .codeGenMergeCompleted,
            .codeGenFixStarted,
            .codeGenFixCompleted,
            .codeGenPipelineCompleted,
            .codeGenPipelineFailed,
        ]
        #expect(types.count == 12)
    }
}
