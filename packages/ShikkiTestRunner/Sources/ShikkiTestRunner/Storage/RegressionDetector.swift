// RegressionDetector.swift — Compare test runs to find regressions
// Part of ShikkiTestRunner

import Foundation

// MARK: - Regression

/// A test that was passing in a previous run but is now failing.
public struct Regression: Sendable, Equatable {
    /// The test name that regressed.
    public let testName: String

    /// The suite containing the test.
    public let suiteName: String?

    /// The source file of the test.
    public let testFile: String

    /// The error message from the failing run.
    public let errorMessage: String?

    /// The error source location from the failing run.
    public let errorFile: String?

    /// The git hash of the run where the test was last green.
    public let lastGreenHash: String

    /// The git hash of the run where the test is now red.
    public let currentHash: String

    public init(
        testName: String,
        suiteName: String? = nil,
        testFile: String,
        errorMessage: String? = nil,
        errorFile: String? = nil,
        lastGreenHash: String,
        currentHash: String
    ) {
        self.testName = testName
        self.suiteName = suiteName
        self.testFile = testFile
        self.errorMessage = errorMessage
        self.errorFile = errorFile
        self.lastGreenHash = lastGreenHash
        self.currentHash = currentHash
    }
}

// MARK: - FirstFailure

/// Tracks when a test first started failing.
public struct FirstFailure: Sendable, Equatable {
    /// The test name.
    public let testName: String

    /// The git hash where the test first failed.
    public let introducedInHash: String

    /// The branch where the failure was introduced.
    public let introducedOnBranch: String?

    /// The run ID of the first failing run.
    public let runID: String

    /// The error message from the first failure.
    public let errorMessage: String?

    public init(
        testName: String,
        introducedInHash: String,
        introducedOnBranch: String? = nil,
        runID: String,
        errorMessage: String? = nil
    ) {
        self.testName = testName
        self.introducedInHash = introducedInHash
        self.introducedOnBranch = introducedOnBranch
        self.runID = runID
        self.errorMessage = errorMessage
    }
}

// MARK: - SlowTest

/// A test that exceeds the duration threshold.
public struct SlowTest: Sendable, Equatable {
    /// The test name.
    public let testName: String

    /// The suite containing the test.
    public let suiteName: String?

    /// The source file.
    public let testFile: String

    /// Duration in milliseconds.
    public let durationMs: Int64

    /// The run ID where this slow execution was recorded.
    public let runID: String

    public init(
        testName: String,
        suiteName: String? = nil,
        testFile: String,
        durationMs: Int64,
        runID: String
    ) {
        self.testName = testName
        self.suiteName = suiteName
        self.testFile = testFile
        self.durationMs = durationMs
        self.runID = runID
    }
}

// MARK: - RegressionDetector

/// Detects regressions by comparing test runs stored in SQLite.
///
/// A regression is a test that was green (passed) in a previous run
/// and is now red (failed/timeout) in the current run.
public struct RegressionDetector: Sendable {
    private let store: SQLiteStore

    /// Initialize with a SQLite store.
    ///
    /// - Parameter store: The SQLite store containing test history.
    public init(store: SQLiteStore) {
        self.store = store
    }

    // MARK: - Regression Detection

