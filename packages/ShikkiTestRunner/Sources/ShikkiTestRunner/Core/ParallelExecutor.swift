// ParallelExecutor.swift — Parallel scope dispatch using TaskGroup
// Part of ShikkiTestRunner

import Foundation

/// Configuration for parallel test execution.
public struct ExecutionConfig: Sendable {
    /// Maximum number of concurrent workers. Defaults to scope count, capped at CPU cores.
    public let maxWorkers: Int

    /// Stop all workers on first scope failure.
    public let failFast: Bool

    /// Working directory for `swift test` invocations.
    public let workingDirectory: String?

    /// Path to swift executable.
    public let swiftPath: String

    public init(
        maxWorkers: Int? = nil,
        failFast: Bool = false,
        workingDirectory: String? = nil,
        swiftPath: String = "/usr/bin/swift"
    ) {
        let cpuCores = ProcessInfo.processInfo.activeProcessorCount
        self.maxWorkers = min(maxWorkers ?? cpuCores, cpuCores)
        self.failFast = failFast
        self.workingDirectory = workingDirectory
        self.swiftPath = swiftPath
    }
}

/// Delegate protocol for receiving execution progress events.
public protocol ExecutionProgressDelegate: Sendable {
    func scopeStarted(_ scope: TestScope) async
    func scopeProgress(_ scope: TestScope, completed: Int, total: Int) async
    func scopeFinished(_ scope: TestScope, result: ScopeResult) async
}

/// Default no-op delegate.
public struct NoOpProgressDelegate: ExecutionProgressDelegate {
    public init() {}
    public func scopeStarted(_ scope: TestScope) async {}
    public func scopeProgress(_ scope: TestScope, completed: Int, total: Int) async {}
    public func scopeFinished(_ scope: TestScope, result: ScopeResult) async {}
}

/// Actor that dispatches scope groups to parallel workers using TaskGroup.
/// Each worker runs `swift test --parallel --filter <scope.filter>`.
public actor ParallelExecutor {
    private let config: ExecutionConfig
    private let processRunner: any ProcessRunner
    private let resultParser: ResultParser
    private let progressDelegate: any ExecutionProgressDelegate

    public init(
        config: ExecutionConfig = ExecutionConfig(),
        processRunner: any ProcessRunner = SystemProcessRunner(),
        resultParser: ResultParser = ResultParser(),
        progressDelegate: any ExecutionProgressDelegate = NoOpProgressDelegate()
    ) {
        self.config = config
        self.processRunner = processRunner
        self.resultParser = resultParser
        self.progressDelegate = progressDelegate
    }

    /// Execute all scopes in parallel, returning aggregated results.
    public func execute(scopes: [TestScope]) async throws -> [ScopeResult] {
        guard !scopes.isEmpty else { return [] }

        let workerCount = min(scopes.count, config.maxWorkers)
        let failFast = config.failFast

        // Use a semaphore-like pattern via a channel to limit concurrency
        return try await withThrowingTaskGroup(of: ScopeResult.self) { group in
            var results: [ScopeResult] = []
            results.reserveCapacity(scopes.count)

            var scopeIterator = scopes.makeIterator()
            var activeTasks = 0
            var cancelled = false

            // Seed initial batch up to workerCount
            for _ in 0..<workerCount {
                guard let scope = scopeIterator.next() else { break }
                group.addTask { [processRunner, config, resultParser, progressDelegate] in
                    await progressDelegate.scopeStarted(scope)
                    let result = await Self.runScope(
                        scope,
                        processRunner: processRunner,
                        config: config,
                        resultParser: resultParser,
                        progressDelegate: progressDelegate
                    )
                    await progressDelegate.scopeFinished(scope, result: result)
                    return result
                }
                activeTasks += 1
            }

            // Collect results and schedule remaining scopes
            while activeTasks > 0 {
                let result = try await group.next()!
                activeTasks -= 1
                results.append(result)

                // Check fail-fast condition
                if failFast && result.failureCount > 0 {
                    cancelled = true
                    group.cancelAll()
                    break
                }

                // Schedule next scope if available
                if !cancelled, let scope = scopeIterator.next() {
                    group.addTask { [processRunner, config, resultParser, progressDelegate] in
                        await progressDelegate.scopeStarted(scope)
                        let result = await Self.runScope(
                            scope,
                            processRunner: processRunner,
                            config: config,
                            resultParser: resultParser,
                            progressDelegate: progressDelegate
                        )
                        await progressDelegate.scopeFinished(scope, result: result)
                        return result
                    }
                    activeTasks += 1
                }
            }

            return results
        }
    }

    /// Run a single scope via `swift test --parallel --filter`.
    private static func runScope(
        _ scope: TestScope,
        processRunner: any ProcessRunner,
        config: ExecutionConfig,
        resultParser: ResultParser,
        progressDelegate: any ExecutionProgressDelegate
    ) async -> ScopeResult {
        let startedAt = Date()

        var arguments = [
            "test",
            "--parallel",
            "--filter", scope.filter
        ]

        // Add event stream output for structured parsing
        arguments.append("--experimental-event-stream-output")

        do {
            let output = try await processRunner.run(
                executable: config.swiftPath,
                arguments: arguments,
                workingDirectory: config.workingDirectory
            )

            let combinedOutput = output.stdout + output.stderr
            let testResults = resultParser.parse(
                output: combinedOutput,
                scope: scope
            )

            return ScopeResult(
                scope: scope,
                results: testResults,
                startedAt: startedAt,
                finishedAt: Date(),
                rawOutput: combinedOutput
            )
        } catch {
            // Process failed to launch or was interrupted
            return ScopeResult(
                scope: scope,
                results: [
                    TestCaseResult(
                        testName: "\(scope.name)/process_error",
                        suiteName: scope.name,
                        status: .failed,
                        errorMessage: error.localizedDescription
                    )
                ],
                startedAt: startedAt,
                finishedAt: Date(),
                rawOutput: "Process error: \(error.localizedDescription)"
            )
        }
    }
}
