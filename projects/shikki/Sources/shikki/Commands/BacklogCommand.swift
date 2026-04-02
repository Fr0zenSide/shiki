import ArgumentParser
import Foundation
import ShikkiKit

struct BacklogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backlog",
        abstract: "Manage the idea backlog — add, list, enrich, promote, kill",
        subcommands: [
            BacklogAddSubcommand.self,
        ],
        defaultSubcommand: nil
    )

    // MARK: - Filters

    @Option(name: .long, help: "Filter by status (raw, enriched, ready, deferred, killed)")
    var status: String?

    @Option(name: .long, help: "Filter by company slug or ID")
    var company: String?

    @Option(name: .long, help: "Sort order: priority, age, manual")
    var sort: String?

    @Flag(name: .long, help: "Show killed items")
    var killed = false

    // MARK: - Output modes

    @Flag(name: .long, help: "Output JSON (pipe mode)")
    var json = false

    @Flag(name: .long, help: "Output count only")
    var count = false

    // MARK: - Connection

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let client = BackendClient(baseURL: url)
        let manager = BacklogManager(client: client)

        // Determine status filter
        let statusFilter: BacklogItem.Status?
        if killed {
            statusFilter = .killed
        } else if let statusStr = status {
            guard let s = BacklogItem.Status(rawValue: statusStr) else {
                throw ValidationError("Invalid status '\(statusStr)'. Valid: raw, enriched, ready, deferred, killed")
            }
            statusFilter = s
        } else {
            statusFilter = nil
        }

        let sortFilter: BacklogSort?
        if let sortStr = sort {
            guard let s = BacklogSort(rawValue: sortStr) else {
                throw ValidationError("Invalid sort '\(sortStr)'. Valid: priority, age, manual")
            }
            sortFilter = s
        } else {
            sortFilter = nil
        }

        // Count mode
        if count {
            let n = try await manager.count(status: statusFilter, companyId: company)
            if json {
                print("{\"count\":\(n)}")
            } else {
                print(n)
            }
            return
        }

        // List mode
        let items: [BacklogItem]
        if let statusFilter {
            items = try await manager.list(status: statusFilter, companyId: company, sort: sortFilter)
        } else {
            items = try await manager.listActive(companyId: company, sort: sortFilter)
        }

        // JSON output
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        // Interactive/text list output
        guard !items.isEmpty else {
            let label = statusFilter?.rawValue ?? "active"
            print("No \(label) backlog items.")
            return
        }

        printBacklogList(items)
    }

    // MARK: - Rendering

    private func printBacklogList(_ items: [BacklogItem]) {
        let dim = "\u{1B}[2m"
        let bold = "\u{1B}[1m"
        let reset = "\u{1B}[0m"
        let green = "\u{1B}[32m"
        let yellow = "\u{1B}[33m"
        let red = "\u{1B}[31m"
        let cyan = "\u{1B}[36m"

        print("\(bold)Backlog\(reset) (\(items.count) items)")
        print()

        for (i, item) in items.enumerated() {
            let statusColor: String
            switch item.status {
            case .raw: statusColor = dim
            case .enriched: statusColor = cyan
            case .ready: statusColor = green
            case .deferred: statusColor = yellow
            case .killed: statusColor = red
            }

            let number = String(format: "%2d", i + 1)
            let statusTag = "\(statusColor)\(item.status.rawValue)\(reset)"
            let priorityTag = item.priority != 50 ? " P\(item.priority)" : ""
            let tagsStr = item.tags.isEmpty ? "" : " \(dim)[\(item.tags.joined(separator: ", "))]\(reset)"

            print("  \(dim)\(number).\(reset) \(statusTag) \(bold)\(item.title)\(reset)\(priorityTag)\(tagsStr)")

            if let desc = item.description, !desc.isEmpty {
                let truncated = desc.count > 80 ? String(desc.prefix(77)) + "..." : desc
                print("      \(dim)\(truncated)\(reset)")
            }

            if let notes = item.enrichmentNotes, !notes.isEmpty {
                let truncated = notes.count > 60 ? String(notes.prefix(57)) + "..." : notes
                print("      \(dim)notes: \(truncated)\(reset)")
            }

            if let reason = item.killReason, !reason.isEmpty {
                print("      \(red)killed: \(reason)\(reset)")
            }
        }

        print()
        print("\(dim)Commands: shi backlog add \"idea\" | --json | --count | --status <s>\(reset)")
    }
}

// MARK: - Add Subcommand

struct BacklogAddSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Quick-add an idea to the backlog"
    )

    @Argument(help: "The idea title")
    var title: String

    @Option(name: .long, help: "Company slug or ID")
    var company: String?

    @Option(name: .long, help: "Priority (0-99, default 50)")
    var priority: Int?

    @Option(name: .long, help: "Comma-separated tags")
    var tags: String?

    @Option(name: .long, help: "Source type: manual, push, flsh, conversation, agent")
    var source: String?

    @Flag(name: .long, help: "Output JSON")
    var json = false

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let client = BackendClient(baseURL: url)
        let manager = BacklogManager(client: client)

        let sourceType: BacklogItem.SourceType
        if let src = source {
            guard let s = BacklogItem.SourceType(rawValue: src) else {
                throw ValidationError("Invalid source '\(src)'. Valid: manual, push, flsh, conversation, agent")
            }
            sourceType = s
        } else {
            sourceType = .manual
        }

        let tagList = tags?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) } ?? []

        if let priority, (priority < 0 || priority > 99) {
            throw ValidationError("Priority must be 0-99")
        }

        let item = try await manager.add(
            title: title,
            companyId: company,
            sourceType: sourceType,
            priority: priority,
            tags: tagList
        )

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(item)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        } else {
            print("Added: \(item.title) [\(item.status.rawValue)] (id: \(item.id))")
        }
    }
}
