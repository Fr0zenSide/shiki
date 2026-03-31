// ReportsTests.swift — Tests for CLI report models
// Part of ShikkiTestRunnerTests

import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("Reports")
struct ReportsTests {

    // MARK: - HistoryReport

    @Test("HistoryReport from TestRunRows truncates git hash")
    func historyReportFromRows() {
        let rows = [
            TestRunRow(
                runID: "run1", gitHash: "abc123def456789", branchName: "develop",
                startedAt: "2026-03-30T12:00:00Z", finishedAt: "2026-03-30T12:01:00Z",
                totalTests: 100, passed: 98, failed: 2, skipped: 0, durationMs: 1200
            ),
            TestRunRow(
                runID: "run2", gitHash: "deadbeef0123456", branchName: "main",
                startedAt: "2026-03-29T12:00:00Z", finishedAt: nil,
                totalTests: nil, passed: nil, failed: nil, skipped: nil, durationMs: nil
            ),
        ]

        let report = HistoryReport.from(rows: rows)
        #expect(report.runs.count == 2)
        #expect(report.runs[0].shortHash == "abc123d")
        #expect(report.runs[0].isFinished == true)
        #expect(report.runs[0].failed == 2)
        #expect(report.runs[1].shortHash == "deadbee")
        #expect(report.runs[1].isFinished == false)
        #expect(report.hasFailures == true)
    }

    @Test("HistoryReport isEmpty for no runs")
    func historyReportEmpty() {
        let report = HistoryReport(runs: [])
        #expect(report.isEmpty)
        #expect(!report.hasFailures)
    }

    // MARK: - RegressionReport

    @Test("RegressionReport properties")
    func regressionReportProperties() {
        let regressions = [
            Regression(
                testName: "testA", testFile: "A.swift",
                errorMessage: "failed", lastGreenHash: "aaa", currentHash: "bbb"
            ),
        ]
        let report = RegressionReport(
            regressions: regressions, currentHash: "bbb", previousHash: "aaa"
        )

        #expect(report.hasRegressions)
        #expect(report.count == 1)
        #expect(!report.isClean)
    }

    @Test("RegressionReport clean when no regressions")
    func regressionReportClean() {
        let report = RegressionReport(
            regressions: [], currentHash: "bbb", previousHash: "aaa"
        )
        #expect(report.isClean)
        #expect(!report.hasRegressions)
        #expect(report.count == 0)
    }

    // MARK: - SlowTestReport

    @Test("SlowTestReport total time calculation")
    func slowTestReportTotalTime() {
        let slow = [
            SlowTest(testName: "testA", testFile: "A.swift", durationMs: 3000, runID: "r1"),
            SlowTest(testName: "testB", testFile: "B.swift", durationMs: 5000, runID: "r1"),
        ]
        let report = SlowTestReport(slowTests: slow, thresholdMs: 2000)

        #expect(report.hasSlow)
        #expect(report.count == 2)
        #expect(report.totalSlowMs == 8000)
        #expect(!report.isClean)
    }

    @Test("SlowTestReport clean when no slow tests")
    func slowTestReportClean() {
        let report = SlowTestReport(slowTests: [], thresholdMs: 2000)
        #expect(report.isClean)
        #expect(!report.hasSlow)
        #expect(report.totalSlowMs == 0)
    }
}
