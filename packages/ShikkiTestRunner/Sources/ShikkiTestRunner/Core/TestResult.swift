// TestResult.swift — Test execution result models
// Part of ShikkiTestRunner

import Foundation

/// Status of an individual test.
public enum TestStatus: String, Sendable, Hashable, Codable {
    case passed
    case failed
    case skipped
    case timeout
}

/// Result for a single test case.
public struct TestCaseResult: Sendable, Hashable {
    public let testName: String
    public let suiteName: String
    public let status: TestStatus
    public let durationMs: Int
    public let errorMessage: String?
    public let errorFile: String?
    public let rawOutput: String

    public init(
        testName: String,
        suiteName: String = "",
        status: TestStatus,
        durationMs: Int = 0,
        errorMessage: String? = nil,
        errorFile: String? = nil,
        rawOutput: String = ""
    ) {
        self.testName = testName
        self.suiteName = suiteName
        self.status = status
        self.durationMs = durationMs
        self.errorMessage = errorMessage
        self.errorFile = errorFile
        self.rawOutput = rawOutput
    }
}

/// Aggregated result for a scope group.
public struct ScopeResult: Sendable {
    public let scope: TestScope
    public let results: [TestCaseResult]
    public let startedAt: Date
    public let finishedAt: Date
    public let rawOutput: String

    public var passed: Int { results.filter { $0.status == .passed }.count }
    public var failed: Int { results.filter { $0.status == .failed }.count }
    public var skipped: Int { results.filter { $0.status == .skipped }.count }
    public var timedOut: Int { results.filter { $0.status == .timeout }.count }
    public var total: Int { results.count }
    public var durationMs: Int {
        Int(finishedAt.timeIntervalSince(startedAt) * 1000)
    }

    /// Number of failures (tests that need attention).
    public var failureCount: Int { failed }

    /// Number of unknowns (skipped + timeout).
    public var unknownCount: Int { skipped + timedOut }

    /// True if all tests passed.
    public var allPassed: Bool { failed == 0 && timedOut == 0 && skipped == 0 }

    /// Failed test results.
    public var failures: [TestCaseResult] {
        results.filter { $0.status == .failed }
    }

    /// Skipped/timeout test results.
    public var unknowns: [TestCaseResult] {
        results.filter { $0.status == .skipped || $0.status == .timeout }
    }

    public init(
        scope: TestScope,
        results: [TestCaseResult],
        startedAt: Date,
        finishedAt: Date,
        rawOutput: String = ""
    ) {
        self.scope = scope
        self.results = results
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.rawOutput = rawOutput
    }
}

/// Full test run result across all scopes.
public struct TestRunResult: Sendable {
    public let runID: String
    public let scopeResults: [ScopeResult]
    public let gitHash: String
    public let branchName: String
    public let startedAt: Date
    public let finishedAt: Date
    public let isPartialRun: Bool
    public let totalScopeCount: Int

    public var passed: Int { scopeResults.reduce(0) { $0 + $1.passed } }
    public var failed: Int { scopeResults.reduce(0) { $0 + $1.failed } }
    public var skipped: Int { scopeResults.reduce(0) { $0 + $1.skipped } }
    public var timedOut: Int { scopeResults.reduce(0) { $0 + $1.timedOut } }
    public var total: Int { scopeResults.reduce(0) { $0 + $1.total } }
    public var durationMs: Int {
        Int(finishedAt.timeIntervalSince(startedAt) * 1000)
    }

    public var failureCount: Int { failed }
    public var unknownCount: Int { skipped + timedOut }
    public var allPassed: Bool { failed == 0 && timedOut == 0 && skipped == 0 }

    public init(
        runID: String = UUID().uuidString,
        scopeResults: [ScopeResult],
        gitHash: String,
        branchName: String,
        startedAt: Date,
        finishedAt: Date,
        isPartialRun: Bool = false,
        totalScopeCount: Int
    ) {
        self.runID = runID
        self.scopeResults = scopeResults
        self.gitHash = gitHash
        self.branchName = branchName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isPartialRun = isPartialRun
        self.totalScopeCount = totalScopeCount
    }
}
