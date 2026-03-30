import Testing
import Foundation
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
}

// MARK: - Mock Fix Agent Runner

final class MockFixAgentRunner: AgentRunner, @unchecked Sendable {
    var runCount = 0

    func run(prompt: String, workingDirectory: String, unitId: String) async throws -> AgentResult {
        runCount += 1
        return AgentResult(unitId: unitId, status: .completed, durationSeconds: 1)
    }
}
