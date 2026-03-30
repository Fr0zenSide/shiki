import ArgumentParser
import Foundation
import Logging
import ShikkiKit

/// Full report command with time range, scope, and output format options.
///
/// - BR-R-01: `--daily` and `--weekly` for personal auto-reports
/// - BR-R-02: LOC, PRs, tasks, budget
/// - BR-R-05: TUI table (default), markdown (`--md`), JSON (`--json`)
/// - Wave 4: `--live` for real-time NATS metrics stream
struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Productivity report — metrics across companies, projects, workspace"
    )

    // Time range (default: weekly)
    @Flag(name: .long, help: "Today's activity")
    var daily: Bool = false

    @Flag(name: .long, help: "Last 7 days (default)")
    var weekly: Bool = false

    @Flag(name: .long, help: "Current sprint (2-week window)")
    var sprint: Bool = false

    @Option(name: .long, help: "Custom start date (YYYY-MM-DD)")
    var since: String?

    @Option(name: .customLong("until"), help: "Custom end date (YYYY-MM-DD)")
    var untilDate: String?

    // Scope
    @Option(name: .long, help: "Scope to one company slug")
    var company: String?

    @Option(name: .long, help: "Scope to one project slug")
    var project: String?

    // Output format
    @Flag(name: .long, help: "Markdown output")
    var md: Bool = false

    @Flag(name: .long, help: "JSON output (pipe-friendly)")
    var json: Bool = false

    @Flag(name: .long, help: "Executive board view (CODIR)")
    var codir: Bool = false

    // NATS live mode (Wave 4)
    @Flag(name: .long, help: "Real-time NATS metrics stream — updates every 5 seconds")
    var live: Bool = false

    @Option(name: .long, help: "NATS server URL (for --live mode)")
    var natsUrl: String = "nats://127.0.0.1:4222"

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        if live {
            try await runLive()
        } else {
            try await runStatic()
        }
    }

    // MARK: - Static Report (existing behavior)

    private func runStatic() async throws {
        let timeRange = resolveTimeRange()
        let scope = resolveScope()

        let client = BackendClient(baseURL: url)
        let aggregator = ReportAggregator(client: client)

        let report: Report
        do {
            report = try await aggregator.aggregate(range: timeRange, scope: scope)
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }

        let renderer: ReportRenderer
        if json {
            renderer = JSONReportRenderer()
        } else if md {
            renderer = MarkdownReportRenderer()
        } else {
            renderer = TUIReportRenderer()
        }

        let output: String
        if codir {
            output = renderer.renderCODIR(report)
        } else {
            output = renderer.render(report)
        }

        Swift.print(output)
    }

    // MARK: - Live NATS Mode (Wave 4)

    private func runLive() async throws {
        let nats = MockNATSClient()  // TODO: Replace with real NATSClient when nats.swift is wired
        let aggregator = NATSReportAggregator(nats: nats)

        try await aggregator.start()

        Swift.print("\(ANSI.bold)\(ANSI.cyan)Shikki Live Report\(ANSI.reset) — streaming from NATS")
        Swift.print("\(ANSI.dim)Press Ctrl+C to stop\(ANSI.reset)")
        Swift.print("")

        // Refresh loop: snapshot every 5 seconds
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(5))

            let snapshot = await aggregator.snapshot()
            let rendered = renderLiveSnapshot(snapshot)

            // Clear screen and redraw
            Swift.print("\u{1B}[2J\u{1B}[H", terminator: "")  // ANSI clear screen + home
            Swift.print(rendered)
        }

        await aggregator.stop()
    }

    /// Render a live aggregated report snapshot as ANSI TUI output.
    func renderLiveSnapshot(_ report: AggregatedReport) -> String {
        var lines: [String] = []

        let uptimeStr = formatUptime(report.uptimeSeconds)
        lines.append("\(ANSI.bold)\(ANSI.cyan)Shikki Live Report\(ANSI.reset) — uptime: \(uptimeStr)")
        lines.append(String(repeating: "─", count: 68))

        // Global rates
        let rate1m = report.globalRates["1m"].map { String(format: "%.2f", $0) } ?? "0"
        let rate5m = report.globalRates["5m"].map { String(format: "%.2f", $0) } ?? "0"
        let count1h = report.globalCounts["1h"] ?? 0
        let count24h = report.globalCounts["24h"] ?? 0
        lines.append("Events: \(rate1m)/s (1m) | \(rate5m)/s (5m) | \(count1h) (1h) | \(count24h) (24h)")
        lines.append("")

        // Per-company
        if report.companies.isEmpty {
            lines.append("\(ANSI.dim)No company events yet\(ANSI.reset)")
        } else {
            lines.append("\(ANSI.bold)Company        Events(5m)  Agents  Gates       Decisions\(ANSI.reset)")
            lines.append(String(repeating: "─", count: 68))

            for c in report.companies {
                let events5m = c.eventCounts["5m"] ?? 0
                let gateStr: String
                if c.gateResults.total > 0 {
                    gateStr = "\(c.gateResults.passed)P/\(c.gateResults.failed)F (\(c.gateResults.passRate)%)"
                } else {
                    gateStr = "-"
                }
                let latencyStr: String
                if let lat = c.avgDecisionLatencySeconds {
                    latencyStr = String(format: "%.1fs avg", lat)
                } else {
                    latencyStr = "-"
                }
                let row = [
                    padLive(c.slug, 15),
                    padLive("\(events5m)", 12),
                    padLive("\(c.agentCompletions)", 8),
                    padLive(gateStr, 12),
                    latencyStr,
                ].joined()
                lines.append(row)
            }
        }

        // Agent utilization
        if !report.agents.isEmpty {
            lines.append("")
            lines.append("\(ANSI.bold)Agent Utilization\(ANSI.reset)")
            lines.append(String(repeating: "─", count: 68))
            for agent in report.agents {
                let rate = agent.completionRate
                let rateColor = rate >= 80 ? ANSI.green : (rate >= 50 ? ANSI.yellow : ANSI.red)
                lines.append("  \(agent.agentId) [\(agent.company)] — \(agent.dispatched)d/\(agent.completed)c/\(agent.failed)f \(rateColor)\(rate)%\(ANSI.reset)")
            }
        }

        lines.append("")
        lines.append("\(ANSI.dim)Generated: \(report.generatedAt.shortDisplay)\(ANSI.reset)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Resolution

    func resolveTimeRange() -> ReportTimeRange {
        if daily { return .daily }
        if sprint { return .sprint }

        if let sinceStr = since {
            let formatter = dateFormatter()
            let start = formatter.date(from: sinceStr) ?? Date()
            let end: Date
            if let untilStr = untilDate {
                end = formatter.date(from: untilStr) ?? Date()
            } else {
                end = Date()
            }
            return .custom(start: start, end: end)
        }

        // Default: weekly
        return .weekly
    }

    func resolveScope() -> ReportScope {
        if let company { return .company(company) }
        if let project { return .project(project) }
        return .workspace
    }

    private func dateFormatter() -> DateFormatter {
        DateFormatter.dateOnly
    }

    private func padLive(_ string: String, _ width: Int) -> String {
        if string.count >= width { return string }
        return string + String(repeating: " ", count: width - string.count)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return "\(h)h \(m)m \(s)s"
        } else if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }
}
