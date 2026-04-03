import ArgumentParser
import Foundation
import ShikkiKit

/// Smart startup: detects environment, bootstraps Docker, seeds data, launches tmux, shows status.
struct StartupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Launch the Shiki system (smart startup with environment detection)"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Option(name: .long, help: "Workspace root path (auto-detected if omitted)")
    var workspace: String?

    @Option(name: .long, help: "Tmux session name (defaults to workspace folder name)")
    var session: String?

    @Flag(name: .long, help: "Skip tmux layout creation (just check and display)")
    var noTmux: Bool = false

    @Flag(name: .long, help: "Don't auto-attach to tmux after startup")
    var noAttach: Bool = false

    @Flag(name: .long, help: "Skip the splash screen")
    var noSplash: Bool = false

    @Flag(name: .long, help: "Replay the splash screen and exit")
    var splashmode: Bool = false

    func run() async throws {
        // --splashmode: replay splash and exit
        if splashmode {
            SplashRenderer.render(version: "1.0.0")
            return
        }

        let workspacePath = resolveWorkspace()
        let sessionName = session ?? URL(fileURLWithPath: workspacePath).lastPathComponent
        let env = EnvironmentDetector()
        let stats = SessionStats()

        // Splash screen (before environment checks)
        if !noSplash {
            // Try to get resume context from session checkpoint
            let checkpointManager = PausedSessionManager()
            let resumeContext: String?
            if let checkpoint = try? checkpointManager.resume() {
                resumeContext = "Resuming: \(checkpoint.branch) — \(checkpoint.summary ?? "no summary")"
            } else {
                resumeContext = nil
            }
            SplashRenderer.render(version: "1.0.0", resumeContext: resumeContext)
        }

        // Silently refresh zsh completions if stale
        refreshCompletionsIfNeeded()

        print("\u{1B}[1m\u{1B}[36mShiki\u{1B}[0m — Smart Startup [\(sessionName)]")
        print()

        // ── Step 1: Environment Detection ──
        print("\u{1B}[33m[1/6] Environment\u{1B}[0m")
        let dockerOk = await env.isDockerRunning()
        let colimaOk = await env.isColimaRunning()
        let backendOk = await env.isBackendHealthy(url: url)
        let lmStudioOk = await env.isLMStudioRunning(url: "http://127.0.0.1:1234")

        printCheck("Docker daemon", dockerOk)
        printCheck("Colima VM", colimaOk)
        printCheck("Backend (\(url))", backendOk)
        printCheck("LM Studio (127.0.0.1:1234)", lmStudioOk, required: false)
        print()

        // ── Step 2: Bootstrap Docker if needed ──
        if !backendOk {
            print("\u{1B}[33m[2/6] Docker bootstrap\u{1B}[0m")

            if !colimaOk {
                print("  Starting Colima...")
                try await startColima()
            }

            if !dockerOk || !backendOk {
                print("  Starting containers...")
                try await startContainers(workspace: workspacePath)
            }

            // Health check loop with dots
            print("  Waiting for backend", terminator: "")
            let healthy = await waitForBackend(url: url, maxAttempts: 30)
            if healthy {
                print(" \u{1B}[32m✓\u{1B}[0m")
            } else {
                print(" \u{1B}[31m✗\u{1B}[0m")
                print("\u{1B}[31m  Backend failed to start after 30s\u{1B}[0m")
                throw ExitCode(1)
            }
        } else {
            print("\u{1B}[33m[2/6] Docker bootstrap\u{1B}[0m")
            print("  \u{1B}[2mBackend already running\u{1B}[0m")
        }
        print()

        // ── Step 3: Data check ──
        print("\u{1B}[33m[3/6] Orchestrator data\u{1B}[0m")
        let companies = await env.companyCount(backendURL: url)
        if companies > 0 {
            print("  \u{1B}[2m\(companies) companies found\u{1B}[0m")
        } else {
            print("  No companies — seeding...")
            try await seedCompanies(workspace: workspacePath)
        }
        print()

        // ── Step 4: Binary check ──
        print("\u{1B}[33m[4/6] Binary\u{1B}[0m")
        // We're already running as the binary, so just confirm
        print("  \u{1B}[2mRunning from compiled binary\u{1B}[0m")
        print()

        // ── Step 5: Gather status (before tmux so we can inject into Claude prompt) ──
        print("\u{1B}[33m[5/6] Status\u{1B}[0m")
        print()

        let displayData = await gatherDisplayData(
            backendURL: url, workspacePath: workspacePath,
            stats: stats, env: env
        )

        // Record this session start
        try? stats.recordSessionEnd()

        // ── Step 6: Tmux layout + heartbeat ──
        print()
        print("\u{1B}[33m[6/6] Tmux session\u{1B}[0m")
        var tmuxCreated = false
        if noTmux {
            print("  \u{1B}[2mSkipped (--no-tmux)\u{1B}[0m")
        } else if await env.isTmuxSessionRunning(name: sessionName) {
            print("  \u{1B}[2mSession '\(sessionName)' already running\u{1B}[0m")
        } else {
            print("  Creating layout...")
            try await createTmuxLayout(
                workspace: workspacePath, session: sessionName,
                companies: displayData.companySlugs
            )

            print("  Starting orchestrator + heartbeat...")
            try await launchOrchestratorAndHeartbeat(
                data: displayData, workspace: workspacePath, session: sessionName
            )
            tmuxCreated = true
            print("  \u{1B}[32mReady\u{1B}[0m")
        }

        // Dashboard: only print to terminal if tmux failed or was skipped
        if !tmuxCreated {
            StartupRenderer.render(displayData)
        }

        if !noTmux {
            if !noAttach && !isInsideTmux() {
                print()
                print("\u{1B}[2mAttaching to '\(sessionName)'...\u{1B}[0m")
                let path = "/usr/bin/env"
                let args = ["env", "tmux", "attach-session", "-t", sessionName]
                let cArgs = args.map { strdup($0) } + [nil]
                execv(path, cArgs)
                // Only reached if execv fails
                StartupRenderer.render(displayData)
                print("\u{1B}[31mFailed to attach. Run: shiki attach\u{1B}[0m")
            } else if noAttach {
                print()
                print("\u{1B}[2mSession '\(sessionName)' ready. Use your session switcher or: shiki attach --session \(sessionName)\u{1B}[0m")
            }
        }
    }

    // MARK: - Helpers

    /// Resolve the workspace path using this priority:
    /// 1. Explicit --workspace flag
    /// 2. Auto-detect from binary symlink (binary lives in projects/shikki/.build/...)
    /// 3. Known default path ~/Documents/Workspaces/shiki
    /// 4. Current directory (first-time setup → suggest wizard)
    private func resolveWorkspace() -> String {
        // 1. Explicit flag
        if let workspace, !workspace.isEmpty {
            return workspace
        }

        // 2. Auto-detect from binary location
        //    Binary is at: {workspace}/projects/shikki/.build/debug/shikki
        //    So workspace = binary path /../../../../../
        let binaryPath = ProcessInfo.processInfo.arguments.first ?? ""
        let resolved = (binaryPath as NSString).resolvingSymlinksInPath
        if resolved.contains("/projects/shikki/.build/") {
            let components = resolved.components(separatedBy: "/projects/shikki/.build/")
            if let root = components.first, !root.isEmpty,
               FileManager.default.fileExists(atPath: "\(root)/docker-compose.yml") {
                return root
            }
        }

        // 3. Known default
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let knownPath = "\(home)/Documents/Workspaces/shiki"
        if FileManager.default.fileExists(atPath: "\(knownPath)/docker-compose.yml") {
            return knownPath
        }

        // 4. No workspace found — fail with guidance
        print("\u{1B}[31mNo Shiki workspace found.\u{1B}[0m")
        print("  Run \u{1B}[1mshiki wizard\u{1B}[0m to set up a new workspace,")
        print("  or use \u{1B}[1m--workspace ./\u{1B}[0m to use the current directory.")
        print()
        return FileManager.default.currentDirectoryPath
    }

    private func printCheck(_ label: String, _ ok: Bool, required: Bool = true) {
        let icon = ok ? "\u{1B}[32m✓\u{1B}[0m" : (required ? "\u{1B}[31m✗\u{1B}[0m" : "\u{1B}[2m-\u{1B}[0m")
        print("  \(icon) \(label)")
    }

    private func isInsideTmux() -> Bool {
        ProcessInfo.processInfo.environment["TMUX"] != nil
    }

    /// Regenerate zsh completions if the binary is newer than the completion file.
    private func refreshCompletionsIfNeeded() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let completionFile = "\(home)/.zsh/completions/_shiki"
        let binaryPath = (ProcessInfo.processInfo.arguments.first ?? "") as NSString
        let resolved = binaryPath.resolvingSymlinksInPath

        let fm = FileManager.default
        guard let binaryDate = (try? fm.attributesOfItem(atPath: resolved))?[.modificationDate] as? Date else { return }
        let completionDate = (try? fm.attributesOfItem(atPath: completionFile))?[.modificationDate] as? Date

        // Regenerate if completion file missing or older than binary
        if completionDate == nil || binaryDate > completionDate! {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolved)
            process.arguments = ["--generate-completion-script", "zsh"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return }
            try? fm.createDirectory(atPath: "\(home)/.zsh/completions", withIntermediateDirectories: true)
            fm.createFile(atPath: completionFile, contents: data)
        }
    }

    // MARK: - Bootstrap

    private func startColima() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["colima", "start"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ShikkiCommandError.processExitedWithCode(process.terminationStatus)
        }
    }

    private func startContainers(workspace: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "compose", "up", "-d"]
        process.currentDirectoryURL = URL(fileURLWithPath: workspace)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ShikkiCommandError.processExitedWithCode(process.terminationStatus)
        }
    }

    private func waitForBackend(url: String, maxAttempts: Int) async -> Bool {
        for _ in 0..<maxAttempts {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["curl", "-sf", "\(url)/health"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return true }
            print(".", terminator: "")
            fflush(stdout)
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    private func seedCompanies(workspace: String) async throws {
        let scriptPath = "\(workspace)/scripts/seed-companies.sh"
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("  \u{1B}[31mSeed script not found at \(scriptPath)\u{1B}[0m")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workspace)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Tmux

    /// Single-window layout: 95% orchestrator (left) + 5% sidebar (right).
    /// Sidebar: workspace shell (top) + heartbeat (bottom, ~3 lines).
    private func createTmuxLayout(
        workspace: String, session: String, companies: [String]
    ) async throws {

        func tmux(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }

        func tmuxCapture(_ args: String...) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        // 1. Single window
        try tmux("new-session", "-d", "-s", session, "-n", "orchestrator", "-c", workspace)

        // 2. Get the main pane (will become orchestrator — left 95%)
        let mainPaneId = try tmuxCapture(
            "display-message", "-t", "\(session):orchestrator", "-p", "#{pane_id}"
        )

        // 3. Split right sidebar (5%)
        try tmux("split-window", "-h", "-t", mainPaneId, "-l", "5%", "-c", workspace)
        let sidebarPaneId = try tmuxCapture(
            "display-message", "-t", "\(session):orchestrator", "-p", "#{pane_id}"
        )

        // 4. Split sidebar: workspace shell (top) + heartbeat (bottom, ~3 lines)
        try tmux("split-window", "-v", "-t", sidebarPaneId, "-l", "3", "-c", workspace)
        let heartbeatPaneId = try tmuxCapture(
            "display-message", "-t", "\(session):orchestrator", "-p", "#{pane_id}"
        )

        // 5. Enable pane border titles + prevent shell from overriding them
        try tmux("set-option", "-w", "-t", "\(session):orchestrator", "pane-border-status", "top")
        try tmux("set-option", "-w", "-t", "\(session):orchestrator", "pane-border-format",
                 " #{pane_title} ")
        try tmux("set-option", "-w", "-t", "\(session):orchestrator", "allow-rename", "off")

        // 6. Label all panes
        try tmux("select-pane", "-t", mainPaneId, "-T", "ORCHESTRATOR")
        try tmux("select-pane", "-t", sidebarPaneId, "-T", "WORKSPACE")
        try tmux("select-pane", "-t", heartbeatPaneId, "-T", "HEARTBEAT")

        // 7. Focus the orchestrator pane
        try tmux("select-pane", "-t", mainPaneId)

        // 8. Save pane mapping for the launcher (/tmp/shiki-panes-{session}.json)
        let mapping: [String: String] = [
            "orchestrator": mainPaneId,
            "workspace": sidebarPaneId,
            "heartbeat": heartbeatPaneId,
        ]
        let mappingFile = "/tmp/shiki-panes-\(session).json"
        let jsonData = try JSONSerialization.data(withJSONObject: mapping)
        FileManager.default.createFile(atPath: mappingFile, contents: jsonData)
    }

    /// Launch interactive Claude in the orchestrator pane + heartbeat in the tiny pane.
    /// Dashboard is included in the Claude prompt (not printed to terminal).
    private func launchOrchestratorAndHeartbeat(
        data: StartupDisplayData, workspace: String, session: String
    ) async throws {
        // 1. Render dashboard to temp file (for Claude to see on startup)
        let statusFile = "/tmp/shiki-startup-status-\(session).txt"
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        StartupRenderer.render(data)
        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        pipe.fileHandleForWriting.closeFile()
        let rendered = pipe.fileHandleForReading.readDataToEndOfFile()
        FileManager.default.createFile(atPath: statusFile, contents: rendered)

        let binaryPath = ProcessInfo.processInfo.arguments.first
            ?? "\(workspace)/projects/shikki/.build/debug/shikki"

        func tmux(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }

        // 2. Read pane mapping
        let mappingFile = "/tmp/shiki-panes-\(session).json"
        guard let mappingData = FileManager.default.contents(atPath: mappingFile),
              let mapping = try? JSONSerialization.jsonObject(with: mappingData) as? [String: String],
              let mainPaneId = mapping["orchestrator"],
              let heartbeatPaneId = mapping["heartbeat"]
        else {
            throw ShikkiCommandError.layoutFailed("Could not read pane mapping from \(mappingFile)")
        }

        // 3. Launch event logger in the event-log pane (above heartbeat)
        if let eventLogPaneId = mapping["event-log"] {
            let logCmd = "\(binaryPath) log; read"
            try tmux("send-keys", "-t", eventLogPaneId, logCmd, "C-m")
        }

        // 4. Launch heartbeat in the tiny bottom-right pane
        let heartbeatCmd = "\(binaryPath) heartbeat --workspace \(workspace) --session \(session); read"
        try tmux("send-keys", "-t", heartbeatPaneId, heartbeatCmd, "C-m")

        // 5. Build orchestrator prompt with dashboard data baked in
        let companySlugs = data.companySlugs.isEmpty
            ? ["maya", "wabisabi", "brainy", "flsh", "kintsugi", "obyw-one"]
            : data.companySlugs

        var decideStep = ""
        if data.pendingDecisions > 0 {
            decideStep = " && echo '' && echo $'\\e[33m⚠ \(data.pendingDecisions) T1 decisions blocking your companies — let\\'s unblock them first.\\e[0m' && echo '' && \(binaryPath) decide"
        }

        let orchestratorPrompt = """
        You are the Shikki main orchestrator — the conductor of a multi-agent system.

        STARTUP DASHBOARD:
        - Version: \(data.version) | Health: \(data.isHealthy ? "OK" : "DEGRADED")
        - Pending T1 decisions: \(data.pendingDecisions)
        - Stale companies: \(data.staleCompanies)
        - Spent today: $\(String(format: "%.2f", data.spentToday))
        - Weekly delta: +\(data.weeklyInsertions) / -\(data.weeklyDeletions) lines across \(data.weeklyProjectCount) projects

        LAYOUT: You are in the left 95% pane (main). The right 5% sidebar has a workspace shell on top + a heartbeat pane at the bottom.
        COMPANIES: \(companySlugs.joined(separator: ", "))
        BACKEND: http://localhost:3900

        The heartbeat monitors company health and dispatches tasks from the queue.

        YOUR ROLE:
        - Use /board to see all running company sessions
        - Use /decide to handle pending T1 decisions that block companies
        - Use /dispatch to launch parallel feature work
        - Use shiki status for overview
        - Work directly on the highest priority task when companies are busy

        Start by reviewing what's pending and act.
        """
        let promptFile = "/tmp/shiki-orchestrator-prompt-\(session).txt"
        FileManager.default.createFile(atPath: promptFile, contents: Data(orchestratorPrompt.utf8))

        // 6. In main pane: show dashboard → decide if needed → launch interactive Claude
        let cmd = "clear && cat \(statusFile)\(decideStep) && echo '' && claude \"$(cat \(promptFile))\""
        try tmux("send-keys", "-t", mainPaneId, cmd, "C-m")
    }

    // MARK: - Gather display data

    private func gatherDisplayData(
        backendURL: String, workspacePath: String,
        stats: SessionStats, env: EnvironmentDetector
    ) async -> StartupDisplayData {
        // Fetch board data from backend
        let client = BackendClient(baseURL: backendURL)
        defer { Task { try? await client.shutdown() } }

        var lastSessionTasks: [(company: String, completed: Int)] = []
        var upcomingTasks: [(company: String, pending: Int)] = []
        var pendingDecisions = 0
        var staleCompanies = 0
        var spentToday: Double = 0
        var companySlugs: [String] = []

        // Fetch companies for task counts
        if let companies = try? await client.getCompanies() {
            companySlugs = companies.sorted { $0.priority < $1.priority }.map(\.slug)
            for c in companies {
                let completed = c.completedTasks ?? 0
                let pending = c.pendingTasks ?? 0
                if completed > 0 {
                    lastSessionTasks.append((company: c.slug, completed: completed))
                }
                if pending > 0 {
                    upcomingTasks.append((company: c.slug, pending: pending))
                }
                spentToday += c.budget.spentTodayUsd
                if c.heartbeatStatus == "stale" || c.heartbeatStatus == "dead" {
                    staleCompanies += 1
                }
            }
        }

        // Fetch pending decisions
        if let decisions = try? await client.getPendingDecisions() {
            pendingDecisions = decisions.filter { $0.tier == 1 }.count
        }

        // Git stats — paths relative to workspace root
        let projects = ["projects/maya", "projects/wabisabi", "projects/brainy", "projects/flsh", "projects/kintsugi-ds"]
        let sessionSummary = await stats.computeStats(
            workspace: workspacePath,
            projects: projects
        )

        let weeklyInsertions = sessionSummary.weeklyAggregate.reduce(0) { $0 + $1.insertions }
        let weeklyDeletions = sessionSummary.weeklyAggregate.reduce(0) { $0 + $1.deletions }
        let weeklyProjects = sessionSummary.weeklyAggregate.filter { $0.commits > 0 }.count

        return StartupDisplayData(
            version: "0.2.0",
            isHealthy: true,
            lastSessionTasks: lastSessionTasks,
            upcomingTasks: upcomingTasks,
            sessionStats: sessionSummary.sinceSession,
            weeklyInsertions: weeklyInsertions,
            weeklyDeletions: weeklyDeletions,
            weeklyProjectCount: weeklyProjects,
            pendingDecisions: pendingDecisions,
            staleCompanies: staleCompanies,
            spentToday: spentToday,
            companySlugs: companySlugs
        )
    }
}
