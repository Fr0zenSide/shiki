import Foundation

/// ANSI TUI table renderer for reports.
/// Follows the same ANSI patterns as StatusRenderer.
public struct TUIReportRenderer: ReportRenderer {

    public init() {}

    public func render(_ report: Report) -> String {
        var lines: [String] = []

        // Header
        let title = "Shikki Report — \(formatDate(report.timeRange.start)) → \(formatDate(report.timeRange.end)) (\(report.timeRange.label))"
        lines.append("\u{1B}[1m\u{1B}[36m\(title)\u{1B}[0m")
        lines.append(String(repeating: "─", count: 68))
        lines.append("")

        // Company table header
        let header = [
            pad("Company", 14), pad("Tasks", 10), pad("PRs", 5),
            pad("LOC (+/-)", 14), pad("Budget", 9), pad("Agents", 10),
        ].joined(separator: " ")
        lines.append("\u{1B}[1m\(header)\u{1B}[0m")
        lines.append(String(repeating: "─", count: 68))

        // Company rows
        for c in report.companies {
            let taskStr = "\(c.tasksCompleted)/\(c.tasksTotal)"
            let locStr = "+\(formatNumber(c.locAdded))/-\(formatNumber(c.locDeleted))"
            let budgetStr = "$\(String(format: "%.2f", c.budgetSpent))"
            let agentStr = c.agentCount > 0
                ? "\(c.agentCount) (avg \(c.avgContextPct)% ctx)"
                : "0"
            let row = [
                pad(c.slug, 14), pad(taskStr, 10), pad("\(c.prsMerged)", 5),
                pad(locStr, 14), pad(budgetStr, 9), agentStr,
            ].joined(separator: " ")
            lines.append(row)
        }

        // Totals
        lines.append(String(repeating: "─", count: 68))
        let t = report.totals
        let totalRow = [
            pad("TOTAL", 14),
            pad("\(t.tasksCompleted)/\(t.tasksTotal)", 10),
            pad("\(t.prsMerged)", 5),
            pad("+\(formatNumber(t.locAdded))/-\(formatNumber(t.locDeleted))", 14),
            pad("$\(String(format: "%.2f", t.budgetSpent))", 9),
            "\(t.agentCount)",
        ].joined(separator: " ")
        lines.append("\u{1B}[1m\(totalRow)\u{1B}[0m")

        // Blocked tasks
        if !report.blocked.isEmpty {
            lines.append("")
            lines.append("\u{1B}[31mBlocked: \(report.blocked.count) task(s)\u{1B}[0m")
            for b in report.blocked {
                let reason = b.reason ?? "unknown"
                lines.append("  [\(b.companySlug)] \(b.title) — \(reason)")
            }
        }

        // Decisions
        if report.pendingDecisions > 0 {
            lines.append("Decisions pending: \(report.pendingDecisions)")
        }

        // Sessions
        lines.append("")
        let avgPerDay = report.sessions.count > 0
            ? String(format: "%.1f", Double(report.sessions.count) / max(1.0, daysInRange(report.timeRange)))
            : "0"
        lines.append("Sessions: \(report.sessions.count) (avg \(avgPerDay)/day)")

        if report.compactions > 0 {
            let compactionsPerDay = String(format: "%.1f", Double(report.compactions) / max(1.0, daysInRange(report.timeRange)))
            lines.append("Compactions: \(report.compactions) total (avg \(compactionsPerDay)/day)")
        }

        return lines.joined(separator: "\n")
    }

    public func renderCODIR(_ report: Report) -> String {
        var lines: [String] = []

        // CODIR Header
        let weekNumber = weekOfYear(from: report.timeRange.start)
        lines.append("\u{1B}[1mCODIR Board — Week \(weekNumber)\u{1B}[0m")
        lines.append(String(repeating: "═", count: 40))
        lines.append("")

        // Budget overview
        let totalBudget = report.totals.budgetSpent
        lines.append("Budget: $\(String(format: "%.2f", totalBudget)) spent")
        lines.append("")

        // Per-company progress — BR-R-04: aggregates only, no individual worker metrics
        for c in report.companies {
            let pct = c.tasksTotal > 0 ? (c.tasksCompleted * 100) / c.tasksTotal : 0
            let bar = progressBar(percent: pct, width: 20)
            lines.append("\(c.displayName) (\(c.tasksCompleted)/\(c.tasksTotal) tasks, \(pct)%)")
            lines.append("  \(bar) \(pct)%")
            lines.append("  \(c.prsMerged) PR(s) merged.")

            let health: String
            if pct >= 70 {
                health = "\u{1B}[32mON TRACK\u{1B}[0m"
            } else if pct >= 50 {
                health = "\u{1B}[33mAT RISK\u{1B}[0m"
            } else {
                health = "\u{1B}[31mBEHIND\u{1B}[0m"
            }
            lines.append("  Sprint health: \(health)")
            lines.append("")
        }

        // Risks
        if !report.blocked.isEmpty {
            lines.append("Risks:")
            for b in report.blocked {
                let reason = b.reason ?? "no details"
                lines.append("  [\(b.companySlug)] \(b.title) — \(reason)")
            }
            lines.append("")
        }

        // Net output
        let netLOC = report.totals.locAdded - report.totals.locDeleted
        lines.append("Net output: +\(formatNumber(report.totals.locAdded)) / -\(formatNumber(report.totals.locDeleted)) LOC (net \(netLOC >= 0 ? "+" : "")\(formatNumber(netLOC)))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    func pad(_ string: String, _ width: Int) -> String {
        let visibleLength = string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "",
            options: .regularExpression
        ).count
        if visibleLength >= width { return string }
        return string + String(repeating: " ", count: width - visibleLength)
    }

    func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    func formatDate(_ iso: String) -> String {
        // Return just YYYY-MM-DD from ISO 8601
        String(iso.prefix(10))
    }

    func progressBar(percent: Int, width: Int) -> String {
        let filled = (percent * width) / 100
        let empty = width - filled
        let filledStr = String(repeating: "\u{2588}", count: filled)
        let emptyStr = String(repeating: "\u{2591}", count: empty)
        return filledStr + emptyStr
    }

    func weekOfYear(from isoDate: String) -> Int {
        guard let date = ISO8601DateFormatter.standard.date(from: isoDate) else { return 0 }
        return Calendar.current.component(.weekOfYear, from: date)
    }

    func daysInRange(_ range: ReportDateRange) -> Double {
        guard let start = ISO8601DateFormatter.standard.date(from: range.start),
              let end = ISO8601DateFormatter.standard.date(from: range.end) else { return 1.0 }
        return max(1.0, end.timeIntervalSince(start) / 86400.0)
    }
}
