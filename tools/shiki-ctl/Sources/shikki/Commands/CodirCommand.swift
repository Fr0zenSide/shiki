import ArgumentParser
import Foundation
import ShikiCtlKit

/// Executive board summary — alias for `shikki report --codir`.
///
/// - BR-R-04: CODIR mode shows project/team aggregates. No individual worker metrics.
struct CodirCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codir",
        abstract: "Executive board summary — stakeholder view"
    )

    @Flag(name: .long, help: "Today's activity")
    var daily: Bool = false

    @Flag(name: .long, help: "Last 7 days (default)")
    var weekly: Bool = false

    @Flag(name: .long, help: "Current sprint (2-week window)")
    var sprint: Bool = false

    @Option(name: .long, help: "Scope to one company slug")
    var company: String?

    // Output format
    @Flag(name: .long, help: "Markdown output")
    var md: Bool = false

    @Flag(name: .long, help: "JSON output")
    var json: Bool = false

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let timeRange: ReportTimeRange
        if daily { timeRange = .daily }
        else if sprint { timeRange = .sprint }
        else { timeRange = .weekly }

        let scope: ReportScope
        if let company { scope = .company(company) }
        else { scope = .workspace }

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

        print(renderer.renderCODIR(report))
    }
}
