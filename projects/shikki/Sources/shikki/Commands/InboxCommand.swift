import ArgumentParser
import Foundation
import ShikkiKit

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

    @Flag(name: .long, help: "Strip colors for piping")
    var plain: Bool = false

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
        let output = InboxRenderer.render(
            items: items,
            branch: currentBranch(),
            plain: plain
        )
        Swift.print(output)
    }

    private func currentBranch() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "develop" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "develop")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
