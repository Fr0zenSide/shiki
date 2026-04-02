import Foundation
import Testing
@testable import ShikkiKit

@Suite("FixEngine")
struct FixEngineTests {

    // MARK: - Fix Unit Creation

    @Test("<5 failures creates single fix unit")
    func singleFixUnit() {
        let runner = MockFixAgentRunner()
        let engine = FixEngine(projectRoot: "/tmp/test", agentRunner: runner)
        let failures = (0..<3).map { TestFailure(testName: "test\($0)", module: "Mod") }
        let units = engine.createFixUnits(from: failures, iteration: 1)
        #expect(units.count == 1)
        #expect(units[0].modules == ["all"])
    }

    @Test("5+ failures splits by module")
    func moduleFixUnits() {
        let runner = MockFixAgentRunner()
        let engine = FixEngine(projectRoot: "/tmp/test", agentRunner: runner)
        let failures = [
            TestFailure(testName: "a", module: "CoreKit"),
            TestFailure(testName: "b", module: "CoreKit"),
            TestFailure(testName: "c", module: "CoreKit"),
            TestFailure(testName: "d", module: "NetKit"),
            TestFailure(testName: "e", module: "NetKit"),
        ]
        let units = engine.createFixUnits(from: failures, iteration: 1)
        #expect(units.count == 2)
        let moduleNames = units.flatMap(\.modules).sorted()
        #expect(moduleNames.contains("CoreKit"))
        #expect(moduleNames.contains("NetKit"))
    }

    // MARK: - Fix Prompt

    @Test("fix prompt includes failure details")
    func fixPromptContent() {
        let runner = MockFixAgentRunner()
        let engine = FixEngine(projectRoot: "/tmp/test", agentRunner: runner)
        let failures = [
            TestFailure(testName: "testFoo", file: "FooTests.swift", line: 42, message: "Expected true", module: "Mod")
        ]
        let layer = ProtocolLayer(
            featureName: "Test",
            protocols: [ProtocolSpec(name: "FooProvider", methods: ["func bar()"])]
        )
        let unit = engine.createFixUnits(from: failures, iteration: 1)[0]
        let prompt = engine.generateFixPrompt(unit: unit, failures: failures, layer: layer, cache: nil)

        #expect(prompt.contains("testFoo"))
        #expect(prompt.contains("FooTests.swift:42"))
        #expect(prompt.contains("Expected true"))
        #expect(prompt.contains("do NOT modify"))
        #expect(prompt.contains("FooProvider"))
    }

    @Test("fix prompt includes architecture context when available")
    func fixPromptWithCache() {
        let runner = MockFixAgentRunner()
        let engine = FixEngine(projectRoot: "/tmp/test", agentRunner: runner)
        let failures = [TestFailure(testName: "t", module: "Mod")]
        let cache = ArchitectureCache(
            projectId: "test", projectPath: "/tmp", gitHash: "abc", builtAt: Date(),
            packageInfo: PackageInfo(name: "TestProject"), protocols: [], types: [],
            dependencyGraph: [:], patterns: [], testInfo: TestInfo()
        )
        let unit = engine.createFixUnits(from: failures, iteration: 1)[0]
        let prompt = engine.generateFixPrompt(
            unit: unit, failures: failures,
            layer: ProtocolLayer(), cache: cache
        )
        #expect(prompt.contains("TestProject"))
    }

    // MARK: - Error Cases

