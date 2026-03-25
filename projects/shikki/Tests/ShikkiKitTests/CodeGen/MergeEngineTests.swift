import Testing
import Foundation
@testable import ShikkiKit

@Suite("MergeEngine")
struct MergeEngineTests {

    let engine = MergeEngine(projectRoot: "/tmp/test")

    // MARK: - Test Failure Parsing

    @Test("parses swift-testing failure output")
    func parseSwiftTestingFailure() {
        let output = """
        Test "validates input correctly" recorded an issue at InputTests.swift:42: Expectation failed
        """
        let failures = engine.parseTestFailures(output)
        #expect(failures.count == 1)
        #expect(failures[0].testName == "validates input correctly")
        #expect(failures[0].file == "InputTests.swift")
        #expect(failures[0].line == 42)
    }

    @Test("parses multiple swift-testing failures")
    func parseMultipleFailures() {
        let output = """
        Test "test A" recorded an issue at FileA.swift:10: failed
        Test "test B" failed at FileB.swift:20
        """
        let failures = engine.parseTestFailures(output)
        #expect(failures.count == 2)
    }

    @Test("parses XCTest failure output")
    func parseXCTestFailure() {
        let output = """
        Tests/FooTests.swift:15: error: -[ShikkiKit.FooTests testBar] : XCTAssertEqual failed
        """
        let failures = engine.parseTestFailures(output)
        #expect(failures.count == 1)
        #expect(failures[0].testName == "testBar")
        #expect(failures[0].module == "ShikkiKit")
        #expect(failures[0].file.contains("FooTests.swift"))
    }

    @Test("returns empty for clean test output")
    func cleanOutput() {
        let output = "Test run with 50 tests in 5 suites passed after 0.5 seconds."
        let failures = engine.parseTestFailures(output)
        #expect(failures.isEmpty)
    }

    // MARK: - Test Count Parsing

    @Test("parses swift-testing test counts")
    func swiftTestingCounts() {
        let output = "Test run with 88 tests in 7 suites passed after 0.6 seconds."
        let (total, failed) = engine.parseTestCounts(output)
        #expect(total == 88)
        #expect(failed == 0)
    }

    @Test("parses swift-testing failed counts")
    func swiftTestingFailedCounts() {
        let output = "Test run with 50 tests in 5 suites failed after 1.2 seconds."
        let (total, failed) = engine.parseTestCounts(output)
        #expect(total == 50)
        #expect(failed == 1)
    }

    @Test("parses XCTest counts")
    func xctestCounts() {
        let output = "Executed 10 tests, with 2 failures"
        let (total, failed) = engine.parseTestCounts(output)
        #expect(total == 10)
        #expect(failed == 2)
    }

    // MARK: - Failure Classification

    @Test("classifies <5 failures as unit scope")
    func classifyFewFailures() {
        let failures = (0..<3).map { i in
            TestFailure(testName: "test\(i)", file: "File.swift", module: "Module")
        }
        let classified = engine.classifyFailures(failures)
        #expect(classified.allSatisfy { $0.scope == .unit })
    }

    @Test("classifies 5-20 failures as suite scope")
    func classifyModerateFailures() {
        let failures = (0..<10).map { i in
            TestFailure(testName: "test\(i)", file: "File.swift", module: "Module")
        }
        let classified = engine.classifyFailures(failures)
        #expect(classified.allSatisfy { $0.scope == .suite })
    }

    @Test("classifies >20 failures as architectural")
    func classifyManyFailures() {
        let failures = (0..<25).map { i in
            TestFailure(testName: "test\(i)", file: "File.swift", module: "Module")
        }
        let classified = engine.classifyFailures(failures)
        #expect(classified.allSatisfy { $0.scope == .architectural })
    }

    // MARK: - Group by Module

    @Test("groups failures by module")
    func groupByModule() {
        let failures = [
            TestFailure(testName: "a", module: "CoreKit"),
            TestFailure(testName: "b", module: "CoreKit"),
            TestFailure(testName: "c", module: "NetKit"),
        ]
        let grouped = engine.groupByModule(failures)
        #expect(grouped.count == 2)
        #expect(grouped["CoreKit"]?.count == 2)
        #expect(grouped["NetKit"]?.count == 1)
    }

    @Test("groups unknown module failures together")
    func groupUnknownModule() {
        let failures = [
            TestFailure(testName: "a", module: ""),
            TestFailure(testName: "b", module: ""),
        ]
        let grouped = engine.groupByModule(failures)
        #expect(grouped["unknown"]?.count == 2)
    }

    // MARK: - Module Inference

    @Test("infers module from Sources path")
    func inferModuleSources() {
        let module = engine.inferModuleFromFile("Sources/ShikkiKit/CodeGen/Foo.swift")
        #expect(module == "ShikkiKit")
    }

    @Test("infers module from Tests path")
    func inferModuleTests() {
        let module = engine.inferModuleFromFile("Tests/ShikkiKitTests/FooTests.swift")
        #expect(module == "ShikkiKitTests")
    }

    @Test("returns unknown for flat paths")
    func inferModuleFlat() {
        let module = engine.inferModuleFromFile("File.swift")
        #expect(module == "unknown")
    }

    // MARK: - Merge Result

    @Test("clean merge result when no conflicts and tests pass")
    func cleanMerge() {
        let result = MergeResult(
            mergedBranches: ["branch-a", "branch-b"],
            testsPassed: true
        )
        #expect(result.isClean)
    }

    @Test("dirty merge result with conflicts")
    func dirtyMergeConflicts() {
        let result = MergeResult(
            mergedBranches: ["branch-a"],
            conflicts: ["File.swift"],
            testsPassed: true
        )
        #expect(!result.isClean)
    }

    @Test("dirty merge result with test failures")
    func dirtyMergeTests() {
        let result = MergeResult(
            mergedBranches: ["branch-a"],
            testsPassed: false,
            testFailures: [TestFailure(testName: "broken")]
        )
        #expect(!result.isClean)
    }

    // MARK: - Error Handling

    @Test("merge throws on empty results")
    func emptyResultsThrows() async {
        let dispatchResult = DispatchResult(
            agentResults: [AgentResult(unitId: "a", status: .failed)],
            totalDurationSeconds: 0,
            strategy: .sequential
        )
        let plan = WorkPlan(units: [WorkUnit(id: "a")], strategy: .sequential)

        do {
            _ = try await engine.merge(
                dispatchResult: dispatchResult,
                worktrees: [],
                plan: plan
            )
            Issue.record("Should have thrown")
        } catch is MergeError {
            // Expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}
