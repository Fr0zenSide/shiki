import ArgumentParser
import Foundation
import ShikkiKit

/// Display agent report cards — per-persona effectiveness tracking.
///
/// Examples:
///   shi agent-reports                        # all recent report cards
///   shi agent-reports --session maya:wave3    # specific session
///   shi agent-reports --company maya          # all maya sessions
///   shi agent-reports --persona implement     # only implementers
///   shi agent-reports --md                    # markdown output
struct AgentReportsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-reports",
        abstract: "Display agent report cards — per-persona effectiveness tracking"
    )

    @Option(name: .long, help: "Filter by session ID")
    var session: String?

    @Option(name: .long, help: "Filter by company slug")
    var company: String?

    @Option(name: .long, help: "Filter by persona (implement, investigate, verify, critique, review, fix)")
    var persona: String?

    @Flag(name: .long, help: "Show expanded report cards (default: collapsed)")
    var expanded: Bool = false

    @Flag(name: .long, help: "Markdown output")
    var md: Bool = false

    @Flag(name: .long, help: "JSON output (pipe-friendly)")
    var json: Bool = false

    @Option(name: .long, help: "Base path for decision journal")
    var decisionsPath: String?

    @Option(name: .long, help: "Base path for session journal")
    var journalPath: String?

    func run() async throws {
        let decisionJournal = DecisionJournal(basePath: decisionsPath)
        let sessionJournal = SessionJournal(basePath: journalPath)
        let generator = AgentReportGenerator()

        // Load all decisions to find sessions with decisions
        let allDecisions = try await decisionJournal.loadAllDecisions()

        // Group decisions by session
        let sessionGroups = Dictionary(grouping: allDecisions, by: \.sessionId)

        // Filter by criteria
        var reports: [AgentReportCard] = []
        for (sessionId, decisions) in sessionGroups {
            // Apply session filter
            if let session, sessionId != session { continue }

            // Apply company filter
            let sessionCompany = decisions.first?.companySlug
            if let company, sessionCompany != company { continue }

            // Apply persona filter
            let sessionPersona = decisions.first?.agentPersona
            if let persona, sessionPersona != persona { continue }

            let resolvedPersona = sessionPersona.flatMap { AgentPersona(rawValue: $0) } ?? .implement

            let report = generator.generate(
                sessionId: sessionId,
                persona: resolvedPersona,
                companySlug: sessionCompany ?? "unknown",
                taskTitle: extractTaskTitle(from: sessionId),
                startedAt: decisions.first?.timestamp ?? Date(),
                endedAt: decisions.last?.timestamp ?? Date(),
                decisions: decisions,
                status: .completed
            )
            reports.append(report)
        }

        // Sort: running first, then by most recent
        reports.sort { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            return lhs.duration > rhs.duration
        }

        guard !reports.isEmpty else {
            print("\u{1B}[2mNo agent reports found.\u{1B}[0m")
            return
        }

        if json {
            renderJSON(reports)
        } else if md {
            renderMarkdown(reports)
        } else {
            renderTUI(reports)
        }
    }

    // MARK: - Rendering

    private func renderTUI(_ reports: [AgentReportCard]) {
        let reset = "\u{1B}[0m"
        let bold = "\u{1B}[1m"

        print("\(bold)Agent Report Cards\(reset) (\(reports.count) sessions)")
        print(String(repeating: "\u{2500}", count: 60))

        for report in reports {
            print()
            print(report.renderTUI(expanded: expanded))
        }
    }

    private func renderMarkdown(_ reports: [AgentReportCard]) {
        for report in reports {
            print(report.renderMarkdown())
            print("---\n")
        }
    }

    private func renderJSON(_ reports: [AgentReportCard]) {
        // Build JSON manually since AgentReportCard is not Codable
        var entries: [[String: Any]] = []
        for report in reports {
            entries.append([
                "sessionId": report.sessionId,
                "persona": report.persona.rawValue,
                "companySlug": report.companySlug,
                "taskTitle": report.taskTitle,
                "duration": report.duration,
                "filesChanged": report.filesChanged,
                "testsAdded": report.testsAdded,
                "keyDecisions": report.keyDecisions,
                "redFlags": report.redFlags,
                "status": "\(report.status)",
            ])
        }

        if let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    // MARK: - Helpers

    private func extractTaskTitle(from sessionId: String) -> String {
        // Session IDs often have format "company:task-description"
        if let colonIdx = sessionId.firstIndex(of: ":") {
            return String(sessionId[sessionId.index(after: colonIdx)...])
        }
        return sessionId
    }
}
