import ArgumentParser
import Foundation
import ShikkiKit

/// Query the enterprise audit trail.
///
/// Usage:
///   shi audit --user bob --since 2026-03-01
///   shi audit --project maya --json
///   shi audit --tool search --limit 50
struct AuditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Query the enterprise audit trail (SOC 2 / ISO 27001 ready)"
    )

    @Option(name: .long, help: "Filter by user ID")
    var user: String?

    @Option(name: .long, help: "Filter by project slug")
    var project: String?

    @Option(name: .long, help: "Filter by workspace ID")
    var workspace: String?

    @Option(name: .long, help: "Filter by tool name")
    var tool: String?

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var since: String?

    @Option(name: .customLong("until"), help: "End date (YYYY-MM-DD)")
    var untilDate: String?

    @Option(name: .long, help: "Maximum events to return")
    var limit: Int = 100

    @Flag(name: .long, help: "JSON output (pipe-friendly)")
    var json: Bool = false

    @Flag(name: .long, help: "Show security incidents")
    var security: Bool = false

    @Flag(name: .long, help: "Show budget status")
    var budget: Bool = false

    func run() async throws {
        let query = buildQuery()

        // For now, audit reads from in-memory store.
        // Future: connect to ShikiDB audit_events table.
        let store = InMemoryAuditStore()
        let logger = AuditLogger(store: store)

        if security {
            printSecurityHeader()
            return
        }

        if budget {
            printBudgetHeader()
            return
        }

        let report = try await logger.generateReport(query: query)

        if json {
            let output = try AuditReportFormatter.renderJSON(report)
            print(output)
        } else {
            let output = AuditReportFormatter.renderText(report)
            print(output)
        }
    }

    private func buildQuery() -> AuditQuery {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let sinceDate = since.flatMap { formatter.date(from: $0) }
        let untilDate = untilDate.flatMap { formatter.date(from: $0) }

        return AuditQuery(
            userId: user,
            projectSlug: project,
            workspaceId: workspace,
            toolName: tool,
            since: sinceDate,
            until: untilDate,
            limit: limit
        )
    }

    private func printSecurityHeader() {
        print("Security Incident Dashboard")
        print("===========================")
        print("No incidents recorded (audit trail empty).")
        print("")
        print("Patterns monitored:")
        print("  - Bulk extraction (100+ queries/5min)")
        print("  - Cross-project scan (5+ projects)")
        print("  - Off-hours access")
        print("  - Export pattern (sequential memory reads)")
        print("  - Burnout signals (16h+ continuous usage)")
        print("  - Knowledge hoarding (80%+ single-user queries)")
    }

    private func printBudgetHeader() {
        print("Budget ACL Dashboard")
        print("====================")
        print("No budget policies configured.")
        print("")
        print("Supported periods: daily, weekly, monthly")
        print("Inheritance: workspace default -> team override -> user override")
    }
}
