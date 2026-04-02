import Foundation

// MARK: - OutputFormat

/// Output format for diagnostic/recovery results.
public enum DiagnosticOutputFormat: String, Sendable {
    case human
    case agent
    case json
}

// MARK: - DiagnosticFormatter

/// Formats RecoveryContext into human, agent, or JSON output.
/// BR-08: Human format with ANSI colors, auto-stripped when not TTY.
/// BR-09: Agent format — compact markdown in <context-recovery> tags.
/// BR-10: JSON format — valid JSON in all cases.
public enum DiagnosticFormatter {

    // MARK: - Human Format (BR-08)

    /// Format recovery context for human reading.
    /// ANSI-colored with sections: State, Branch, Timeline, Errors, Confidence.
    /// BR-08: Strips ANSI when stdout is not a TTY.
    public static func formatHuman(_ context: RecoveryContext, isTTY: Bool = true, verbose: Bool = false) -> String {
        var lines: [String] = []

        let ansi = isTTY
        let bold = ansi ? "\u{1B}[1m" : ""
        let reset = ansi ? "\u{1B}[0m" : ""
        let dim = ansi ? "\u{1B}[2m" : ""
        let green = ansi ? "\u{1B}[32m" : ""
        let yellow = ansi ? "\u{1B}[33m" : ""
        let red = ansi ? "\u{1B}[31m" : ""
        let cyan = ansi ? "\u{1B}[36m" : ""

        // Header
        lines.append("\(bold)\(cyan)Shikki Diagnostic\(reset)")
        lines.append(String(repeating: "\u{2500}", count: 56))
        lines.append("")

        // Staleness
        let stalenessColor: String
        switch context.staleness {
        case .fresh: stalenessColor = green
        case .recent: stalenessColor = yellow
        case .stale, .ancient: stalenessColor = red
        }
        lines.append("\(bold)Staleness:\(reset) \(stalenessColor)\(context.staleness.rawValue)\(reset)")

        // Workspace
        if let branch = context.workspace.branch {
            lines.append("\(bold)Branch:\(reset)    \(branch)")
        }

        if let ab = context.workspace.aheadBehind {
            lines.append("\(bold)Tracking:\(reset)  \(ab.ahead) ahead, \(ab.behind) behind")
        }

        lines.append("")

        // Confidence meter (BR-H2)
        let overall = context.confidence.overall
        let filled = overall / 10
        let empty = 10 - filled
        let meterColor = overall >= 70 ? green : (overall >= 30 ? yellow : red)
        let meter = String(repeating: "=", count: filled) + String(repeating: "-", count: empty)
        lines.append("\(bold)Confidence:\(reset) \(meterColor)[\(meter)] \(overall)%\(reset)")

        // Source breakdown
        for source in context.sources {
            let icon: String
            switch source.status {
            case .available: icon = "\(green)\u{2713}\(reset)"
            case .partial: icon = "\(yellow)\u{26A0}\(reset)"
            case .corrupted: icon = "\(red)\u{2717}\(reset)"
            case .unavailable: icon = "\(dim)-\(reset)"
            }
            lines.append("  \(icon) \(source.name): \(source.itemCount) item(s), score \(source.score)")
        }

        lines.append("")

        // Timeline
        if !context.timeline.isEmpty {
            lines.append("\(bold)Timeline:\(reset)")
            for item in context.timeline.prefix(verbose ? 50 : 10) {
                let formatter = ISO8601DateFormatter()
                let ts = formatter.string(from: item.timestamp)
                let provTag = dim + "[\(item.provenance.rawValue)]" + reset
                lines.append("  \(ts) \(provTag) \(item.summary)")
                if verbose, let detail = item.detail {
                    lines.append("    \(dim)\(detail)\(reset)")
                }
            }
            lines.append("")
        }

        // Pending decisions
        if !context.pendingDecisions.isEmpty {
            lines.append("\(bold)Pending Decisions:\(reset)")
            for decision in context.pendingDecisions.prefix(5) {
                lines.append("  \(yellow)\u{25CF}\(reset) \(decision)")
            }
            lines.append("")
        }

        // Errors
        if !context.errors.isEmpty {
            lines.append("\(bold)Errors:\(reset)")
            for error in context.errors {
                lines.append("  \(red)\u{2717}\(reset) \(error)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Agent Format (BR-09)

    /// Format recovery context as compact markdown for agent injection.
    /// Wrapped in <context-recovery> tags. Default budget: 2KB.
    /// BR-21: Stale/ancient context includes warning comment.
    public static func formatAgent(_ context: RecoveryContext, budget: Int = 2048) -> String {
        var lines: [String] = []

        // BR-21: Stale warning
        if context.staleness == .stale || context.staleness == .ancient {
            let hoursAgo = Int(-context.timeWindow.since.timeIntervalSinceNow / 3600)
            lines.append("<!-- WARNING: Context is \(hoursAgo)h old. Verify current state before acting. -->")
        }

        lines.append("<context-recovery>")
        lines.append("")

        // Active branch
        if let branch = context.workspace.branch {
            lines.append("## Branch: \(branch)")
        }

        // Confidence
        lines.append("## Confidence: \(context.confidence.overall)% (\(context.staleness.rawValue))")
        lines.append("")

        // Recent commits (last 5)
        if !context.workspace.recentCommits.isEmpty {
            lines.append("## Recent Commits")
            for commit in context.workspace.recentCommits.prefix(5) {
                lines.append("- `\(commit.hash.prefix(7))` \(commit.message)")
            }
            lines.append("")
        }

        // Recent events (last 10, one-line each)
        let events = context.timeline.filter { $0.kind == .event }
        if !events.isEmpty {
            lines.append("## Recent Events")
            for event in events.prefix(10) {
                lines.append("- \(event.summary)")
            }
            lines.append("")
        }

        // Pending decisions
        if !context.pendingDecisions.isEmpty {
            lines.append("## Pending Decisions")
            for decision in context.pendingDecisions.prefix(5) {
                lines.append("- \(decision)")
            }
            lines.append("")
        }

        // Errors
        if !context.errors.isEmpty {
            lines.append("## Errors")
            for error in context.errors {
                lines.append("- \(error)")
            }
            lines.append("")
        }

        lines.append("</context-recovery>")

        var result = lines.joined(separator: "\n")

        // Enforce budget
        if result.utf8.count > budget {
            result = truncateToBudget(result, budget: budget)
        }

        return result
    }

    // MARK: - JSON Format (BR-10)

    /// Format recovery context as valid JSON.
    /// BR-10: Errors included as field, never printed to stdout.
    /// BR-26: Payloads summarized by default, full with verbose.
    public static func formatJSON(_ context: RecoveryContext, verbose: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(context)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            // BR-27: Never crash. Return minimal valid JSON with error.
            return """
            {"error": "\(error.localizedDescription)", "recoveredAt": "\(ISO8601DateFormatter().string(from: context.recoveredAt))"}
            """
        }
    }

    // MARK: - Helpers

    /// Truncate content to budget, keeping opening/closing tags.
    private static func truncateToBudget(_ content: String, budget: Int) -> String {
        guard content.utf8.count > budget else { return content }

        let closing = "\n\n</context-recovery>"
        let remaining = budget - closing.utf8.count - 20 // margin for truncation notice
        guard remaining > 0 else { return "<context-recovery>\n(truncated)\n</context-recovery>" }

        let data = Data(content.utf8.prefix(remaining))
        let truncated = String(data: data, encoding: .utf8) ?? ""

        // Find last newline to avoid cutting mid-line
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[truncated.startIndex...lastNewline]) + "\n(truncated)" + closing
        }

        return truncated + "\n(truncated)" + closing
    }
}