    @Test("throws on empty failures")
    func emptyFailuresThrows() async {
        let runner = MockFixAgentRunner()
        let engine = FixEngine(projectRoot: "/tmp/test", agentRunner: runner)

        do {
            _ = try await engine.fix(failures: [], layer: ProtocolLayer())
            Issue.record("Should have thrown")
        } catch is FixError {
            // Expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("throws architectural error for >20 failures")
    func architecturalThrows() async {
        let runner = MockFixAgentRunner()
        let engine = FixEngine(projectRoot: "/tmp/test", agentRunner: runner)
        let failures = (0..<25).map { TestFailure(testName: "test\($0)", module: "Mod") }

        do {
            _ = try await engine.fix(failures: failures, layer: ProtocolLayer())
            Issue.record("Should have thrown")
        } catch let error as FixError {
            if case .architecturalFailure = error {
                // Expected
            } else {
                Issue.record("Wrong FixError variant: \(error)")
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    // MARK: - Max Iterations

    @Test("max iterations is 3")
    func maxIterations() {
        #expect(FixEngine.maxIterations == 3)
    }

    // MARK: - Fix Result

    @Test("fix result tracks total fixed count")
    func fixResultCounts() {
        let result = FixResult(
            iterations: [
                FixIterationResult(iteration: 1, fixedCount: 3, remainingFailures: [
                    TestFailure(testName: "a"), TestFailure(testName: "b")
                ]),
                FixIterationResult(iteration: 2, fixedCount: 2, remainingFailures: []),
            ],
            finallyPassed: true,
            totalFixedCount: 5,
            remainingFailures: []
        )
        #expect(result.finallyPassed)
        #expect(result.totalFixedCount == 5)
        #expect(result.remainingFailures.isEmpty)
    }

    @Test("fix iteration knows when all fixed")
    func iterationAllFixed() {
        let done = FixIterationResult(iteration: 1, fixedCount: 5, remainingFailures: [])
        let notDone = FixIterationResult(iteration: 1, fixedCount: 3, remainingFailures: [
            TestFailure(testName: "x")
        ])
        #expect(done.allFixed)
        #expect(!notDone.allFixed)
    }

    // MARK: - Hardening: Happy Path (BR-01 through BR-06)

    @Test("happy path: progressive fix across 2 iterations")
    func happyPathProgressiveFix() async throws {
        let runner = MockFixAgentRunner()
        let git = MockGitOps()
        let testRunner = MockTestRunner()
        let verifier = MockContractVerifier()

        // Iteration 1: 4 failures -> 2 remaining
        // Iteration 2: 2 remaining -> 0
        testRunner.results = [
            TestRunResult(passed: false, totalTests: 4, failedTests: 2, failures: [
                TestFailure(testName: "c", module: "Mod"),
                TestFailure(testName: "d", module: "Mod"),
            ]),
            TestRunResult(passed: true, totalTests: 4, failedTests: 0, failures: []),
        ]

        git.headHash = "abc123"
        git.diffFiles = []
        verifier.result = ContractResult(isValid: true)

        let engine = FixEngine(
            projectRoot: "/tmp/test",
            agentRunner: runner,
            contractVerifier: verifier,
            gitOps: git,
            testRunner: testRunner
        )

        let failures = (0..<4).map { TestFailure(testName: "test\($0)", module: "Mod") }
        let result = try await engine.fix(failures: failures, layer: ProtocolLayer())

        #expect(result.finallyPassed)
        #expect(result.iterations.count == 2)
        #expect(result.totalFixedCount == 4)
    }

    // MARK: - Hardening: Regression (BR-03)

    @Test("regression: fix creates more failures then rollback + event")
    func regressionTriggersRollback() async throws {
        let runner = MockFixAgentRunner()
        let git = MockGitOps()
        let testRunner = MockTestRunner()
        let verifier = MockContractVerifier()

        // Start with 3 failures, iteration makes it 5 (regression)
        testRunner.results = [
            TestRunResult(passed: false, totalTests: 5, failedTests: 5, failures:
                (0..<5).map { TestFailure(testName: "test\($0)", module: "Mod") }
            ),
        ]

        git.headHash = "snap123"
        git.diffFiles = []
        verifier.result = ContractResult(isValid: true)

        let collector = FixEventCollector()

        let engine = FixEngine(
            projectRoot: "/tmp/test",
            agentRunner: runner,
            contractVerifier: verifier,
            gitOps: git,
            testRunner: testRunner
        )

        let failures = (0..<3).map { TestFailure(testName: "test\($0)", module: "Mod") }
        _ = try await engine.fix(failures: failures, layer: ProtocolLayer()) { event in
            collector.append(event)
        }

        // Should have rolled back
        #expect(git.resetCalls.contains("snap123"))

        // Should have emitted regression event
        let hasRegression = collector.events.contains { event in
            if case .regression(let iter, let delta) = event {
                return iter == 1 && delta == -2
            }
            return false
        }
        #expect(hasRegression)
    }

    // MARK: - Hardening: Test File Modification (BR-04)

    @Test("test file modification: agent modifies Tests.swift then rollback + skip")
    func testFileModificationTriggersRollback() async throws {
        let runner = MockFixAgentRunner()
        let git = MockGitOps()
        let testRunner = MockTestRunner()
        let verifier = MockContractVerifier()

        // After agent runs, git diff shows test file was modified
        git.headHash = "snap456"
        git.diffFiles = ["Sources/Foo.swift", "Tests/FooTests.swift"]
        verifier.result = ContractResult(isValid: true)

        let collector = FixEventCollector()

        let engine = FixEngine(
            projectRoot: "/tmp/test",
            agentRunner: runner,
            contractVerifier: verifier,
            gitOps: git,
            testRunner: testRunner
        )

        let failures = [TestFailure(testName: "testA", module: "Mod")]
        _ = try await engine.fix(failures: failures, layer: ProtocolLayer()) { event in
            collector.append(event)
        }

        // Should have rolled back
        #expect(git.resetCalls.contains("snap456"))

        // Should have emitted test file modification event
        let hasTestFileMod = collector.events.contains { event in
            if case .testFileModification(let iter, let files) = event {
                return iter == 1 && files.contains("Tests/FooTests.swift")
            }
            return false
        }
        #expect(hasTestFileMod)
    }

    // MARK: - Hardening: Exhaustion (BR-05)

    @Test("exhaustion: 3 iterations still have failures then exhausted event")
    func exhaustionEmitsEvent() async throws {
        let runner = MockFixAgentRunner()
        let git = MockGitOps()
        let testRunner = MockTestRunner()
        let verifier = MockContractVerifier()

        // Each iteration fixes 1 but 1 always remains
        let stubFailure = TestFailure(testName: "stubbornTest", module: "Mod")
        testRunner.results = [
            TestRunResult(passed: false, totalTests: 3, failedTests: 2, failures: [
                stubFailure, TestFailure(testName: "b", module: "Mod"),
            ]),
            TestRunResult(passed: false, totalTests: 3, failedTests: 1, failures: [stubFailure]),
            TestRunResult(passed: false, totalTests: 3, failedTests: 1, failures: [stubFailure]),
        ]

        git.headHash = "snap789"
        git.diffFiles = []
        verifier.result = ContractResult(isValid: true)

        let collector = FixEventCollector()

        let engine = FixEngine(
            projectRoot: "/tmp/test",
            agentRunner: runner,
            contractVerifier: verifier,
            gitOps: git,
            testRunner: testRunner
        )

        let failures = (0..<3).map { TestFailure(testName: "test\($0)", module: "Mod") }
        let result = try await engine.fix(failures: failures, layer: ProtocolLayer()) { event in
            collector.append(event)
        }

        #expect(!result.finallyPassed)
        #expect(result.iterations.count == 3)

        // Should have emitted exhausted event
        let hasExhausted = collector.events.contains { event in
            if case .exhausted(let remaining) = event {
                return !remaining.isEmpty
            }
            return false
        }
        #expect(hasExhausted)
    }

    // MARK: - Hardening: Contract Violation (BR-02)

    @Test("contract violation: fix breaks protocol contracts then rollback + event")
    func contractViolationTriggersRollback() async throws {
        let runner = MockFixAgentRunner()
        let git = MockGitOps()
        let testRunner = MockTestRunner()
        let verifier = MockContractVerifier()

        git.headHash = "snapABC"
        git.diffFiles = []

        // Contract verification fails after agent runs
        verifier.result = ContractResult(isValid: false, issues: ["Missing method foo()"])

        let collector = FixEventCollector()

        let engine = FixEngine(
            projectRoot: "/tmp/test",
            agentRunner: runner,
            contractVerifier: verifier,
            gitOps: git,
            testRunner: testRunner
        )

        let failures = [TestFailure(testName: "testA", module: "Mod")]
        _ = try await engine.fix(failures: failures, layer: ProtocolLayer()) { event in
            collector.append(event)
        }

        // Should have rolled back
        #expect(git.resetCalls.contains("snapABC"))

        // Should have emitted contract violation event
        let hasViolation = collector.events.contains { event in
            if case .contractViolation(let iter, let issues) = event {
                return iter == 1 && issues.contains("Missing method foo()")
            }
            return false
        }
        #expect(hasViolation)
    }

    // MARK: - Hardening: Per-Iteration Timeout (BR-06)

    @Test("per-iteration timeout: agent exceeds timeout then rollback + event")
    func timeoutTriggersRollback() async throws {
        let runner = MockSlowAgentRunner(delaySeconds: 2)
        let git = MockGitOps()
        let testRunner = MockTestRunner()
        let verifier = MockContractVerifier()

        git.headHash = "snapTIME"
        git.diffFiles = []
        verifier.result = ContractResult(isValid: true)
        testRunner.results = []

        let collector = FixEventCollector()

        // 1-second timeout but agent takes 2 seconds
        let engine = FixEngine(
            projectRoot: "/tmp/test",
            agentRunner: runner,
            contractVerifier: verifier,
            iterationTimeoutSeconds: 1,
            gitOps: git,
            testRunner: testRunner
        )

        let failures = [TestFailure(testName: "testA", module: "Mod")]
        _ = try await engine.fix(failures: failures, layer: ProtocolLayer()) { event in
            collector.append(event)
        }

        // Should have rolled back
        #expect(git.resetCalls.contains("snapTIME"))

        // Should have emitted timeout event
        let hasTimeout = collector.events.contains { event in
            if case .timedOut(let iter) = event {
                return iter == 1
            }
            return false
        }
        #expect(hasTimeout)
    }
}

// MARK: - Event Collector (thread-safe)

final class FixEventCollector: @unchecked Sendable {
    private var _events: [FixProgressEvent] = []

    func append(_ event: FixProgressEvent) {
        _events.append(event)
    }

    var events: [FixProgressEvent] { _events }
}

// MARK: - Mock Fix Agent Runner

final class MockFixAgentRunner: AgentRunner, @unchecked Sendable {
    var runCount = 0

    func run(prompt: String, workingDirectory: String, unitId: String) async throws -> AgentResult {
        runCount += 1
        return AgentResult(unitId: unitId, status: .completed, durationSeconds: 1)
    }
}

// MARK: - Mock Slow Agent Runner (for timeout tests)

final class MockSlowAgentRunner: AgentRunner, @unchecked Sendable {
    let delaySeconds: UInt64

    init(delaySeconds: UInt64) {
        self.delaySeconds = delaySeconds
    }

    func run(prompt: String, workingDirectory: String, unitId: String) async throws -> AgentResult {
        try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        return AgentResult(unitId: unitId, status: .completed, durationSeconds: Int(delaySeconds))
    }
}

// MARK: - Mock Git Operations

final class MockGitOps: GitOperationsProvider, @unchecked Sendable {
    var headHash: String = "mock-hash"
    var diffFiles: [String] = []
    var resetCalls: [String] = []

    func snapshotHead() async throws -> String {
        headHash
    }

    func resetHard(to hash: String) async throws {
        resetCalls.append(hash)
    }

    func diffNameOnly() async throws -> [String] {
        diffFiles
    }
}

// MARK: - Mock Contract Verifier

final class MockContractVerifier: ContractVerifierProtocol, @unchecked Sendable {
    var result = ContractResult(isValid: true)

    func verify(_ layer: ProtocolLayer) -> ContractResult {
        result
    }
}

// MARK: - Mock Test Runner

final class MockTestRunner: TestRunnerProtocol, @unchecked Sendable {
    var results: [TestRunResult] = []
    private var callIndex = 0

    func runTests(scope: [String]) async throws -> TestRunResult {
        guard callIndex < results.count else {
            return TestRunResult(passed: true, totalTests: 0, failures: [])
        }
        let result = results[callIndex]
        callIndex += 1
        return result
    }
}
