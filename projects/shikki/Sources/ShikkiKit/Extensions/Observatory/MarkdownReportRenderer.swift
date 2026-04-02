import Foundation

/// Renders a Report as Markdown output.
public struct MarkdownReportRenderer: ReportRenderer {

    public init() {}

    public func render(_ report: Report) -> String {
        var lines: [String] = []

        lines.append("# Shikki Report — \(formatDate(report.timeRange.start)) to \(formatDate(report.timeRange.end)) (\(report.timeRange.label))")
        lines.append("")
        lines.append("| Company | Tasks | PRs | LOC (+/-) | Budget | Agents |")
        lines.append("|---------|-------|-----|-----------|--------|--------|")

        for c in report.companies {
            let taskStr = "\(c.tasksCompleted)/\(c.tasksTotal)"
            let locStr = "+\(c.locAdded)/-\(c.locDeleted)"
            let budgetStr = "$\(String(format: "%.2f", c.budgetSpent))"
            let agentStr = "\(c.agentCount)"
            lines.append("| \(c.slug) | \(taskStr) | \(c.prsMerged) | \(locStr) | \(budgetStr) | \(agentStr) |")
        }

        let t = report.totals
        lines.append("| **TOTAL** | **\(t.tasksCompleted)/\(t.tasksTotal)** | **\(t.prsMerged)** | **+\(t.locAdded)/-\(t.locDeleted)** | **$\(String(format: "%.2f", t.budgetSpent))** | **\(t.agentCount)** |")
        lines.append("")

        if !report.blocked.isEmpty {
            lines.append("## Blocked")
            lines.append("")
            for b in report.blocked {
                lines.append("- **[\(b.companySlug)]** \(b.title) — \(b.reason ?? "unknown")")
            }
            lines.append("")
        }

        if report.pendingDecisions > 0 {
            lines.append("**Decisions pending:** \(report.pendingDecisions)")
            lines.append("")
        }

        lines.append("**Sessions:** \(report.sessions.count)")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    public func renderCODIR(_ report: Report) -> String {
        var lines: [String] = []

        lines.append("# CODIR Board")
        lines.append("")
        lines.append("**Budget:** $\(String(format: "%.2f", report.totals.budgetSpent)) spent")
        lines.append("")

        for c in report.companies {
            let pct = c.tasksTotal > 0 ? (c.tasksCompleted * 100) / c.tasksTotal : 0
            lines.append("## \(c.displayName) (\(c.tasksCompleted)/\(c.tasksTotal) tasks, \(pct)%)")
            lines.append("")
            lines.append("- \(c.prsMerged) PR(s) merged")
            let health = pct >= 70 ? "ON TRACK" : pct >= 50 ? "AT RISK" : "BEHIND"
            lines.append("- Sprint health: **\(health)**")
            lines.append("")
        }

        if !report.blocked.isEmpty {
            lines.append("## Risks")
            lines.append("")
            for b in report.blocked {
                lines.append("- **[\(b.companySlug)]** \(b.title) — \(b.reason ?? "no details")")
            }
            lines.append("")
        }

        let netLOC = report.totals.locAdded - report.totals.locDeleted
        lines.append("**Net output:** +\(report.totals.locAdded) / -\(report.totals.locDeleted) LOC (net \(netLOC >= 0 ? "+" : "")\(netLOC))")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func formatDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }
}
