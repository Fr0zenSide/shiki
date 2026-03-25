import Foundation

// MARK: - CodeGenContext Protocol

/// Injected context for the code generation pipeline — follows ShipContext pattern.
///
/// Provides shell execution, event emission, and pipeline configuration.
/// Implementations: ``RealCodeGenContext``, ``DryRunCodeGenContext``, mock for tests.
public protocol CodeGenContext: Sendable {
    var isDryRun: Bool { get }
    var projectRoot: URL { get }
    var baseBranch: String { get }
    var verbose: Bool { get }
    func shell(_ command: String) async throws -> ShellResult
    func emit(_ event: ShikkiEvent) async
}

// MARK: - CodeGenerationPipeline Protocol

/// The formal pipeline protocol composing all CodeGen engines.
///
/// Each method maps to a pipeline stage. The pipeline orchestrates them in sequence,
/// emitting ShikkiEvents at every milestone for observability.
///
/// Language-agnostic by design: ProtocolLayer, WorkUnit, ContractResult are universal.
/// Language-specific logic lives in SpecParser/ProjectAnalyzer implementations.
public protocol CodeGenerationPipeline: Sendable {
    func parseSpec(at path: String) async throws -> ProtocolLayer
    func verifyContracts(_ layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> ContractResult
    func planWork(_ layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> WorkPlan
    func dispatch(_ plan: WorkPlan, layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> DispatchResult
    func merge(_ result: DispatchResult, plan: WorkPlan) async throws -> MergeResult
    func fix(_ failures: [TestFailure], layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> FixResult
    func updateCache(projectPath: String) async throws -> ArchitectureCache
}

// MARK: - Pipeline Stage

/// Named stages for progress tracking and event emission.
public enum CodeGenStage: String, Sendable, Codable {
    case parsing
    case verifying
    case planning
    case dispatching
    case merging
    case fixing
    case caching
    case done
}

// MARK: - Pipeline Result

/// Complete result of a code generation pipeline run.
public struct CodeGenPipelineResult: Sendable {
    public let featureName: String
    public let stage: CodeGenStage
    public let protocolLayer: ProtocolLayer?
    public let contractResult: ContractResult?
    public let workPlan: WorkPlan?
    public let dispatchResult: DispatchResult?
    public let mergeResult: MergeResult?
    public let fixResult: FixResult?
    public let updatedCache: ArchitectureCache?
    public let success: Bool
    public let failureReason: String?
    public let durationSeconds: Int

    public init(
        featureName: String = "",
        stage: CodeGenStage = .done,
        protocolLayer: ProtocolLayer? = nil,
        contractResult: ContractResult? = nil,
        workPlan: WorkPlan? = nil,
        dispatchResult: DispatchResult? = nil,
        mergeResult: MergeResult? = nil,
        fixResult: FixResult? = nil,
        updatedCache: ArchitectureCache? = nil,
        success: Bool = false,
        failureReason: String? = nil,
        durationSeconds: Int = 0
    ) {
        self.featureName = featureName
        self.stage = stage
        self.protocolLayer = protocolLayer
        self.contractResult = contractResult
        self.workPlan = workPlan
        self.dispatchResult = dispatchResult
        self.mergeResult = mergeResult
        self.fixResult = fixResult
        self.updatedCache = updatedCache
        self.success = success
        self.failureReason = failureReason
        self.durationSeconds = durationSeconds
    }
}

// MARK: - ShikkiCodeGenPipeline (Composed Implementation)

/// The default implementation composing all CodeGen engines into a single pipeline.
///
/// Follows ShipGate pattern: each stage is atomic, testable, and emits events.
/// The pipeline is the `building` stage of FeatureLifecycle.
public struct ShikkiCodeGenPipeline: CodeGenerationPipeline, Sendable {

    private let context: CodeGenContext
    private let agentRunner: AgentRunner

    public init(context: CodeGenContext, agentRunner: AgentRunner) {
        self.context = context
        self.agentRunner = agentRunner
    }

    // MARK: - Pipeline Stages

    public func parseSpec(at path: String) async throws -> ProtocolLayer {
        await context.emit(makeEvent(.codeGenSpecParsed, payload: ["spec_path": .string(path)]))
        let parser = SpecParser()
        return try parser.parse(specPath: path)
    }

    public func verifyContracts(_ layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> ContractResult {
        let verifier = ContractVerifier()
        let result: ContractResult
        if let cache {
            result = verifier.verifyAgainstCache(layer, cache: cache)
        } else {
            result = verifier.verify(layer)
        }

        await context.emit(makeEvent(.codeGenContractVerified, payload: [
            "valid": .bool(result.isValid),
            "issues": .int(result.issues.count),
            "warnings": .int(result.warnings.count),
            "duration_ms": .int(result.durationMs),
        ]))

        return result
    }

    public func planWork(_ layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> WorkPlan {
        let planner = WorkUnitPlanner()
        let plan = planner.plan(layer, cache: cache, baseBranch: context.baseBranch)

        await context.emit(makeEvent(.codeGenPlanCreated, payload: [
            "strategy": .string(plan.strategy.rawValue),
            "units": .int(plan.units.count),
            "rationale": .string(plan.rationale),
        ]))

        return plan
    }

    public func dispatch(_ plan: WorkPlan, layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> DispatchResult {
        let engine = DispatchEngine(
            projectRoot: context.projectRoot.path,
            agentRunner: agentRunner
        )

        let result = try await engine.dispatch(
            plan: plan,
            layer: layer,
            cache: cache,
            baseBranch: context.baseBranch
        ) { [context] event in
            switch event {
            case .unitStarted(let id, let desc):
                Task {
                    await context.emit(makeEvent(.codeGenAgentDispatched, payload: [
                        "unit_id": .string(id),
                        "description": .string(desc),
                    ]))
                }
            case .unitCompleted(let id, let status):
                Task {
                    await context.emit(makeEvent(.codeGenAgentCompleted, payload: [
                        "unit_id": .string(id),
                        "status": .string(status.rawValue),
                    ]))
                }
            case .phase:
                break
            }
        }

        return result
    }

    public func merge(_ result: DispatchResult, plan: WorkPlan) async throws -> MergeResult {
        await context.emit(makeEvent(.codeGenMergeStarted, payload: [
            "branches": .int(result.successCount),
        ]))

        let worktreeManager = WorktreeManager(projectRoot: context.projectRoot.path)
        let worktrees = try await worktreeManager.createAll(for: plan, baseBranch: context.baseBranch)

        let mergeEngine = MergeEngine(projectRoot: context.projectRoot.path)
        let mergeResult = try await mergeEngine.merge(
            dispatchResult: result,
            worktrees: worktrees,
            plan: plan,
            baseBranch: context.baseBranch
        )

        await worktreeManager.removeAll(worktrees)

        await context.emit(makeEvent(.codeGenMergeCompleted, payload: [
            "clean": .bool(mergeResult.isClean),
            "merged": .int(mergeResult.mergedBranches.count),
            "conflicts": .int(mergeResult.conflicts.count),
            "test_failures": .int(mergeResult.testFailures.count),
        ]))

        return mergeResult
    }

    public func fix(_ failures: [TestFailure], layer: ProtocolLayer, cache: ArchitectureCache?) async throws -> FixResult {
        await context.emit(makeEvent(.codeGenFixStarted, payload: [
            "failure_count": .int(failures.count),
        ]))

        let fixEngine = FixEngine(
            projectRoot: context.projectRoot.path,
            agentRunner: agentRunner
        )

        let result = try await fixEngine.fix(
            failures: failures,
            layer: layer,
            cache: cache
        )

        await context.emit(makeEvent(.codeGenFixCompleted, payload: [
            "passed": .bool(result.finallyPassed),
            "iterations": .int(result.iterations.count),
            "total_fixed": .int(result.totalFixedCount),
            "remaining": .int(result.remainingFailures.count),
        ]))

        return result
    }

    public func updateCache(projectPath: String) async throws -> ArchitectureCache {
        let analyzer = ProjectAnalyzer()
        let cache = try await analyzer.analyze(projectPath: projectPath)
        let store = CacheStore()
        try store.save(cache)
        return cache
    }

    // MARK: - Full Pipeline Run

    /// Execute the complete pipeline: parse → verify → plan → dispatch → merge → fix → cache.
    public func run(specPath: String) async throws -> CodeGenPipelineResult {
        let start = Date()
        let projectPath = context.projectRoot.path

        await context.emit(makeEvent(.codeGenStarted, payload: [
            "spec_path": .string(specPath),
            "project": .string(projectPath),
            "dry_run": .bool(context.isDryRun),
        ]))

        // Load existing cache
        let cacheStore = CacheStore()
        let projectId = context.projectRoot.lastPathComponent
        let existingCache = try? cacheStore.load(projectId: projectId)

        // Stage 1: Parse
        let layer = try await parseSpec(at: specPath)

        // Stage 2: Verify
        let contractResult = try await verifyContracts(layer, cache: existingCache)
        guard contractResult.isValid else {
            let reason = contractResult.issues.joined(separator: "\n")
            await emitPipelineFailed(reason: reason)
            return CodeGenPipelineResult(
                featureName: layer.featureName,
                stage: .verifying,
                protocolLayer: layer,
                contractResult: contractResult,
                success: false,
                failureReason: reason,
                durationSeconds: elapsed(since: start)
            )
        }

        // Stage 3: Plan
        let plan = try await planWork(layer, cache: existingCache)

        if context.isDryRun {
            await emitPipelineCompleted(feature: layer.featureName)
            return CodeGenPipelineResult(
                featureName: layer.featureName,
                stage: .planning,
                protocolLayer: layer,
                contractResult: contractResult,
                workPlan: plan,
                success: true,
                durationSeconds: elapsed(since: start)
            )
        }

        // Stage 4: Dispatch
        let dispatchResult = try await dispatch(plan, layer: layer, cache: existingCache)

        // Stage 5: Merge (parallel strategies only)
        var mergeResult: MergeResult?
        if plan.strategy != .sequential {
            mergeResult = try await merge(dispatchResult, plan: plan)
        }

        // Stage 6: Fix (if tests failed)
        var fixResult: FixResult?
        let testFailures = mergeResult?.testFailures ?? []
        if !testFailures.isEmpty {
            fixResult = try await fix(testFailures, layer: layer, cache: existingCache)
        }

        // Stage 7: Update cache
        let updatedCache = try await updateCache(projectPath: projectPath)

        let success = (mergeResult?.isClean ?? true) && (fixResult?.finallyPassed ?? true)

        if success {
            await emitPipelineCompleted(feature: layer.featureName)
        } else {
            await emitPipelineFailed(reason: "Tests still failing after fix loop")
        }

        return CodeGenPipelineResult(
            featureName: layer.featureName,
            stage: .done,
            protocolLayer: layer,
            contractResult: contractResult,
            workPlan: plan,
            dispatchResult: dispatchResult,
            mergeResult: mergeResult,
            fixResult: fixResult,
            updatedCache: updatedCache,
            success: success,
            durationSeconds: elapsed(since: start)
        )
    }

    // MARK: - Event Helpers

    private func emitPipelineCompleted(feature: String) async {
        await context.emit(makeEvent(.codeGenPipelineCompleted, payload: [
            "feature": .string(feature),
        ]))
    }

    private func emitPipelineFailed(reason: String) async {
        await context.emit(makeEvent(.codeGenPipelineFailed, payload: [
            "reason": .string(reason),
        ]))
    }

    private func elapsed(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start))
    }
}

// MARK: - Event Factory

/// Create a CodeGen ShikkiEvent with standard source and scope.
func makeEvent(_ type: EventType, payload: [String: EventValue] = [:]) -> ShikkiEvent {
    ShikkiEvent(
        source: .process(name: "codegen"),
        type: type,
        scope: .global,
        payload: payload
    )
}

// MARK: - RealCodeGenContext

/// Real context — executes shell commands and emits to event bus.
public final class RealCodeGenContext: CodeGenContext, @unchecked Sendable {
    public let isDryRun = false
    public let projectRoot: URL
    public let baseBranch: String
    public let verbose: Bool
    private let eventBus: InProcessEventBus?

    public init(
        projectRoot: URL,
        baseBranch: String = "HEAD",
        verbose: Bool = false,
        eventBus: InProcessEventBus? = nil
    ) {
        self.projectRoot = projectRoot
        self.baseBranch = baseBranch
        self.verbose = verbose
        self.eventBus = eventBus
    }

    public func shell(_ command: String) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = projectRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ShellResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    public func emit(_ event: ShikkiEvent) async {
        await eventBus?.publish(event)
    }
}

// MARK: - DryRunCodeGenContext

/// Dry-run context — captures commands, doesn't execute agents.
public actor DryRunCodeGenContext: CodeGenContext {
    public let isDryRun = true
    public let projectRoot: URL
    public let baseBranch: String
    public let verbose: Bool
    private let eventBus: InProcessEventBus?
    private var _capturedCommands: [String] = []

    public var capturedCommands: [String] { _capturedCommands }

    public init(
        projectRoot: URL,
        baseBranch: String = "HEAD",
        verbose: Bool = false,
        eventBus: InProcessEventBus? = nil
    ) {
        self.projectRoot = projectRoot
        self.baseBranch = baseBranch
        self.verbose = verbose
        self.eventBus = eventBus
    }

    public func shell(_ command: String) async throws -> ShellResult {
        _capturedCommands.append(command)
        return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }

    public func emit(_ event: ShikkiEvent) async {
        await eventBus?.publish(event)
    }
}
