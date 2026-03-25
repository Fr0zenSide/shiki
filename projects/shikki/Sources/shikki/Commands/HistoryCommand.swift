import ArgumentParser
import ShikkiKit

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show session transcript history for a company"
    )

    @Argument(help: "Company slug (e.g. maya, wabisabi)")
    var company: String?

    @Option(name: .long, help: "Filter by task ID")
    var task: String?

    @Option(name: .long, help: "Filter by phase (plan, implement, completed, failed)")
    var phase: String?

    @Option(name: .long, help: "Number of entries to show")
    var limit: Int = 10

    @Option(name: .long, help: "Show full detail for a specific transcript ID")
    var detail: String?

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Flag(name: .long, help: "Include raw log output")
    var raw: Bool = false

    func run() async throws {
        let client = BackendClient(baseURL: url)
        defer { Task { try? await client.shutdown() } }

        guard try await client.healthCheck() else {
            print("\u{1B}[31mError:\u{1B}[0m Backend unreachable at \(url)")
            throw ExitCode.failure
        }

        // Detail view for a single transcript
        if let detailId = detail {
            let transcript = try await client.getSessionTranscript(id: detailId)
            renderDetail(transcript)
            return
        }

        // List view
        let transcripts = try await client.getSessionTranscripts(
            companySlug: company, taskId: task, limit: limit
        )

        if transcripts.isEmpty {
            let scope = company ?? "all companies"
            print("\u{1B}[2mNo session transcripts found for \(scope)\u{1B}[0m")
            return
        }

        print("\u{1B}[1m\u{1B}[36mSession History\u{1B}[0m")
        if let company { print("\u{1B}[2mCompany: \(company)\u{1B}[0m") }
        print(String(repeating: "\u{2500}", count: 72))
        print()

        for t in transcripts {
            let phaseColor = phaseColor(t.phase)
            let date = formatDate(t.createdAt)
            let duration = t.durationMinutes.map { "\($0)min" } ?? "?"
            let files = t.filesChanged.count
            let prs = t.prsCreated.count

            print("\u{1B}[1m[\(t.companySlug)] \(t.taskTitle)\u{1B}[0m")
            print("  \(phaseColor)\(t.phase)\u{1B}[0m | \(date) | \(duration) | \(files) files | \(prs) PRs")

            if let summary = t.summary, !summary.isEmpty {
                // Show first 2 lines of summary
                let lines = summary.split(separator: "\n", maxSplits: 2).prefix(2)
                for line in lines {
                    print("  \u{1B}[2m\(line)\u{1B}[0m")
                }
            }

            if !t.errors.isEmpty {
                print("  \u{1B}[31m\(t.errors.count) error(s)\u{1B}[0m")
            }

            print("  \u{1B}[2mid: \(t.id)\u{1B}[0m")
            print()
        }
    }

    private func renderDetail(_ t: SessionTranscript) {
        let phaseColor = phaseColor(t.phase)

        print("\u{1B}[1m\u{1B}[36m[\(t.companySlug)] \(t.taskTitle)\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 72))
        print("  Phase:    \(phaseColor)\(t.phase)\u{1B}[0m")
        print("  Date:     \(formatDate(t.createdAt))")
        if let d = t.durationMinutes { print("  Duration: \(d) min") }
        if let c = t.contextPct { print("  Context:  \(c)%") }
        print("  Compactions: \(t.compactionCount)")
        if let p = t.projectPath { print("  Project:  \(p)") }

        if let summary = t.summary, !summary.isEmpty {
            print()
            print("\u{1B}[1mSummary:\u{1B}[0m")
            print(summary)
        }

        if let plan = t.planOutput, !plan.isEmpty {
            print()
            print("\u{1B}[1mPlan:\u{1B}[0m")
            print(plan)
        }

        if !t.filesChanged.isEmpty {
            print()
            print("\u{1B}[1mFiles Changed (\(t.filesChanged.count)):\u{1B}[0m")
            for f in t.filesChanged { print("  \(f)") }
        }

        if !t.prsCreated.isEmpty {
            print()
            print("\u{1B}[1mPRs Created:\u{1B}[0m")
            for pr in t.prsCreated { print("  \(pr)") }
        }

        if let tests = t.testResults, !tests.isEmpty {
            print()
            print("\u{1B}[1mTest Results:\u{1B}[0m")
            print(tests)
        }

        if !t.errors.isEmpty {
            print()
            print("\u{1B}[31m\u{1B}[1mErrors:\u{1B}[0m")
            for e in t.errors { print("  \u{1B}[31m\(e)\u{1B}[0m") }
        }

        if raw, let log = t.rawLog, !log.isEmpty {
            print()
            print("\u{1B}[1mRaw Log:\u{1B}[0m")
            print(log)
        }
    }

    private func phaseColor(_ phase: String) -> String {
        switch phase {
        case "completed": return "\u{1B}[32m"
        case "failed": return "\u{1B}[31m"
        case "blocked": return "\u{1B}[33m"
        case "plan": return "\u{1B}[36m"
        case "implement": return "\u{1B}[34m"
        case "review": return "\u{1B}[35m"
        default: return "\u{1B}[2m"
        }
    }

    private func formatDate(_ iso: String) -> String {
        // Extract just YYYY-MM-DD HH:MM from ISO timestamp
        let parts = iso.split(separator: "T")
        guard parts.count >= 2 else { return iso }
        let time = parts[1].prefix(5)
        return "\(parts[0]) \(time)"
    }
}
