// RegressionDetectorTests.swift — Tests for regression detection
// Part of ShikkiTestRunnerTests

import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("RegressionDetector")
struct RegressionDetectorTests {

    // MARK: - Helpers

    /// Create a store with two runs and some results.
    private func storeWithTwoRuns() throws -> (SQLiteStore, String, String) {
        let store = try SQLiteStore(path: ":memory:")

        // Previous run: all green
        let previousRun = try store.recordRun(gitHash: "aaa111", branch: "develop")
        _ = try store.recordResult(
            runID: previousRun, testFile: "CoreTests.swift",
            testName: "testAdd", suiteName: "CoreTests",
            status: .passed, durationMs: 5
        )
        _ = try store.recordResult(
            runID: previousRun, testFile: "CoreTests.swift",
            testName: "testSubtract", suiteName: "CoreTests",
            status: .passed, durationMs: 3
        )
        _ = try store.recordResult(
            runID: previousRun, testFile: "NATSTests.swift",
            testName: "testPublish", suiteName: "NATSTests",
            status: .passed, durationMs: 10
        )
        try store.finishRun(
            runID: previousRun, totalTests: 3, passed: 3,
            failed: 0, skipped: 0, durationMs: 100
        )

        // Current run: one test regressed
        let currentRun = try store.recordRun(gitHash: "bbb222", branch: "develop")
        _ = try store.recordResult(
            runID: currentRun, testFile: "CoreTests.swift",
            testName: "testAdd", suiteName: "CoreTests",
            status: .passed, durationMs: 4
        )
        _ = try store.recordResult(
            runID: currentRun, testFile: "CoreTests.swift",
            testName: "testSubtract", suiteName: "CoreTests",
            status: .failed, durationMs: 2,
            error: "Expected 5, got 3"
        )
        _ = try store.recordResult(
            runID: currentRun, testFile: "NATSTests.swift",
            testName: "testPublish", suiteName: "NATSTests",
            status: .passed, durationMs: 8
        )
        try store.finishRun(
            runID: currentRun, totalTests: 3, passed: 2,
            failed: 1, skipped: 0, durationMs: 90
        )

        return (store, previousRun, currentRun)
    }

    // MARK: - Green to Red Detection

    @Test("Detect regression: green in previous, red in current")
    func detectGreenToRed() throws {
        let (store, previousRun, currentRun) = try storeWithTwoRuns()
        let detector = RegressionDetector(store: store)

        let regressions = try detector.detectRegressions(
            currentRunID: currentRun,
            previousRunID: previousRun
        )

        #expect(regressions.count == 1)
        #expect(regressions[0].testName == "testSubtract")
        #expect(regressions[0].errorMessage == "Expected 5, got 3")
        #expect(regressions[0].lastGreenHash == "aaa111")
        #expect(regressions[0].currentHash == "bbb222")
    }

    @Test("No regressions when all tests pass in both runs")
    func noRegressions() throws {
        let store = try SQLiteStore(path: ":memory:")

        let run1 = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "A.swift",
            testName: "testA", status: .passed, durationMs: 1
        )
        try store.finishRun(runID: run1, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 10)

        let run2 = try store.recordRun(gitHash: "bbb", branch: "main")
        _ = try store.recordResult(
            runID: run2, testFile: "A.swift",
            testName: "testA", status: .passed, durationMs: 1
        )
        try store.finishRun(runID: run2, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 10)

