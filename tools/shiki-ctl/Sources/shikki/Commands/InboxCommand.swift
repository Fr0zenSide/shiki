import ArgumentParser
import Foundation
import ShikiCtlKit

struct InboxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Unified pending items list — PRs, decisions, specs, tasks, gate results"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    // MARK: - Type Filters

    @Flag(name: .long, help: "Show PRs only")
    var prs: Bool = false

    @Flag(name: .long, help: "Show decisions only")
    var decisions: Bool = false

    @Flag(name: .long, help: "Show specs only")
    var specs: Bool = false

    @Flag(name: .long, help: "Show tasks only")
    var tasks: Bool = false

    @Flag(name: .long, help: "Show gate results only")
    var gates: Bool = false

    // MARK: - Scope Filters

    @Option(name: .long, help: "Filter by company slug")
    var company: String?

    // MARK: - Output Modes

    @Flag(name: .long, help: "Output count only")
    var count: Bool = false

    @Flag(name: .long, help: "Output JSON for piping")
    var json: Bool = false

    @Option(name: .long, help: "Sort by: urgency (default), age, type")
    var sort: String = "urgency"

    func run() async throws {
        let client = BackendClient(baseURL: url)
        let manager = InboxManager(client: client)

        let filters = buildFilters()
        let items: [InboxItem]

        do {
            items = try await manager.fetchAll(filters: filters)
        } catch {
            try? await client.shutdown()
            throw error
        }

        let sorted = applySorting(items)

        if count {
            renderCount(sorted)
        } else if json {
            try renderJSON(sorted)
        } else {
            renderList(sorted)
        }

        try await client.shutdown()
    }

    // MARK: - Filter Building

    private func buildFilters() -> InboxFilters {
        var types: Set<InboxItem.ItemType>?
        let flagTypes: [(Bool, InboxItem.ItemType)] = [
            (prs, .pr), (decisions, .decision), (specs, .spec),
            (tasks, .task), (gates, .gate),
        ]
        let activeTypes = flagTypes.filter(\.0).map(\.1)
        if !activeTypes.isEmpty {
            types = Set(activeTypes)
        }
        return InboxFilters(companySlug: company, types: types)
    }

    // MARK: - Sorting

    private func applySorting(_ items: [InboxItem]) -> [InboxItem] {
        switch sort {
        case "age":
            return items.sorted { $0.age > $1.age }
        case "type":
            return items.sorted { $0.type.rawValue < $1.type.rawValue }
        default: // urgency (already sorted by manager)
            return items
        }
    }

    // MARK: - Rendering

    private func renderCount(_ items: [InboxItem]) {
        if prs || decisions || specs || tasks || gates {
            // Filtered count
            Swift.print(items.count)
        } else {
            // Full breakdown
            let prCount = items.filter { $0.type == .pr }.count
            let decisionCount = items.filter { $0.type == .decision }.count
            let specCount = items.filter { $0.type == .spec }.count
            let taskCount = items.filter { $0.type == .task }.count
            let gateCount = items.filter { $0.type == .gate }.count
            Swift.print("PRs: \(prCount)  Decisions: \(decisionCount)  Specs: \(specCount)  Tasks: \(taskCount)  Gates: \(gateCount)  Total: \(items.count)")
        }
    }

    private func renderJSON(_ items: [InboxItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        if let string = String(data: data, encoding: .utf8) {
            Swift.print(string)
        }
    }

    private func renderList(_ items: [InboxItem]) {
        guard !items.isEmpty else {
            Swift.print("Inbox is empty.")
            return
        }

        Swift.print("\u{1B}[1mInbox (\(items.count) items)\u{1B}[0m")
        Swift.print()

        for item in items {
            let typeIcon = typeSymbol(item.type)
            let urgencyColor = urgencyColorCode(item.urgencyScore)
            let ageStr = formatAge(item.age)
            let companyTag = item.companySlug.map { " \u{1B}[36m[\($0)]\u{1B}[0m" } ?? ""

            Swift.print(
                "  \(typeIcon) \(urgencyColor)\(item.urgencyScore)\u{1B}[0m "
                    + "\u{1B}[1m\(item.title)\u{1B}[0m"
                    + companyTag
                    + " \u{1B}[2m(\(ageStr))\u{1B}[0m"
            )
            if let subtitle = item.subtitle {
                Swift.print("    \u{1B}[2m\(subtitle)\u{1B}[0m")
            }
        }

        Swift.print()
        Swift.print("\u{1B}[2mPipe to review: shikki review inbox | Filtered: shikki inbox --prs\u{1B}[0m")
    }

    private func typeSymbol(_ type: InboxItem.ItemType) -> String {
        switch type {
        case .pr: return "\u{1B}[32mPR\u{1B}[0m"
        case .decision: return "\u{1B}[33mDC\u{1B}[0m"
        case .spec: return "\u{1B}[35mSP\u{1B}[0m"
        case .task: return "\u{1B}[34mTK\u{1B}[0m"
        case .gate: return "\u{1B}[31mGT\u{1B}[0m"
        }
    }

    private func urgencyColorCode(_ score: Int) -> String {
        switch score {
        case 70...: return "\u{1B}[31m"  // red
        case 40..<70: return "\u{1B}[33m"  // yellow
        default: return "\u{1B}[32m"  // green
        }
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        if hours < 1 { return "<1h" }
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
