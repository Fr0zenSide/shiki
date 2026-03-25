import ArgumentParser
import Foundation
import ShikkiKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show orchestrator status overview"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Flag(name: .long, help: "Use legacy table format")
    var legacy: Bool = false

    @Flag(name: .long, help: "Show local session registry with attention zones")
    var showRegistry: Bool = false

    @Flag(name: .long, help: "Single-line output for tmux status bar")
    var mini: Bool = false

    @Flag(name: .long, help: "Toggle between compact and expanded tmux format")
    var toggleExpand: Bool = false

    @Option(name: .long, help: "Set arrow separator style: none, left, right, both (Dracula-style powerline arrows)")
    var arrowStyle: String?

    @Flag(name: .long, help: "Git status for tmux: branch, staged, modified, ahead/behind")
    var git: Bool = false

    @Flag(name: .long, help: "Project context for tmux: language version + test status")
    var project: Bool = false

    @Option(name: .long, help: "Working directory for git/project detection (default: cwd)")
    var path: String?

    @Flag(name: .long, help: "Strip ANSI colors from output (for tmux status-right)")
    var plain: Bool = false

    func run() async throws {
        // Handle arrow style change: persist and continue
        if let arrowRaw = arrowStyle {
            let stateManager = TmuxStateManager()
            if let style = ArrowStyle(rawValue: arrowRaw) {
                stateManager.setArrowStyle(style)
            }
        }

        // Handle toggle-expand: flip state and continue with mini output
        if toggleExpand {
            let stateManager = TmuxStateManager()
            stateManager.toggle()
        }

        // Git segment for tmux
        if git {
            runGit()
            return
        }

        // Project segment for tmux
        if project {
            runProject()
            return
        }

        // Mini mode: single-line output for tmux
        if mini || toggleExpand {
            try await runMini()
            return
        }

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

        // Header with workspace info
        print("\u{1B}[1m\u{1B}[36mShiki Orchestrator\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 56))

        // Workspace & sessions info
        let workspace = resolveCurrentWorkspace()
        let sessions = detectShikiSessions()
        let currentSession = URL(fileURLWithPath: workspace).lastPathComponent

        print("\u{1B}[2mWorkspace:\u{1B}[0m \(workspace)")
        if sessions.count > 1 {
            print("\u{1B}[2mSessions:\u{1B}[0m  \(sessions.map { $0 == currentSession ? "\u{1B}[32m\($0) ●\u{1B}[0m" : "\u{1B}[2m\($0)\u{1B}[0m" }.joined(separator: "  "))")
        } else if sessions.count == 1 {
            print("\u{1B}[2mSession:\u{1B}[0m   \(sessions[0]) \u{1B}[32m●\u{1B}[0m")
        } else {
            print("\u{1B}[2mSession:\u{1B}[0m   \u{1B}[33mnot running\u{1B}[0m")
        }
        print(String(repeating: "\u{2500}", count: 56))

        if overview.t1PendingDecisions > 0 {
            print("\u{1B}[33m\u{26A0} \(overview.t1PendingDecisions) T1 decision(s) pending\u{1B}[0m")
            print()
        }

        // Session registry view (attention-zone sorted)
        if showRegistry {
            let registry = SessionRegistry(
                discoverer: TmuxDiscoverer(),
                journal: SessionJournal()
            )
            await registry.refresh()
            let sorted = await registry.sessionsByAttention()

            if sorted.isEmpty {
                print("\u{1B}[2mNo active sessions\u{1B}[0m")
            } else {
                print("\u{1B}[1mSessions (by attention):\u{1B}[0m")
                for session in sorted {
                    let zoneLabel = StatusRenderer.formatAttentionZone(session.attentionZone)
                    let stateStr = "\u{1B}[2m\(session.state.rawValue)\u{1B}[0m"
                    print("  \(zoneLabel) \(StatusRenderer.pad(session.windowName, 25)) \(stateStr)")
                }
            }
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

    // MARK: - Mini Mode

    private func runMini() async throws {
        let stateManager = TmuxStateManager()
        let registry = SessionRegistry(
            discoverer: TmuxDiscoverer(),
            journal: SessionJournal()
        )
        await registry.refresh()
        let sessions = await registry.allSessions

        // Try to get backend data for questions and budget
        let client = BackendClient(baseURL: url)
        let isHealthy = (try? await client.healthCheck()) ?? false

        if !isHealthy {
            try? await client.shutdown()
            // No trailing newline for tmux
            print(MiniStatusFormatter.formatUnreachable(arrowStyle: stateManager.arrowStyle), terminator: "")
            return
        }

        var pendingQuestions = 0
        var spentUsd: Double = 0
        var budgetUsd: Double = 0

        do {
            let status = try await client.getStatus()
            try await client.shutdown()
            pendingQuestions = status.overview.totalPendingDecisions
            spentUsd = status.overview.todayTotalSpend
            // Sum daily budgets across active companies
            budgetUsd = status.activeCompanies.reduce(0) { $0 + $1.budget.dailyUsd }
        } catch {
            try? await client.shutdown()
        }

        let arrows = stateManager.arrowStyle
        let output: String
        if stateManager.isExpanded {
            output = MiniStatusFormatter.formatExpanded(
                sessions: sessions, pendingQuestions: pendingQuestions,
                spentUsd: spentUsd, budgetUsd: budgetUsd,
                arrowStyle: arrows
            )
        } else {
            output = MiniStatusFormatter.formatCompact(
                sessions: sessions, pendingQuestions: pendingQuestions,
                spentUsd: spentUsd, budgetUsd: budgetUsd,
                arrowStyle: arrows
            )
        }
        // No trailing newline for tmux status bar
        print(output, terminator: "")
    }

    // MARK: - ANSI Stripping

    private func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "",
            options: .regularExpression
        )
    }

    // MARK: - Git Segment

    private func runGit() {
        let dir = path ?? FileManager.default.currentDirectoryPath
        let stateManager = TmuxStateManager()
        let arrows = stateManager.arrowStyle

        guard let info = GitStatusFormatter.collectGitInfo(at: dir) else {
            let out = GitStatusFormatter.formatNoRepo(arrowStyle: arrows)
            print(plain ? stripANSI(out) : out, terminator: "")
            return
        }
        let out = GitStatusFormatter.format(info, arrowStyle: arrows)
        print(plain ? stripANSI(out) : out, terminator: "")
    }

    // MARK: - Project Segment

    private func runProject() {
        let dir = path ?? FileManager.default.currentDirectoryPath
        let stateManager = TmuxStateManager()
        let arrows = stateManager.arrowStyle

        let projectInfo = ProjectStatusFormatter.detectProject(at: dir)
        let testStatus = ProjectStatusFormatter.readCachedTests(at: dir)
        let out = ProjectStatusFormatter.format(project: projectInfo, tests: testStatus, arrowStyle: arrows)
        print(plain ? stripANSI(out) : out, terminator: "")
    }

    // MARK: - Workspace Detection

    /// Same resolution logic as StartupCommand — symlink → known path → cwd
    private func resolveCurrentWorkspace() -> String {
        let binaryPath = ProcessInfo.processInfo.arguments.first ?? ""
        let resolved = (binaryPath as NSString).resolvingSymlinksInPath
        if resolved.contains("/projects/shikki/.build/") {
            let components = resolved.components(separatedBy: "/projects/shikki/.build/")
            if let root = components.first, !root.isEmpty { return root }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let known = "\(home)/Documents/Workspaces/shiki"
        if FileManager.default.fileExists(atPath: "\(known)/docker-compose.yml") { return known }
        return FileManager.default.currentDirectoryPath
    }

    /// Detect all tmux sessions that look like shiki workspaces.
    /// Shiki sessions are named after the workspace folder.
    private func detectShikiSessions() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "list-sessions", "-F", "#{session_name}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let output = String(data: data, encoding: .utf8) ?? ""

        // Filter: sessions that have an orchestrator window (shiki-created sessions)
        return output.split(separator: "\n").compactMap { session in
            let name = String(session)
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            check.arguments = ["tmux", "list-windows", "-t", name, "-F", "#{window_name}"]
            let checkPipe = Pipe()
            check.standardOutput = checkPipe
            check.standardError = FileHandle.nullDevice
            try? check.run()
            // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
            let windowsData = checkPipe.fileHandleForReading.readDataToEndOfFile()
            check.waitUntilExit()
            guard check.terminationStatus == 0 else { return nil }
            let windows = String(data: windowsData, encoding: .utf8) ?? ""
            // A shiki session has an "orchestrator" window
            return windows.contains("orchestrator") ? name : nil
        }
    }
}