        let detector = RegressionDetector(store: store)
        let regressions = try detector.detectRegressions(
            currentRunID: run2, previousRunID: run1
        )
        #expect(regressions.isEmpty)
    }

    @Test("Test already failing in both runs is not a regression")
    func alreadyFailing() throws {
        let store = try SQLiteStore(path: ":memory:")

        let run1 = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "A.swift",
            testName: "testBroken", status: .failed, durationMs: 1,
            error: "was broken"
        )
        try store.finishRun(runID: run1, totalTests: 1, passed: 0, failed: 1, skipped: 0, durationMs: 10)

        let run2 = try store.recordRun(gitHash: "bbb", branch: "main")
        _ = try store.recordResult(
            runID: run2, testFile: "A.swift",
            testName: "testBroken", status: .failed, durationMs: 1,
            error: "still broken"
        )
        try store.finishRun(runID: run2, totalTests: 1, passed: 0, failed: 1, skipped: 0, durationMs: 10)

        let detector = RegressionDetector(store: store)
        let regressions = try detector.detectRegressions(
            currentRunID: run2, previousRunID: run1
        )
        #expect(regressions.isEmpty)
    }

    @Test("Timeout treated as regression if previously passing")
    func timeoutRegression() throws {
        let store = try SQLiteStore(path: ":memory:")

        let run1 = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "A.swift",
            testName: "testSlow", status: .passed, durationMs: 100
        )
        try store.finishRun(runID: run1, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 100)

        let run2 = try store.recordRun(gitHash: "bbb", branch: "main")
        _ = try store.recordResult(
            runID: run2, testFile: "A.swift",
            testName: "testSlow", status: .timeout, durationMs: 5000,
            error: "Exceeded 5s timeout"
        )
        try store.finishRun(runID: run2, totalTests: 1, passed: 0, failed: 0, skipped: 0, durationMs: 5000)

        let detector = RegressionDetector(store: store)
        let regressions = try detector.detectRegressions(
            currentRunID: run2, previousRunID: run1
        )
        #expect(regressions.count == 1)
        #expect(regressions[0].testName == "testSlow")
    }

    @Test("Detect regressions with nonexistent run returns empty")
    func nonexistentRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let detector = RegressionDetector(store: store)

        let regressions = try detector.detectRegressions(
            currentRunID: "none", previousRunID: "also-none"
        )
        #expect(regressions.isEmpty)
    }

    // MARK: - First Failure

    @Test("Find first failure for a test with pass then fail history")
    func findFirstFailure() throws {
        let store = try SQLiteStore(path: ":memory:")

        // Run 1: passes
        let run1 = try store.recordRun(gitHash: "commit-1", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "X.swift",
            testName: "testX", status: .passed, durationMs: 1
        )
        try store.finishRun(runID: run1, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 10)

        // Run 2: still passes
        let run2 = try store.recordRun(gitHash: "commit-2", branch: "main")
        _ = try store.recordResult(
            runID: run2, testFile: "X.swift",
            testName: "testX", status: .passed, durationMs: 1
        )
        try store.finishRun(runID: run2, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 10)

        // Run 3: fails
        let run3 = try store.recordRun(gitHash: "commit-3", branch: "feature/break")
        _ = try store.recordResult(
            runID: run3, testFile: "X.swift",
            testName: "testX", status: .failed, durationMs: 1,
            error: "nil was not expected"
        )
        try store.finishRun(runID: run3, totalTests: 1, passed: 0, failed: 1, skipped: 0, durationMs: 10)

        // Run 4: still fails
        let run4 = try store.recordRun(gitHash: "commit-4", branch: "feature/break")
        _ = try store.recordResult(
            runID: run4, testFile: "X.swift",
            testName: "testX", status: .failed, durationMs: 1,
            error: "nil was not expected"
        )
        try store.finishRun(runID: run4, totalTests: 1, passed: 0, failed: 1, skipped: 0, durationMs: 10)

        let detector = RegressionDetector(store: store)
        let firstFailure = try detector.findFirstFailure(testName: "testX")

        #expect(firstFailure != nil)
        #expect(firstFailure?.introducedInHash == "commit-3")
        #expect(firstFailure?.introducedOnBranch == "feature/break")
        #expect(firstFailure?.errorMessage == "nil was not expected")
    }

    @Test("First failure for always-passing test returns nil")
    func firstFailureAlwaysPassing() throws {
        let store = try SQLiteStore(path: ":memory:")

        let run1 = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "A.swift",
            testName: "testGood", status: .passed, durationMs: 1
        )
        try store.finishRun(runID: run1, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 10)

        let detector = RegressionDetector(store: store)
        let firstFailure = try detector.findFirstFailure(testName: "testGood")
        #expect(firstFailure == nil)
    }

    @Test("First failure for test with no history returns nil")
    func firstFailureNoHistory() throws {
        let store = try SQLiteStore(path: ":memory:")
        let detector = RegressionDetector(store: store)
        let firstFailure = try detector.findFirstFailure(testName: "testGhost")
        #expect(firstFailure == nil)
    }

    // MARK: - Slow Tests

    @Test("Detect slow tests exceeding threshold")
    func detectSlowTests() throws {
        let store = try SQLiteStore(path: ":memory:")

        let run1 = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "FastTests.swift",
            testName: "testFast", status: .passed, durationMs: 10
        )
        _ = try store.recordResult(
            runID: run1, testFile: "SlowTests.swift",
            testName: "testSlow1", suiteName: "SlowTests",
            status: .passed, durationMs: 3500
        )
        _ = try store.recordResult(
            runID: run1, testFile: "SlowTests.swift",
            testName: "testSlow2", suiteName: "SlowTests",
            status: .passed, durationMs: 5200
        )
        _ = try store.recordResult(
            runID: run1, testFile: "EdgeTests.swift",
            testName: "testEdge", status: .passed, durationMs: 2000
        )
        try store.finishRun(runID: run1, totalTests: 4, passed: 4, failed: 0, skipped: 0, durationMs: 10000)

        let detector = RegressionDetector(store: store)
        let slow = try detector.slowTests(thresholdMs: 2000)

        // Only testSlow1 and testSlow2 exceed 2000ms (testEdge is exactly 2000, not >)
        #expect(slow.count == 2)
        // Ordered by duration descending
        #expect(slow[0].testName == "testSlow2")
        #expect(slow[0].durationMs == 5200)
        #expect(slow[1].testName == "testSlow1")
        #expect(slow[1].durationMs == 3500)
    }

    @Test("No slow tests when all are fast")
    func noSlowTests() throws {
        let store = try SQLiteStore(path: ":memory:")

        let run1 = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordResult(
            runID: run1, testFile: "A.swift",
            testName: "testA", status: .passed, durationMs: 5
        )
        _ = try store.recordResult(
            runID: run1, testFile: "B.swift",
            testName: "testB", status: .passed, durationMs: 10
        )
        try store.finishRun(runID: run1, totalTests: 2, passed: 2, failed: 0, skipped: 0, durationMs: 15)

        let detector = RegressionDetector(store: store)
        let slow = try detector.slowTests(thresholdMs: 2000)
        #expect(slow.isEmpty)
    }

    // MARK: - Latest Regressions Convenience

    @Test("Detect latest regressions auto-selects two most recent runs")
    func detectLatestRegressions() throws {
        let (store, _, _) = try storeWithTwoRuns()
        let detector = RegressionDetector(store: store)

        let regressions = try detector.detectLatestRegressions()
        #expect(regressions.count == 1)
        #expect(regressions[0].testName == "testSubtract")
    }

    @Test("Latest regressions with fewer than 2 runs returns empty")
    func latestRegressionsInsufficientRuns() throws {
        let store = try SQLiteStore(path: ":memory:")
        _ = try store.recordRun(gitHash: "aaa", branch: "main")

        let detector = RegressionDetector(store: store)
        let regressions = try detector.detectLatestRegressions()
        #expect(regressions.isEmpty)
    }
}
