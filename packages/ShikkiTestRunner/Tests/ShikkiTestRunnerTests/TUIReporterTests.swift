// TUIReporterTests.swift — Tests for TUI rendering output
// Part of ShikkiTestRunnerTests

import Foundation
import Testing
@testable import ShikkiTestRunner

@Suite("TUIReporter")
struct TUIReporterTests {

    // MARK: - Scope Line Rendering

    @Test("all-green scope shows passed marker without failure suffixes")
    func allGreenScopeLine() {
        let reporter = TUIReporter()
        let result = TestFixtures.allPassedScopeResult(
            scope: TestFixtures.natsScope,
            count: 57
        )

        let line = reporter.renderScopeLine(result)

        #expect(line.contains(StatusMarker.allPassed.symbol))
        #expect(line.contains("nats"))
        #expect(line.contains("57/57"))
        #expect(!line.contains("!!"))
        #expect(!line.contains("??"))
    }

    @Test("failed scope shows failure marker with !!N suffix and detail lines")
    func failureScopeLine() {
        let reporter = TUIReporter()
        let result = TestFixtures.failedScopeResult(
            scope: TestFixtures.safetyScope,
            passed: 52,
            failures: [
                (name: "TOCTOU", message: "concurrent check both passed"),
                (name: "offHoursAccess", message: "timezone mismatch"),
                (name: "countdownCompletes", message: "SLOW (>2s threshold)")
            ]
        )

        let line = reporter.renderScopeLine(result)

        #expect(line.contains(StatusMarker.hasFailures.symbol))
        #expect(line.contains("safety"))
        #expect(line.contains("52/55"))
        #expect(line.contains("!!3"))
        // Detail lines
        #expect(line.contains("TOCTOU"))
        #expect(line.contains("concurrent check both passed"))
        #expect(line.contains("offHoursAccess"))
        #expect(line.contains("timezone mismatch"))
    }

    @Test("scope with failures and skipped shows both !!N and ??N suffixes")
    func failuresAndSkippedScopeLine() {
        let reporter = TUIReporter()
        let result = TestFixtures.failedScopeResult(
            scope: TestFixtures.safetyScope,
            passed: 51,
            failures: [
                (name: "TOCTOU", message: "concurrent check both passed"),
                (name: "offHoursAccess", message: "timezone mismatch"),
                (name: "countdownCompletes", message: "SLOW (>2s threshold)")
            ],
            skipped: [
                (name: "Integration", reason: "skipped: requires DB connection")
            ]
        )

        let line = reporter.renderScopeLine(result)

        #expect(line.contains("!!3"))
        #expect(line.contains("??1"))
        #expect(line.contains("Integration"))
        #expect(line.contains("skipped: requires DB connection"))
    }

    // MARK: - Summary Line Rendering

    @Test("all-green summary uses passed marker without suffixes")
    func allGreenSummary() {
        let reporter = TUIReporter()
        let scopeResults = [
            TestFixtures.allPassedScopeResult(scope: TestFixtures.natsScope, count: 57),
            TestFixtures.allPassedScopeResult(scope: TestFixtures.flywheelScope, count: 80)
        ]
        let run = TestFixtures.makeTestRunResult(scopeResults: scopeResults)

        let summary = reporter.renderSummary(run)

        #expect(summary.contains(StatusMarker.allPassed.symbol))
        #expect(summary.contains("abc123f"))
        #expect(summary.contains("fix/mega-merge"))
        #expect(summary.contains("137/137"))
        #expect(!summary.contains("!!"))
        #expect(!summary.contains("??"))
        // Contains separator
        #expect(summary.contains("\u{2501}"))
    }

    @Test("summary with failures shows failure marker and !!N")
    func failureSummary() {
        let reporter = TUIReporter()
        let scopeResults = [
            TestFixtures.allPassedScopeResult(scope: TestFixtures.natsScope, count: 57),
            TestFixtures.failedScopeResult(
                scope: TestFixtures.safetyScope,
                passed: 52,
                failures: [
                    (name: "test1", message: "fail"),
                    (name: "test2", message: "fail"),
                    (name: "test3", message: "fail")
                ]
            )
        ]
        let run = TestFixtures.makeTestRunResult(scopeResults: scopeResults)

        let summary = reporter.renderSummary(run)

        #expect(summary.contains(StatusMarker.hasFailures.symbol))
        #expect(summary.contains("!!3"))
    }

    @Test("partial run uses partial marker when all scopes pass")
    func partialRunSummary() {
        let reporter = TUIReporter()
        let scopeResults = [
            TestFixtures.allPassedScopeResult(scope: TestFixtures.natsScope, count: 57),
            TestFixtures.allPassedScopeResult(scope: TestFixtures.tuiScope, count: 89)
        ]
        let run = TestFixtures.makeTestRunResult(
            scopeResults: scopeResults,
            isPartialRun: true,
            totalScopeCount: 5
        )

        let summary = reporter.renderSummary(run)

        #expect(summary.contains(StatusMarker.partialRun.symbol))
        #expect(summary.contains("146/146"))
    }

    @Test("verbose summary appends log file path")
    func verboseSummary() {
        let reporter = TUIReporter(
            verbosity: .verbose,
            logFilePath: ".shikki/test-logs/2026-03-31-abc123f.log"
        )
        let scopeResults = [
            TestFixtures.allPassedScopeResult(scope: TestFixtures.natsScope, count: 57)
        ]
        let run = TestFixtures.makeTestRunResult(scopeResults: scopeResults)

        let summary = reporter.renderSummary(run)

        #expect(summary.contains("Full log: .shikki/test-logs/2026-03-31-abc123f.log"))
    }

    @Test("clean verbosity does NOT append log file path")
    func cleanNoLogPath() {
        let reporter = TUIReporter(
            verbosity: .clean,
            logFilePath: ".shikki/test-logs/2026-03-31-abc123f.log"
        )
        let scopeResults = [
            TestFixtures.allPassedScopeResult(scope: TestFixtures.natsScope, count: 57)
        ]
        let run = TestFixtures.makeTestRunResult(scopeResults: scopeResults)

        let summary = reporter.renderSummary(run)

        #expect(!summary.contains("Full log:"))
    }

    // MARK: - Full Report

    @Test("full report contains all scope lines and summary")
    func fullReport() {
        let reporter = TUIReporter()
        let scopeResults = [
            TestFixtures.allPassedScopeResult(scope: TestFixtures.natsScope, count: 57),
            TestFixtures.allPassedScopeResult(scope: TestFixtures.flywheelScope, count: 80),
            TestFixtures.allPassedScopeResult(scope: TestFixtures.tuiScope, count: 89)
        ]
        let run = TestFixtures.makeTestRunResult(scopeResults: scopeResults)

        let report = reporter.renderFullReport(run)

        #expect(report.contains("nats"))
        #expect(report.contains("flywheel"))
        #expect(report.contains("tui"))
        #expect(report.contains("226/226"))
        // Contains separator
        #expect(report.contains("\u{2501}"))
    }

    // MARK: - Duration Formatting

    @Test("formatDuration handles sub-second, seconds, and minutes")
    func durationFormatting() {
        let reporter = TUIReporter()

        #expect(reporter.formatDuration(200) == "0.2s")
        #expect(reporter.formatDuration(1200) == "1.2s")
        #expect(reporter.formatDuration(65000) == "1m5s")
        #expect(reporter.formatDuration(0) == "0.0s")
    }
}
