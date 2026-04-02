import ArgumentParser
import Foundation
import ShikkiKit

/// Query and display architecture decisions from the Decision Journal.
///
/// Examples:
///   shi decisions                          # all decisions, most recent first
///   shi decisions --session maya:spm-wave3 # decisions for a specific session
///   shi decisions --category architecture  # only architecture decisions
///   shi decisions --chain <uuid>           # show decision chain from root
struct DecisionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decisions",
        abstract: "Query architecture decisions from the Decision Journal"
    )

    @Option(name: .long, help: "Filter by session ID")
    var session: String?

    @Option(name: .long, help: "Filter by category (architecture, implementation, process, tradeOff, scope)")
    var category: String?

    @Option(name: .long, help: "Filter by impact (architecture, implementation, process)")
    var impact: String?

    @Option(name: .long, help: "Filter by company slug")
    var company: String?

    @Option(name: .long, help: "Show decision chain from this decision UUID")
    var chain: String?

    @Option(name: .long, help: "Filter decisions since date (YYYY-MM-DD)")
    var since: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int?

    @Flag(name: .long, help: "JSON output (pipe-friendly)")
    var json: Bool = false

    @Option(name: .long, help: "Base path for decision journal")
    var path: String?

    func run() async throws {
        let journal = DecisionJournal(basePath: path)

        // Chain mode: show full chain from a decision
        if let chainId = chain, let uuid = UUID(uuidString: chainId) {
            try await renderChain(journal: journal, rootId: uuid)
            return
        }

        // Build query
        let query = DecisionQuery(
            sessionId: session,
            companySlug: company,
            category: category.flatMap { DecisionCategory(rawValue: $0) },
            impact: impact.flatMap { DecisionImpact(rawValue: $0) },
            since: since.flatMap { parseDateString($0) }
        )

        let decisions = try await journal.query(query)
        let sorted = decisions.sorted { $0.timestamp > $1.timestamp }
        let limited = limit.map { Array(sorted.prefix($0)) } ?? sorted

        if json {
            renderJSON(limited)
        } else {
            renderTUI(limited)
        }
    }

    // MARK: - Rendering

    private func renderTUI(_ decisions: [DecisionEvent]) {
        guard !decisions.isEmpty else {
            print("\u{1B}[2mNo decisions found.\u{1B}[0m")
            return
        }

        let reset = "\u{1B}[0m"
        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"

        print("\(bold)Decision Journal\(reset) (\(decisions.count) entries)")
        print(String(repeating: "\u{2500}", count: 60))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for decision in decisions {
            let icon = categoryIcon(decision.category)
            let impactColor = impactColor(decision.impact)
            let dateStr = formatter.string(from: decision.timestamp)
            let confidenceStr = String(format: "%.0f%%", decision.confidence * 100)

            print()
            print("\(icon) \(bold)\(decision.question)\(reset)")
            print("  \(impactColor)\(decision.impact.rawValue)\(reset) | \(decision.category.rawValue) | \(confidenceStr) confidence")
            print("  \u{2192} \(decision.choice)")
            print("  \(dim)\(decision.rationale)\(reset)")

            if !decision.alternatives.isEmpty {
                print("  \(dim)Alternatives: \(decision.alternatives.joined(separator: ", "))\(reset)")
            }
            if !decision.tags.isEmpty {
                print("  \(dim)Tags: \(decision.tags.joined(separator: ", "))\(reset)")
            }
            print("  \(dim)\(dateStr) | \(decision.sessionId)\(reset)")

            if let parentId = decision.parentDecisionId {
                print("  \(dim)\u{2514}\u{2500} parent: \(parentId.uuidString.prefix(8))...\(reset)")
            }
        }
    }

    private func renderJSON(_ decisions: [DecisionEvent]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(decisions),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    private func renderChain(journal: DecisionJournal, rootId: UUID) async throws {
        guard let chain = try await journal.buildFullChain(from: rootId) else {
            print("\u{1B}[31mDecision not found: \(rootId)\u{1B}[0m")
            return
        }

        let reset = "\u{1B}[0m"
        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"

        print("\(bold)Decision Chain\(reset) (depth: \(chain.depth))")
        print(String(repeating: "\u{2500}", count: 60))

        for (i, decision) in chain.allDecisions.enumerated() {
            let prefix = i == 0 ? "\u{25C6}" : "  \u{2514}\u{2500}"
            let icon = categoryIcon(decision.category)
            print("\(prefix) \(icon) \(bold)\(decision.question)\(reset)")
            print("    \u{2192} \(decision.choice)")
            print("    \(dim)\(decision.rationale)\(reset)")
        }
    }

    // MARK: - Helpers

    private func categoryIcon(_ category: DecisionCategory) -> String {
        switch category {
        case .architecture: "\u{1B}[1m\u{1B}[35m\u{25C6}\u{1B}[0m"  // bold magenta diamond
        case .implementation: "\u{1B}[36m\u{25CF}\u{1B}[0m"           // cyan circle
        case .process: "\u{1B}[33m\u{25B2}\u{1B}[0m"                  // yellow triangle
        case .tradeOff: "\u{1B}[34m\u{2194}\u{1B}[0m"                 // blue arrow
        case .scope: "\u{1B}[32m\u{25A0}\u{1B}[0m"                    // green square
        }
    }

    private func impactColor(_ impact: DecisionImpact) -> String {
        switch impact {
        case .architecture: "\u{1B}[1m\u{1B}[31m"  // bold red
        case .implementation: "\u{1B}[36m"           // cyan
        case .process: "\u{1B}[33m"                  // yellow
        }
    }

    private func parseDateString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: str)
    }
}