    /// Compare two test runs and find regressions (green -> red).
    ///
    /// - Parameters:
    ///   - currentRunID: The current (newer) run ID.
    ///   - previousRunID: The previous (older) run ID to compare against.
    /// - Returns: List of regressions (tests that passed before, fail now).
    public func detectRegressions(
        currentRunID: String,
        previousRunID: String
    ) throws -> [Regression] {
        let currentRun = try store.fetchRun(currentRunID)
        let previousRun = try store.fetchRun(previousRunID)

        guard let currentRun, let previousRun else {
            return []
        }

        let currentResults = try store.resultsForRun(currentRunID)
        let previousResults = try store.resultsForRun(previousRunID)

        // Index previous results by test name
        var previousByName: [String: TestResultRow] = [:]
        for result in previousResults {
            previousByName[result.testName] = result
        }

        var regressions: [Regression] = []

        for current in currentResults {
            // Only look at failures and timeouts in the current run
            guard current.status == .failed || current.status == .timeout else { continue }

            // Check if this test was passing in the previous run
            if let previous = previousByName[current.testName],
               previous.status == .passed {
                regressions.append(Regression(
                    testName: current.testName,
                    suiteName: current.suiteName,
                    testFile: current.testFile,
                    errorMessage: current.errorMessage,
                    errorFile: current.errorFile,
                    lastGreenHash: previousRun.gitHash,
                    currentHash: currentRun.gitHash
                ))
            }
        }

        return regressions
    }

    /// Find the first run where a test started failing.
    ///
    /// Walks the test history backwards to find the transition from
    /// passing to failing. Returns the commit that introduced the failure.
    ///
    /// - Parameter testName: The test function name.
    /// - Returns: The first failure info, or nil if the test has always passed or has no history.
    public func findFirstFailure(testName: String) throws -> FirstFailure? {
        let history = try store.historyForTest(testName, limit: 100)

        // History is ordered most recent first.
        // Walk from oldest to newest to find the first failure.
        let chronological = history.reversed()

        var lastPassingIndex: Array<TestResultRow>.Index?
        var firstFailIndex: Array<TestResultRow>.Index?

        for (index, result) in chronological.enumerated() {
            if result.status == .passed {
                lastPassingIndex = index
                firstFailIndex = nil
            } else if result.status == .failed || result.status == .timeout {
                if firstFailIndex == nil {
                    firstFailIndex = index
                }
            }
        }

        // We need a transition: there was a passing run, then a failing run after it
        guard let passIdx = lastPassingIndex else {
            // Never passed — check if first entry is a failure
            if let first = chronological.first,
               (first.status == .failed || first.status == .timeout) {
                let run = try store.fetchRun(first.runID)
                return FirstFailure(
                    testName: testName,
                    introducedInHash: run?.gitHash ?? "unknown",
                    introducedOnBranch: run?.branchName,
                    runID: first.runID,
                    errorMessage: first.errorMessage
                )
            }
            return nil
        }

        // Find the first failure AFTER the last passing run
        let chronologicalArray = Array(chronological)
        for i in (passIdx + 1)..<chronologicalArray.count {
            let result = chronologicalArray[i]
            if result.status == .failed || result.status == .timeout {
                let run = try store.fetchRun(result.runID)
                return FirstFailure(
                    testName: testName,
                    introducedInHash: run?.gitHash ?? "unknown",
                    introducedOnBranch: run?.branchName,
                    runID: result.runID,
                    errorMessage: result.errorMessage
                )
            }
        }

        return nil
    }

    /// Find tests that exceed a duration threshold.
    ///
    /// - Parameter thresholdMs: Duration threshold in milliseconds (default 2000ms = 2s).
    /// - Returns: List of slow tests, ordered by duration descending.
    public func slowTests(thresholdMs: Int64 = 2000) throws -> [SlowTest] {
        let results = try store.slowResults(thresholdMs: thresholdMs)

        return results.compactMap { result in
            guard let durationMs = result.durationMs else { return nil }
            return SlowTest(
                testName: result.testName,
                suiteName: result.suiteName,
                testFile: result.testFile,
                durationMs: durationMs,
                runID: result.runID
            )
        }
    }

    /// Find regressions between the two most recent finished runs.
    ///
    /// Convenience method that auto-selects the latest two runs.
    ///
    /// - Returns: List of regressions, or empty if fewer than 2 runs exist.
    public func detectLatestRegressions() throws -> [Regression] {
        let runs = try store.allRuns(limit: 2)
        guard runs.count >= 2 else { return [] }

        return try detectRegressions(
            currentRunID: runs[0].runID,
            previousRunID: runs[1].runID
        )
    }
}
