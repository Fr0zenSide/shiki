import ArgumentParser
import Foundation
import ShikkiKit

/// The main CodeGen pipeline command.
///
/// Full flow: spec → parse → verify → plan → dispatch → merge → test → fix → done.
///
/// Usage:
///   shi wave --spec features/payment.md
///   shi wave --spec features/payment.md --dry-run
///   shi wave --resume --fix-red
struct WaveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wave",
        abstract: "AI code production engine — spec to feature in one command."
    )

    @Option(name: .long, help: "Path to the feature spec / TDDP markdown file.")
    var spec: String?

    @Option(name: .long, help: "Project path to generate code in (default: current directory).")
    var project: String?

    @Option(name: .long, help: "Base branch for worktrees (default: HEAD).")
    var base: String = "HEAD"

    @Flag(name: .long, help: "Show the plan without executing.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Skip contract verification.")
    var skipVerify: Bool = false

    @Flag(name: .long, help: "Resume and fix red tests from a previous run.")
    var fixRed: Bool = false

    @Flag(name: .long, help: "Verbose output with full prompts.")
    var verbose: Bool = false

    func run() async throws {
        let projectPath = project ?? FileManager.default.currentDirectoryPath

        if fixRed {
            try await runFixMode(projectPath: projectPath)
            return
        }

        guard let specPath = spec else {
            print("[wave] Error: --spec is required (or use --fix-red to fix existing failures)")
            throw ExitCode(1)
        }

        let resolvedSpec = specPath.hasPrefix("/")
            ? specPath
            : "\(FileManager.default.currentDirectoryPath)/\(specPath)"

        try await runFullPipeline(specPath: resolvedSpec, projectPath: projectPath)
    }

    // MARK: - Full Pipeline

    func runFullPipeline(specPath: String, projectPath: String) async throws {
        // Phase 1: Parse
        print("[wave] Parsing spec: \(specPath)")
        let parser = SpecParser()
        let layer = try parser.parse(specPath: specPath)
        print("[wave] Feature: \(layer.featureName)")
        print("[wave]   Protocols: \(layer.protocols.count)")
        print("[wave]   Types: \(layer.types.count)")
        print("[wave]   Files: \(layer.fileSpecs.count)")

        // Phase 2: Verify
        if !skipVerify {
            print("[wave] Verifying contracts...")
            let verifier = ContractVerifier()

            // Try to load architecture cache for deeper verification
            let cacheStore = CacheStore()
            let projectId = URL(fileURLWithPath: projectPath).lastPathComponent
            let cache = try? cacheStore.load(projectId: projectId)

            let result: ContractResult
            if let cache {
                result = verifier.verifyAgainstCache(layer, cache: cache)
            } else {
                result = verifier.verify(layer)
            }

            if !result.isValid {
                print("[wave] Contract verification FAILED:")
                for issue in result.issues {
                    print("  [error] \(issue)")
                }
                throw ExitCode(1)
            }

            for warning in result.warnings {
                print("  [warn] \(warning)")
            }
            print("[wave] Contracts verified (\(result.durationMs)ms)")
        }

        // Phase 3: Plan
        print("[wave] Planning work units...")
        let planner = WorkUnitPlanner()
        let cacheStore = CacheStore()
        let projectId = URL(fileURLWithPath: projectPath).lastPathComponent
        let cache = try? cacheStore.load(projectId: projectId)
        let plan = planner.plan(layer, cache: cache, baseBranch: base)

        print("[wave] Strategy: \(plan.strategy.rawValue)")
        print("[wave] Work units: \(plan.units.count)")
        for unit in plan.units {
            print("  [\(unit.priority)] \(unit.id) — \(unit.description) (\(unit.files.count) files)")
        }
        print("[wave] Rationale: \(plan.rationale)")

        if dryRun {
            print("[wave] Dry run — stopping before dispatch.")

            if verbose {
                let generator = AgentPromptGenerator()
                for unit in plan.units {
                    print("\n--- Prompt for \(unit.id) ---")
                    let prompt = plan.strategy == .sequential
                        ? generator.generateCompact(for: unit, layer: layer, cache: cache)
                        : generator.generate(for: unit, layer: layer, cache: cache)
                    print(prompt)
                }
            }
            return
        }

        // Phase 4: Dispatch
        print("[wave] Dispatching agents...")
        let runner = CLIAgentRunner()
        let engine = DispatchEngine(projectRoot: projectPath, agentRunner: runner)

        let dispatchResult = try await engine.dispatch(
            plan: plan,
            layer: layer,
            cache: cache,
            baseBranch: base
        ) { event in
            switch event {
            case .phase(let name):
                print("[wave] \(name)")
            case .unitStarted(let id, let desc):
                print("[wave] Started: \(id) — \(desc)")
            case .unitCompleted(let id, let status):
                let icon = status == .completed ? "done" : "FAIL"
                print("[wave] [\(icon)] \(id)")
            }
        }

        print("[wave] Dispatch complete: \(dispatchResult.successCount)/\(dispatchResult.agentResults.count) succeeded")

        // Phase 5: Merge + Test (for parallel strategies)
        if plan.strategy != .sequential {
            print("[wave] Merging branches...")
            let worktreeManager = WorktreeManager(projectRoot: projectPath)
            let worktrees = try await worktreeManager.createAll(for: plan, baseBranch: base)

            let mergeEngine = MergeEngine(projectRoot: projectPath)
            let mergeResult = try await mergeEngine.merge(
                dispatchResult: dispatchResult,
                worktrees: worktrees,
                plan: plan,
                baseBranch: base
            )

            if mergeResult.isClean {
                print("[wave] Merge clean — all tests pass")
            } else {
                if !mergeResult.conflicts.isEmpty {
                    print("[wave] Conflicts: \(mergeResult.conflicts.joined(separator: ", "))")
                }
                if !mergeResult.testFailures.isEmpty {
                    print("[wave] Test failures: \(mergeResult.testFailures.count)")
                    try await runFixLoop(
                        failures: mergeResult.testFailures,
                        layer: layer,
                        cache: cache,
                        projectPath: projectPath
                    )
                }
            }

            // Cleanup worktrees
            await worktreeManager.removeAll(worktrees)
        } else if !dispatchResult.allSucceeded {
            // Sequential mode — run tests to check
            let mergeEngine = MergeEngine(projectRoot: projectPath)
            let testResult = try await mergeEngine.runTests()
            if !testResult.passed {
                print("[wave] Tests failed after sequential dispatch — entering fix loop")
                try await runFixLoop(
                    failures: testResult.failures,
                    layer: layer,
                    cache: cache,
                    projectPath: projectPath
                )
            }
        }

        // Phase 6: Update architecture cache
        print("[wave] Updating architecture cache...")
        let analyzer = ProjectAnalyzer()
        let newCache = try await analyzer.analyze(projectPath: projectPath)
        try cacheStore.save(newCache)
        print("[wave] Cache updated (\(newCache.protocols.count) protocols, \(newCache.types.count) types)")

        print("[wave] Done.")
    }

    // MARK: - Fix Mode

    func runFixMode(projectPath: String) async throws {
        print("[wave] Running tests to find failures...")
        let mergeEngine = MergeEngine(projectRoot: projectPath)
        let testResult = try await mergeEngine.runTests()

        if testResult.passed {
            print("[wave] All tests pass — nothing to fix.")
            return
        }

        print("[wave] Found \(testResult.failures.count) failures")

        let cacheStore = CacheStore()
        let projectId = URL(fileURLWithPath: projectPath).lastPathComponent
        let cache = try? cacheStore.load(projectId: projectId)

        try await runFixLoop(
            failures: testResult.failures,
            layer: ProtocolLayer(),
            cache: cache,
            projectPath: projectPath
        )
    }

    func runFixLoop(
        failures: [TestFailure],
        layer: ProtocolLayer,
        cache: ArchitectureCache?,
        projectPath: String
    ) async throws {
        let runner = CLIAgentRunner()
        let fixEngine = FixEngine(projectRoot: projectPath, agentRunner: runner)

        let result = try await fixEngine.fix(
            failures: failures,
            layer: layer,
            cache: cache
        ) { event in
            switch event {
            case .iterationStarted(let iter, let count):
                print("[fix] Iteration \(iter) — \(count) failures to fix")
            case .iterationCompleted(let iter, let fixed, let remaining):
                print("[fix] Iteration \(iter) done: fixed \(fixed), remaining \(remaining)")
            case .noProgress(let iter):
                print("[fix] No progress in iteration \(iter) — stopping")
            case .regression(let iter, let delta):
                print("[fix] Regression in iteration \(iter): \(abs(delta)) more failures — rolling back")
            case .contractViolation(let iter, let issues):
                print("[fix] Contract violation in iteration \(iter): \(issues.joined(separator: ", ")) — rolling back")
            case .testFileModification(let iter, let files):
                print("[fix] Test files modified in iteration \(iter): \(files.joined(separator: ", ")) — rolling back")
            case .exhausted(let remaining):
                print("[fix] All iterations exhausted, \(remaining.count) failures remain")
            case .timedOut(let iter):
                print("[fix] Iteration \(iter) timed out — rolling back")
            }
        }

        if result.finallyPassed {
            print("[wave] All tests pass after \(result.iterations.count) fix iterations")
        } else {
            print("[wave] \(result.remainingFailures.count) failures remain after \(result.iterations.count) iterations")
            print("[wave] Developer intervention needed. Failures:")
            for failure in result.remainingFailures {
                print("  - \(failure.testName) at \(failure.file)")
            }
            throw ExitCode(1)
        }
    }
}
