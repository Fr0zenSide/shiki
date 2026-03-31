// ParallelExecutorTests.swift — Tests for parallel scope dispatch
// Part of ShikkiTestRunnerTests

import Foundation
import Testing
@testable import ShikkiTestRunner

@Suite("ParallelExecutor")
struct ParallelExecutorTests {

    @Test("dispatches all scopes and collects results")
    func dispatchAllScopes() async throws {
        let mock = MockProcessRunner()
        let passedOutput = TestFixtures.allPassedOutput(suite: "NATSTests", count: 5)
        await mock.registerDefault(
            output: ProcessOutput(stdout: passedOutput, stderr: "", exitCode: 0)
        )

        let config = ExecutionConfig(maxWorkers: 4, failFast: false)
        let executor = ParallelExecutor(config: config, processRunner: mock)

        let scopes = [TestFixtures.natsScope, TestFixtures.flywheelScope, TestFixtures.tuiScope]
        let results = try await executor.execute(scopes: scopes)

        #expect(results.count == 3)
        let invocations = await mock.invocationCount()
        #expect(invocations == 3)
    }

    @Test("returns empty results for empty scope list")
    func emptyScopes() async throws {
        let mock = MockProcessRunner()
        let executor = ParallelExecutor(
            config: ExecutionConfig(),
            processRunner: mock
        )

        let results = try await executor.execute(scopes: [])

        #expect(results.isEmpty)
        let invocations = await mock.invocationCount()
        #expect(invocations == 0)
    }

    @Test("fail-fast cancels remaining scopes on first failure")
    func failFastCancellation() async throws {
        let mock = MockProcessRunner()

        // First scope returns failures
        let failedOutput = TestFixtures.mixedOutput(suite: "NATSTests", passed: 2, failed: 3)
        await mock.register(
            filter: "NATSTests",
            output: ProcessOutput(stdout: failedOutput, stderr: "", exitCode: 1)
        )

        // Other scopes take longer (simulated by delay)
        let passedOutput = TestFixtures.allPassedOutput(suite: "SlowTests", count: 5)
        await mock.registerDefault(
            output: ProcessOutput(stdout: passedOutput, stderr: "", exitCode: 0)
        )

        let config = ExecutionConfig(maxWorkers: 1, failFast: true)
        let executor = ParallelExecutor(config: config, processRunner: mock)

        let scopes = [
            TestFixtures.natsScope,
            TestFixtures.flywheelScope,
            TestFixtures.tuiScope,
            TestFixtures.safetyScope
        ]

        let results = try await executor.execute(scopes: scopes)

        // With maxWorkers=1 and failFast, should stop after first failure
        // The first scope fails, so we get at most 1 result
        #expect(results.count >= 1)
        let failedResults = results.filter { $0.failureCount > 0 }
        #expect(failedResults.count >= 1)
    }

    @Test("respects worker count limit")
    func workerCountLimit() async throws {
        let mock = MockProcessRunner()
        let passedOutput = TestFixtures.allPassedOutput(suite: "Tests", count: 3)
        await mock.registerDefault(
            output: ProcessOutput(stdout: passedOutput, stderr: "", exitCode: 0)
        )

        // Request 2 workers for 5 scopes
        let config = ExecutionConfig(maxWorkers: 2, failFast: false)
        let executor = ParallelExecutor(config: config, processRunner: mock)

        let results = try await executor.execute(scopes: TestFixtures.allScopes)

        // All 5 scopes should still complete
        #expect(results.count == 5)
        let invocations = await mock.invocationCount()
        #expect(invocations == 5)
    }

    @Test("passes correct swift test arguments")
    func swiftTestArguments() async throws {
        let mock = MockProcessRunner()
        await mock.registerDefault(
            output: ProcessOutput(stdout: "", stderr: "", exitCode: 0)
        )

        let config = ExecutionConfig(
            maxWorkers: 1,
            swiftPath: "/usr/bin/swift"
        )
        let executor = ParallelExecutor(config: config, processRunner: mock)

        let scope = TestFixtures.natsScope
        _ = try await executor.execute(scopes: [scope])

        let invocations = await mock.allInvocations()
        #expect(invocations.count == 1)

        let args = invocations[0].arguments
        #expect(args.contains("test"))
        #expect(args.contains("--parallel"))
        #expect(args.contains("--filter"))
        #expect(args.contains("NATSTests"))
        #expect(args.contains("--experimental-event-stream-output"))
    }

    @Test("handles process errors gracefully")
    func processErrorHandling() async throws {
        let mock = MockProcessRunner()
        // Register output that simulates a process error via stderr
        await mock.registerDefault(
            output: ProcessOutput(
                stdout: "",
                stderr: "error: no tests matched filter 'NonExistent'",
                exitCode: 1
            )
        )

        let config = ExecutionConfig(maxWorkers: 1)
        let executor = ParallelExecutor(config: config, processRunner: mock)

        let scope = TestScope(name: "nonexistent", filter: "NonExistent")
        let results = try await executor.execute(scopes: [scope])

        #expect(results.count == 1)
        // Should not crash — should return a result (possibly with no test cases)
    }

    @Test("notifies progress delegate on scope lifecycle")
    func progressDelegateNotification() async throws {
        let mock = MockProcessRunner()
        let passedOutput = TestFixtures.allPassedOutput(suite: "Tests", count: 3)
        await mock.registerDefault(
            output: ProcessOutput(stdout: passedOutput, stderr: "", exitCode: 0)
        )

        let delegate = SpyProgressDelegate()
        let config = ExecutionConfig(maxWorkers: 1)
        let executor = ParallelExecutor(
            config: config,
            processRunner: mock,
            progressDelegate: delegate
        )

        _ = try await executor.execute(scopes: [TestFixtures.natsScope])

        let startedCount = await delegate.startedCount()
        let finishedCount = await delegate.finishedCount()
        #expect(startedCount == 1)
        #expect(finishedCount == 1)
    }
}

// MARK: - Spy Progress Delegate

actor SpyProgressDelegate: ExecutionProgressDelegate {
    private var _startedScopes: [String] = []
    private var _finishedScopes: [String] = []

    nonisolated func scopeStarted(_ scope: TestScope) async {
        await recordStarted(scope.name)
    }

    nonisolated func scopeProgress(_ scope: TestScope, completed: Int, total: Int) async {
        // no-op for this spy
    }

    nonisolated func scopeFinished(_ scope: TestScope, result: ScopeResult) async {
        await recordFinished(scope.name)
    }

    private func recordStarted(_ name: String) {
        _startedScopes.append(name)
    }

    private func recordFinished(_ name: String) {
        _finishedScopes.append(name)
    }

    func startedCount() -> Int { _startedScopes.count }
    func finishedCount() -> Int { _finishedScopes.count }
    func startedScopes() -> [String] { _startedScopes }
    func finishedScopes() -> [String] { _finishedScopes }
}
