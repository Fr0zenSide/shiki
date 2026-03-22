import ArgumentParser
import ShikiCtlKit

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Show daily cross-company digest"
    )

    @Option(name: .long, help: "Date (YYYY-MM-DD), defaults to today")
    var date: String?

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let client = BackendClient(baseURL: url)
        let report: DailyReport
        do {
            report = try await client.getDailyReport(date: date)
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }

        print("\u{1B}[1m\u{1B}[36mDaily Report — \(report.date)\u{1B}[0m")
        print(String(repeating: "─", count: 60))

        // Per-company table
        let header = [
            pad("Company", 15), pad("Done", 6), pad("Fail", 6),
            pad("Asked", 6), pad("Ans'd", 6), pad("Spend", 8),
        ].joined(separator: " ")
        print("\u{1B}[1m\(header)\u{1B}[0m")

        for c in report.perCompany {
            let row = [
                pad(c.slug, 15),
                pad("\(c.tasksCompleted)", 6),
                pad("\(c.tasksFailed)", 6),
                pad("\(c.decisionsAsked)", 6),
                pad("\(c.decisionsAnswered)", 6),
                pad("$\(String(format: "%.2f", c.spendUsd))", 8),
            ].joined(separator: " ")
            print(row)
        }

        // Blocked tasks
        if !report.blocked.isEmpty {
            print()
            print("\u{1B}[31mBlocked Tasks:\u{1B}[0m")
            for b in report.blocked {
                let question = b.question ?? "no question"
                print("  [\(b.companySlug)] \(b.title) — T\(b.tier ?? 0): \(question)")
            }
        }

        // PRs created
        if !report.prsCreated.isEmpty {
            print()
            print("\u{1B}[32mPRs Created:\u{1B}[0m")
            for pr in report.prsCreated {
                let project = pr.projectSlug ?? "?"
                let title = pr.title ?? pr.branch ?? "untitled"
                let prUrl = pr.prUrl ?? ""
                print("  [\(project)] \(title) \(prUrl)")
            }
        }
    }

    private func pad(_ string: String, _ width: Int) -> String {
        if string.count >= width { return string }
        return string + String(repeating: " ", count: width - string.count)
    }
}
