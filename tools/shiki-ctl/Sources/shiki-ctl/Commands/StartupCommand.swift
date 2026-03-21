import ArgumentParser
import Foundation
import ShikiCtlKit

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

        // ── Step 5: Gather status (before tmux so we can write it into the pane) ──
        print("\u{1B}[33m[5/6] Status\u{1B}[0m")
        print()

        let displayData = await gatherDisplayData(
            backendURL: url, workspacePath: workspacePath,
            stats: stats, env: env
        )
        StartupRenderer.render(displayData)

        // Record this session start
        try? stats.recordSessionEnd()

        // ── Step 6: Tmux layout + heartbeat ──
        print()
        print("\u{1B}[33m[6/6] Tmux session\u{1B}[0m")
        if noTmux {
            print("  \u{1B}[2mSkipped (--no-tmux)\u{1B}[0m")
        } else if await env.isTmuxSessionRunning(name: sessionName) {
            print("  \u{1B}[2mSession '\(sessionName)' already running\u{1B}[0m")
        } else {
            print("  Creating board layout...")
            try await createTmuxLayout(workspace: workspacePath, session: sessionName)

            // Write status into orchestrator pane, then launch heartbeat in same command
            print("  Starting heartbeat...")
            try await launchHeartbeatWithStatus(
                data: displayData, workspace: workspacePath, session: sessionName
            )
            print("  \u{1B}[32mBoard ready\u{1B}[0m")
        }

        if !noTmux {
            if !noAttach && !isInsideTmux() {
                print()
                print("\u{1B}[2mAttaching to '\(sessionName)'...\u{1B}[0m")
                let path = "/usr/bin/env"
                let args = ["env", "tmux", "attach-session", "-t", sessionName]
                let cArgs = args.map { strdup($0) } + [nil]
                execv(path, cArgs)
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
    /// 2. Auto-detect from binary symlink (binary lives in tools/shiki-ctl/.build/...)
    /// 3. Known default path ~/Documents/Workspaces/shiki
    /// 4. Current directory (first-time setup → suggest wizard)
    private func resolveWorkspace() -> String {
        // 1. Explicit flag
        if let workspace, !workspace.isEmpty {
            return workspace
        }

        // 2. Auto-detect from binary location
        //    Binary is at: {workspace}/tools/shiki-ctl/.build/debug/shiki-ctl
        //    So workspace = binary path /../../../../../
        let binaryPath = ProcessInfo.processInfo.arguments.first ?? ""
        let resolved = (binaryPath as NSString).resolvingSymlinksInPath
        if resolved.contains("/tools/shiki-ctl/.build/") {
            let components = resolved.components(separatedBy: "/tools/shiki-ctl/.build/")
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
            throw ShikiCommandError.processExitedWithCode(process.terminationStatus)
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
            throw ShikiCommandError.processExitedWithCode(process.terminationStatus)
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

    private func createTmuxLayout(workspace: String, session: String) async throws {
        let scriptPath = "\(workspace)/scripts/orchestrate-layout.sh"
        // If the layout script exists, use it; otherwise create manually
        if FileManager.default.fileExists(atPath: scriptPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            process.currentDirectoryURL = URL(fileURLWithPath: workspace)
            try process.run()
            process.waitUntilExit()
            return
        }

        // Manual layout creation (same as orchestrate.sh)
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
            // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }

        // Tab 1: orchestrator
        try tmux("new-session", "-d", "-s", session, "-n", "orchestrator", "-c", workspace)

        // Tab 2: board (empty, filled dynamically by heartbeat)
        try tmux("new-window", "-t", session, "-n", "board", "-c", workspace)
        // Enable pane border titles on board tab
        try tmux("set-option", "-w", "-t", "\(session):board", "pane-border-status", "top")
        try tmux("set-option", "-w", "-t", "\(session):board", "pane-border-format", " #{pane_title} ")
        // Set initial title on the board pane
        let boardPanes = try tmuxCapture("list-panes", "-t", "\(session):board", "-F", "#{pane_id}")
        if let firstBoardPane = boardPanes.split(separator: "\n").first {
            try tmux("select-pane", "-t", String(firstBoardPane), "-T", "DISPATCHER (waiting for tasks...)")
        }

        // Tab 3: research (4 panes)
        let researchDir = "\(workspace)/projects/research"
        let researchPath = FileManager.default.fileExists(atPath: researchDir) ? researchDir : workspace
        try tmux("new-window", "-t", session, "-n", "research", "-c", researchPath)
        try tmux("split-window", "-v", "-t", "\(session):research", "-c", researchPath)
        try tmux("split-window", "-v", "-t", "\(session):research", "-c", researchPath)
        try tmux("split-window", "-v", "-t", "\(session):research", "-c", researchPath)
        try tmux("select-layout", "-t", "\(session):research", "tiled")

        // Set pane border titles on research tab
        try tmux("set-option", "-w", "-t", "\(session):research", "pane-border-status", "top")
        try tmux("set-option", "-w", "-t", "\(session):research", "pane-border-format", " #{pane_title} ")
        let researchPanes = try tmuxCapture("list-panes", "-t", "\(session):research", "-F", "#{pane_id}")
        let paneIds = researchPanes.split(separator: "\n").map(String.init)
        let paneLabels = ["INGEST", "RADAR", "EXPLORE", "SCRATCH"]
        for (pane, label) in zip(paneIds, paneLabels) {
            try tmux("select-pane", "-t", pane, "-T", label)
        }

        // Select orchestrator tab
        try tmux("select-window", "-t", "\(session):orchestrator")
    }

    /// Split orchestrator pane: top = Claude (main), bottom = heartbeat (small).
    /// Show dashboard + decide in the main pane before launching Claude.
    private func launchHeartbeatWithStatus(
        data: StartupDisplayData, workspace: String, session: String
    ) async throws {
        // 1. Write rendered status to temp file
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

        let binaryPath = ProcessInfo.processInfo.arguments.first ?? "\(workspace)/tools/shiki-ctl/.build/debug/shiki-ctl"

        // 2. Split orchestrator pane: bottom 20% = heartbeat
        func tmux(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }

        // Get the main pane ID BEFORE splitting (this will be the Claude pane)
        func tmuxCapture2(_ args: String...) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            let capPipe = Pipe()
            process.standardOutput = capPipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
            let capData = capPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: capData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let mainPaneId = try tmuxCapture2("display-message", "-t", "\(session):orchestrator", "-p", "#{pane_id}")

        // Create a small bottom pane for the heartbeat (80/20 split)
        try tmux("split-window", "-v", "-t", mainPaneId, "-l", "20%",
                 "-c", workspace, "bash", "-c",
                 "\(binaryPath) heartbeat --workspace \(workspace) --session \(session); read")

        // The new pane (heartbeat) is now selected — get its ID
        let heartbeatPaneId = try tmuxCapture2("display-message", "-t", "\(session):orchestrator", "-p", "#{pane_id}")

        // Enable pane border titles
        try tmux("set-option", "-w", "-t", "\(session):orchestrator", "pane-border-status", "top")
        try tmux("set-option", "-w", "-t", "\(session):orchestrator", "pane-border-format", " #{pane_title} ")

        // Label panes by explicit ID
        try tmux("select-pane", "-t", mainPaneId, "-T", "ORCHESTRATOR")
        try tmux("select-pane", "-t", heartbeatPaneId, "-T", "HEARTBEAT")

        // Select the main pane (Claude)
        try tmux("select-pane", "-t", mainPaneId)

        // 3. In the main pane: show dashboard → decide if needed → then Claude
        var decideStep = ""
        if data.pendingDecisions > 0 {
            decideStep = " && echo '' && echo '\\e[33m⚠ \(data.pendingDecisions) T1 decisions blocking your companies — let\\'s unblock them first.\\e[0m' && echo '' && \(binaryPath) decide"
        }
        let cmd = "clear && cat \(statusFile)\(decideStep) && echo '' && claude"
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

        // Fetch companies for task counts
        if let companies = try? await client.getCompanies() {
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
            spentToday: spentToday
        )
    }
}
