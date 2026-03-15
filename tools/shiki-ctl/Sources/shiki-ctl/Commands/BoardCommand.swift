import ArgumentParser
import Foundation
import ShikiCtlKit

struct BoardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Rich board overview — companies, tasks, budget, health, last session"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let client = BackendClient(baseURL: url)
        defer { Task { try? await client.shutdown() } }

        guard try await client.healthCheck() else {
            print("\u{1B}[31mError:\u{1B}[0m Backend unreachable at \(url)")
            throw ExitCode.failure
        }

        let board = try await client.getBoardOverview()

        print("\u{1B}[1m\u{1B}[36mShiki Board\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 80))

        if board.isEmpty {
            print("\u{1B}[2mNo companies found\u{1B}[0m")
            return
        }

        // Group by status
        let active = board.filter { $0.companyStatus == "active" }
        let paused = board.filter { $0.companyStatus == "paused" }

        let totalTasks = board.reduce(0) { $0 + $1.totalTasks }
        let totalRunning = board.reduce(0) { $0 + $1.runningTasks }
        let totalPending = board.reduce(0) { $0 + $1.pendingTasks }
        let totalSpent = board.reduce(0.0) { $0 + $1.spentToday }

        print("\u{1B}[1mOverview:\u{1B}[0m \(board.count) companies | \(totalRunning) running | \(totalPending) queued | \(totalTasks) total tasks | $\(String(format: "%.2f", totalSpent)) today")
        print()

        for entry in active {
            renderEntry(entry)
        }

        if !paused.isEmpty {
            print("\u{1B}[33m\u{1B}[1mPaused:\u{1B}[0m")
            for entry in paused {
                print("  \u{1B}[2m\(entry.companySlug) (\(entry.displayName))\u{1B}[0m")
            }
            print()
        }

        let formatter = ISO8601DateFormatter()
        print("\u{1B}[2mTimestamp: \(formatter.string(from: Date()))\u{1B}[0m")
    }

    private func renderEntry(_ e: BoardEntry) {
        let healthColor: String
        switch e.heartbeatStatus {
        case "healthy": healthColor = "\u{1B}[32m"
        case "stale": healthColor = "\u{1B}[33m"
        case "dead": healthColor = "\u{1B}[31m"
        default: healthColor = "\u{1B}[2m"
        }

        let spent = String(format: "%.0f", e.spentToday)
        let daily = String(format: "%.0f", e.budget.dailyUsd)
        let projectInfo = e.projectCount > 1 ? " (\(e.projectCount) projects)" : ""

        // Company header
        print("\u{1B}[1m\(e.companySlug)\u{1B}[0m \(e.displayName)\(projectInfo)  \(healthColor)\(e.heartbeatStatus)\u{1B}[0m  $\(spent)/$\(daily)")

        // Task bar
        let done = e.completedTasks
        let run = e.runningTasks
        let pend = e.pendingTasks
        let blk = e.blockedTasks
        let fail = e.failedTasks
        var taskLine = "  Tasks:"
        if run > 0 { taskLine += " \u{1B}[32m\(run) running\u{1B}[0m" }
        if pend > 0 { taskLine += " \(pend) pending" }
        if blk > 0 { taskLine += " \u{1B}[33m\(blk) blocked\u{1B}[0m" }
        if fail > 0 { taskLine += " \u{1B}[31m\(fail) failed\u{1B}[0m" }
        taskLine += " | \(done)/\(e.totalTasks) done"
        print(taskLine)

        // Progress bar
        if e.totalTasks > 0 {
            let pct = Double(done) / Double(e.totalTasks)
            let barWidth = 30
            let filled = Int(pct * Double(barWidth))
            let bar = String(repeating: "\u{2588}", count: filled) + String(repeating: "\u{2591}", count: barWidth - filled)
            print("  [\(bar)] \(Int(pct * 100))%")
        }

        // Pending decisions
        if e.pendingDecisions > 0 {
            print("  \u{1B}[33m\u{26A0} \(e.pendingDecisions) pending decision(s)\u{1B}[0m")
        }

        // Last session
        if let summary = e.lastSessionSummary {
            let phase = e.lastSessionPhase ?? "?"
            let phaseColor: String
            switch phase {
            case "completed": phaseColor = "\u{1B}[32m"
            case "failed": phaseColor = "\u{1B}[31m"
            case "blocked": phaseColor = "\u{1B}[33m"
            default: phaseColor = "\u{1B}[2m"
            }
            let date = formatDate(e.lastSessionAt ?? "")
            print("  Last: \(phaseColor)\(phase)\u{1B}[0m \(date)")
            // First line of summary
            let firstLine = summary.split(separator: "\n").first.map(String.init) ?? summary
            let truncated = firstLine.count > 70 ? String(firstLine.prefix(67)) + "..." : firstLine
            print("  \u{1B}[2m\(truncated)\u{1B}[0m")
        }

        print()
    }

    private func formatDate(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let parts = iso.split(separator: "T")
        guard parts.count >= 2 else { return iso }
        let time = parts[1].prefix(5)
        return "\(parts[0]) \(time)"
    }
}
