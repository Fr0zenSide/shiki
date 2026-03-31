// Reports.swift — CLI output models for history, regression, and slow test commands
// Part of ShikkiTestRunner

import Foundation

// MARK: - HistoryReport

/// Model for `shikki test --history` output.
///
/// Contains a list of recent test runs with summary statistics.
public struct HistoryReport: Sendable, Equatable {
    /// The runs to display, most recent first.
    public let runs: [RunSummary]

    /// A single run in the history.
    public struct RunSummary: Sendable, Equatable {
        /// Short git hash (first 7 chars).
        public let shortHash: String

        /// Branch name, if available.
        public let branchName: String?

        /// When the run started.
        public let startedAt: String

        /// Total test count.
        public let totalTests: Int64

        /// Number of passing tests.
        public let passed: Int64

        /// Number of failing tests.
        public let failed: Int64

        /// Number of skipped tests.
        public let skipped: Int64

        /// Total duration in milliseconds.
        public let durationMs: Int64

        /// Whether the run is complete.
        public let isFinished: Bool

        public init(
            shortHash: String,
            branchName: String? = nil,
            startedAt: String,
            totalTests: Int64 = 0,
            passed: Int64 = 0,
            failed: Int64 = 0,
            skipped: Int64 = 0,
            durationMs: Int64 = 0,
            isFinished: Bool = true
        ) {
            self.shortHash = shortHash
            self.branchName = branchName
            self.startedAt = startedAt
            self.totalTests = totalTests
            self.passed = passed
            self.failed = failed
            self.skipped = skipped
            self.durationMs = durationMs
            self.isFinished = isFinished
        }
    }

    public init(runs: [RunSummary]) {
        self.runs = runs
    }

    /// Create a HistoryReport from TestRunRows.
    public static func from(rows: [TestRunRow]) -> HistoryReport {
        let summaries = rows.map { row in
            let shortHash = String(row.gitHash.prefix(7))
            return RunSummary(
                shortHash: shortHash,
                branchName: row.branchName,
                startedAt: row.startedAt,
                totalTests: row.totalTests ?? 0,
                passed: row.passed ?? 0,
                failed: row.failed ?? 0,
                skipped: row.skipped ?? 0,
                durationMs: row.durationMs ?? 0,
                isFinished: row.finishedAt != nil
            )
        }
        return HistoryReport(runs: summaries)
    }

    /// Whether any runs have failures.
    public var hasFailures: Bool {
        runs.contains { $0.failed > 0 }
    }

    /// Whether the report is empty.
    public var isEmpty: Bool {
        runs.isEmpty
    }
}

// MARK: - RegressionReport

/// Model for `shikki test --regression` output.
///
/// Contains regressions found by comparing recent runs.
public struct RegressionReport: Sendable, Equatable {
    /// The regressions detected.
    public let regressions: [Regression]

    /// The current run's git hash.
    public let currentHash: String

    /// The previous run's git hash.
    public let previousHash: String

    public init(
        regressions: [Regression],
        currentHash: String,
        previousHash: String
    ) {
        self.regressions = regressions
        self.currentHash = currentHash
        self.previousHash = previousHash
    }

    /// Whether any regressions were found.
    public var hasRegressions: Bool {
        !regressions.isEmpty
    }

    /// Number of regressions.
    public var count: Int {
        regressions.count
    }

    /// Whether the report is clean (no regressions).
    public var isClean: Bool {
        regressions.isEmpty
    }
}

// MARK: - SlowTestReport

/// Model for `shikki test --slow` output.
///
/// Contains tests exceeding the duration threshold.
public struct SlowTestReport: Sendable, Equatable {
    /// The slow tests detected, ordered by duration descending.
    public let slowTests: [SlowTest]

    /// The threshold in milliseconds used for detection.
    public let thresholdMs: Int64

    public init(slowTests: [SlowTest], thresholdMs: Int64) {
        self.slowTests = slowTests
        self.thresholdMs = thresholdMs
    }

    /// Whether any slow tests were found.
    public var hasSlow: Bool {
        !slowTests.isEmpty
    }

    /// Number of slow tests.
    public var count: Int {
        slowTests.count
    }

    /// Whether the report is clean (no slow tests).
    public var isClean: Bool {
        slowTests.isEmpty
    }

    /// Total time spent in slow tests, in milliseconds.
    public var totalSlowMs: Int64 {
        slowTests.reduce(0) { $0 + $1.durationMs }
    }
}
