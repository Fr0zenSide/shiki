import ArgumentParser
import ShikiCtlKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show orchestrator status overview"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Flag(name: .long, help: "Use legacy table format")
    var legacy: Bool = false

    func run() async throws {
        let client = BackendClient(baseURL: url)

        guard try await client.healthCheck() else {
            try await client.shutdown()
            print("\u{1B}[31mError:\u{1B}[0m Backend unreachable at \(url)")
            print("Start it with: docker compose up -d")
            throw ExitCode.failure
        }

        let status: OrchestratorStatus
        do {
            status = try await client.getStatus()
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
        let overview = status.overview

        // Header
        print("\u{1B}[1m\u{1B}[36mShiki Orchestrator\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 56))

        if overview.t1PendingDecisions > 0 {
            print("\u{1B}[33m\u{26A0} \(overview.t1PendingDecisions) T1 decision(s) pending\u{1B}[0m")
            print()
        }

        // Dispatcher-style or legacy table
        if legacy {
            // Overview row
            print("\u{1B}[1mOverview:\u{1B}[0m \(overview.activeCompanies) active companies | "
                + "\(overview.totalPendingTasks) pending | "
                + "\(overview.totalRunningTasks) running | "
                + "\(overview.totalBlockedTasks) blocked | "
                + "$\(String(format: "%.2f", overview.todayTotalSpend)) spent today")

            if !status.activeCompanies.isEmpty {
                print()
                StatusRenderer.renderCompanyTable(status.activeCompanies)
            }
        } else {
            StatusRenderer.renderDispatcherStatus(companies: status.activeCompanies)
        }

        // Pending decisions
        if !status.pendingDecisions.isEmpty {
            print("\u{1B}[1mPending Decisions:\u{1B}[0m")
            for d in status.pendingDecisions {
                let slug = d.companySlug ?? "?"
                let tierColor = d.tier == 1 ? "\u{1B}[31m" : "\u{1B}[33m"
                print("  \(tierColor)T\(d.tier)\u{1B}[0m [\(slug)] \(d.question)")
            }
            print()
        }

        // Package locks
        if !status.packageLocks.isEmpty {
            print("\u{1B}[1mPackage Locks:\u{1B}[0m")
            for lock in status.packageLocks {
                print("  \(lock.packageName) \u{2192} \(lock.companySlug) (since \(lock.claimedAt ?? "?"))")
            }
            print()
        }

        // Stale companies
        if !status.staleCompanies.isEmpty {
            print("\u{1B}[31mStale Companies:\u{1B}[0m")
            for c in status.staleCompanies {
                print("  \(c.slug) \u{2014} last heartbeat: \(c.lastHeartbeatAt ?? "never")")
            }
            print()
        }

        print("\u{1B}[2mTimestamp: \(status.timestamp)\u{1B}[0m")
    }
}
