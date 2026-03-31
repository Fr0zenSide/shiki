// TestFixtures.swift — Shared test data factories
// Part of ShikkiTestRunnerTests

import Foundation
@testable import ShikkiTestRunner

enum TestFixtures {

    // MARK: - Scopes

    static let natsScope = TestScope(
        name: "nats",
        filter: "NATSTests",
        testFiles: ["NATSClientTests.swift", "EventBusTests.swift"],
        expectedTestCount: 57
    )

    static let flywheelScope = TestScope(
        name: "flywheel",
        filter: "FlywheelTests",
        testFiles: ["CalibrationTests.swift", "RiskScoringTests.swift"],
        expectedTestCount: 80
    )

    static let tuiScope = TestScope(
        name: "tui",
        filter: "TUITests",
        testFiles: ["TerminalOutputTests.swift", "ANSITests.swift"],
        expectedTestCount: 89
    )

    static let safetyScope = TestScope(
        name: "safety",
        filter: "SafetyTests",
        testFiles: ["BudgetACLTests.swift"],
        expectedTestCount: 55
    )

    static let kernelScope = TestScope(
        name: "kernel",
        filter: "KernelTests",
        testFiles: ["ShikkiKernelTests.swift"],
        expectedTestCount: 49
    )

    static let allScopes: [TestScope] = [natsScope, flywheelScope, tuiScope, safetyScope, kernelScope]

    // MARK: - Process Output

    static func allPassedOutput(suite: String, count: Int) -> String {
        (1...count).map { i in
            "Test Case '\(suite).test\(i)' passed (0.001 seconds)."
        }.joined(separator: "\n")
    }

    static func mixedOutput(suite: String, passed: Int, failed: Int) -> String {
        var lines: [String] = []
        for i in 1...passed {
            lines.append("Test Case '\(suite).testPassing\(i)' passed (0.001 seconds).")
        }
        for i in 1...failed {
            lines.append("Test Case '\(suite).testFailing\(i)' failed (0.002 seconds).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Scope Results

    static func allPassedScopeResult(scope: TestScope, count: Int) -> ScopeResult {
        let results = (1...count).map { i in
            TestCaseResult(
                testName: "test\(i)",
                suiteName: scope.name,
                status: .passed,
                durationMs: 1
            )
        }
        let start = Date()
        return ScopeResult(
            scope: scope,
            results: results,
            startedAt: start,
            finishedAt: start.addingTimeInterval(0.3)
        )
    }

    static func failedScopeResult(
        scope: TestScope,
        passed: Int,
        failures: [(name: String, message: String)],
        skipped: [(name: String, reason: String)] = []
    ) -> ScopeResult {
        var results: [TestCaseResult] = []

        for i in 1...passed {
            results.append(TestCaseResult(
                testName: "testPassing\(i)",
                suiteName: scope.name,
                status: .passed,
                durationMs: 1
            ))
        }

        for failure in failures {
            results.append(TestCaseResult(
                testName: failure.name,
                suiteName: scope.name,
                status: .failed,
                durationMs: 2,
                errorMessage: failure.message
            ))
        }

        for skip in skipped {
            results.append(TestCaseResult(
                testName: skip.name,
                suiteName: skip.name,
                status: .skipped,
                errorMessage: skip.reason
            ))
        }

        let start = Date()
        return ScopeResult(
            scope: scope,
            results: results,
            startedAt: start,
            finishedAt: start.addingTimeInterval(0.2)
        )
    }

    static func makeTestRunResult(
        scopeResults: [ScopeResult],
        gitHash: String = "abc123f0",
        branchName: String = "fix/mega-merge",
        isPartialRun: Bool = false,
        totalScopeCount: Int = 5
    ) -> TestRunResult {
        let start = scopeResults.first?.startedAt ?? Date()
        let end = scopeResults.last?.finishedAt ?? Date()
        return TestRunResult(
            runID: "test-run-1",
            scopeResults: scopeResults,
            gitHash: gitHash,
            branchName: branchName,
            startedAt: start,
            finishedAt: end,
            isPartialRun: isPartialRun,
            totalScopeCount: totalScopeCount
        )
    }
}
