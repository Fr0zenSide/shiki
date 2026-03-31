// TUIReporter.swift — Scope results as one-liners with SF Symbol markers
// Part of ShikkiTestRunner

import Foundation

/// Verbosity level for TUI output.
public enum Verbosity: Sendable {
    case clean      // One-liners only
    case verbose    // One-liners + log file path at end
    case live       // One-liners + real-time log streaming
}

/// SF Symbol markers for test status.
public enum StatusMarker: Sendable {
    /// 􁁛 All passed
    case allPassed
    /// 􀢄 Has failures
    case hasFailures
    /// 􀟈 Partial run (not all scopes tested)
    case partialRun

    public var symbol: String {
        switch self {
        case .allPassed: return "\u{10184D}"    // 􁁛
        case .hasFailures: return "\u{100894}"   // 􀢄
        case .partialRun: return "\u{1007C8}"    // 􀟈
        }
    }
}

/// Renders test results as compact one-liner TUI output.
///
/// Format per scope:
///   `<marker> [HH:MM:SS] <scope> [duration] passed/total`
///   Failures: `!!N` suffix + N detail lines below
///   Skipped/timeout: `??N` suffix + N detail lines below
///
/// Summary line:
///   `<marker> [HH:MM:SS] <git_hash> <branch> [duration] passed/total [!!N] [??N]`
public struct TUIReporter: Sendable {
    public let verbosity: Verbosity
    public let logFilePath: String?

    public init(verbosity: Verbosity = .clean, logFilePath: String? = nil) {
        self.verbosity = verbosity
        self.logFilePath = logFilePath
    }

    // MARK: - Scope Line Rendering

    /// Render a single scope result as a one-liner (+ detail lines if failures).
    public func renderScopeLine(_ result: ScopeResult) -> String {
        let marker = result.allPassed ? StatusMarker.allPassed : StatusMarker.hasFailures
        let time = formatTime(result.startedAt)
        let duration = formatDuration(result.durationMs)
        let scopeName = result.scope.name.padding(toLength: 12, withPad: " ", startingAt: 0)

        var line = "  \(marker.symbol) [\(time)] \(scopeName) [\(duration)]  \(result.passed)/\(result.total)"

        if result.failureCount > 0 {
            line += " !!\(result.failureCount)"
        }

        if result.unknownCount > 0 {
            line += " ??\(result.unknownCount)"
        }

        // Append failure detail lines
        let details = renderDetailLines(result)
        if !details.isEmpty {
            line += "\n" + details
        }

        return line
    }

    /// Render detail lines for failures and unknowns.
    public func renderDetailLines(_ result: ScopeResult) -> String {
        var lines: [String] = []

        for failure in result.failures {
            let duration = formatDuration(failure.durationMs)
            let name = "\(failure.suiteName)/\(failure.testName)"
            let message = failure.errorMessage ?? "failed"
            lines.append("    [\(duration)] \(name) \u{2014} \(message)")
        }

        for unknown in result.unknowns {
            let status = unknown.status == .skipped ? "skipped" : "timeout"
            let reason = unknown.errorMessage ?? status
            let name = "\(unknown.suiteName)/\(unknown.testName)"
            lines.append("    [??]     \(name) \u{2014} \(reason)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Summary Line Rendering

    /// Render the summary separator + summary line for a full test run.
    public func renderSummary(_ run: TestRunResult) -> String {
        let separator = "  \u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}"

        let marker: StatusMarker
        if run.isPartialRun {
            marker = run.allPassed ? .partialRun : .hasFailures
        } else {
            marker = run.allPassed ? .allPassed : .hasFailures
        }

        let time = formatTime(run.finishedAt)
        let shortHash = String(run.gitHash.prefix(7))
        let duration = formatDuration(run.durationMs)

        var summaryLine = "  \(marker.symbol) [\(time)] \(shortHash) \(run.branchName) [\(duration)] \(run.passed)/\(run.total)"

        if run.failureCount > 0 {
            summaryLine += " !!\(run.failureCount)"
        }

        if run.unknownCount > 0 {
            summaryLine += " ??\(run.unknownCount)"
        }

        var output = separator + "\n" + summaryLine

        // Verbose: append log file path
        if verbosity == .verbose || verbosity == .live, let logFilePath {
            output += "\n\n  Full log: \(logFilePath)"
        }

        return output
    }

    // MARK: - Full Report

    /// Render a complete test run report (all scope lines + summary).
    public func renderFullReport(_ run: TestRunResult) -> String {
        var lines: [String] = []

        for scopeResult in run.scopeResults {
            lines.append(renderScopeLine(scopeResult))
        }

        lines.append(renderSummary(run))

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting Helpers

    /// Format a Date as HH:MM:SS.
    public func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    /// Format milliseconds as a human-readable duration string.
    public func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "0.\(ms / 100)s"
        } else if ms < 60000 {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = ms / 60000
            let seconds = (ms % 60000) / 1000
            return "\(minutes)m\(seconds)s"
        }
    }
}
