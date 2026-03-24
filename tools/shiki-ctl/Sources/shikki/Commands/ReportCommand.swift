import ArgumentParser
import Foundation
import ShikiCtlKit

/// Full report command with time range, scope, and output format options.
///
/// - BR-R-01: `--daily` and `--weekly` for personal auto-reports
/// - BR-R-02: LOC, PRs, tasks, budget
/// - BR-R-05: TUI table (default), markdown (`--md`), JSON (`--json`)
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

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
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

        print(output)
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }
}
