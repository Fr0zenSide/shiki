import Foundation

// MARK: - ReviewProvider Protocol

/// Abstraction for LLM-backed review operations.
/// Concrete implementations invoke Claude or another LLM; tests inject a mock.
/// All methods return structured results — the LLM is a worker, Swift is the judge.
public protocol ReviewProvider: Sendable {
    /// Run a CTO-level architecture review on the given diff.
    /// Returns structured findings with a pass/fail verdict.
    func runCtoReview(diff: String, featureSpec: String?) async throws -> ReviewResult

    /// Run an AI slop scan on the given source files.
    /// Returns detected AI markers (placeholder comments, generic variable names, etc.).
    func runSlopScan(sources: [String]) async throws -> SlopScanResult
}

// MARK: - ReviewResult

/// Structured output from a CTO review gate.
public struct ReviewResult: Sendable {
    public let passed: Bool
    public let findings: [ReviewFinding]
    public let summary: String

    public init(passed: Bool, findings: [ReviewFinding], summary: String) {
        self.passed = passed
        self.findings = findings
        self.summary = summary
    }
}

// MARK: - ReviewFinding

/// A single finding from a code review.
public struct ReviewFinding: Sendable {
    public enum Severity: String, Sendable {
        case critical
        case warning
        case info
    }

    public let severity: Severity
    public let file: String?
    public let line: Int?
    public let message: String

    public init(severity: Severity, file: String? = nil, line: Int? = nil, message: String) {
        self.severity = severity
        self.file = file
        self.line = line
        self.message = message
    }
}

// MARK: - SlopScanResult

/// Structured output from an AI slop scan.
public struct SlopScanResult: Sendable {
    public let clean: Bool
    public let markers: [SlopMarker]
    public let summary: String

    public init(clean: Bool, markers: [SlopMarker], summary: String) {
        self.clean = clean
        self.markers = markers
        self.summary = summary
    }
}

// MARK: - SlopMarker

/// A single AI slop marker detected in source code.
public struct SlopMarker: Sendable {
    public let file: String
    public let line: Int
    public let pattern: String
    public let context: String

    public init(file: String, line: Int, pattern: String, context: String) {
        self.file = file
        self.line = line
        self.pattern = pattern
        self.context = context
    }
}
