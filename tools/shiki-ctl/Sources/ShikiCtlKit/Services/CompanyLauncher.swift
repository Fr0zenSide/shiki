import Foundation
import Logging

/// Tmux-based task session launcher.
///
/// Creates one tmux window per dispatched task with a dynamically generated name
/// (`"{company}:{task-short}"`). Pane border titles show the full company + task name.
/// After each launch or stop, the board is re-tiled so the layout adapts automatically.
///
/// The autopilot prompt embedded in each window instructs Claude to:
/// 1. Claim the assigned task via the orchestrator API
/// 2. Work in TDD mode with `/pre-pr` before PRs
/// 3. Send heartbeats every 60s with context pressure data
public struct TmuxProcessLauncher: ProcessLauncher, Sendable {
    let session: String
    let workspacePath: String
    let logger: Logger

    public init(
        session: String = "shiki-board",
        workspacePath: String,
        logger: Logger = Logger(label: "shiki-ctl.launcher")
    ) {
        self.session = session
        self.workspacePath = workspacePath
        self.logger = logger
    }

    public func launchTaskSession(
        taskId: String, companyId: String, companySlug: String,
        title: String, projectPath: String
    ) async throws {
        let windowName = Self.windowName(companySlug: companySlug, title: title)

        guard !(await isSessionRunning(slug: windowName)) else {
            logger.debug("Session already running: \(windowName)")
            return
        }

        let projectDir = "\(workspacePath)/projects/\(projectPath)"

        // Ensure tmux session exists
        if !tmuxSessionExists() {
            try runProcess("tmux", arguments: ["new-session", "-d", "-s", session, "-c", workspacePath])
        }

        // Build the autopilot prompt for this task session
        let prompt = Self.buildAutopilotPrompt(
            companyId: companyId, companySlug: companySlug,
            taskId: taskId, title: title
        )

        // Create new window running Claude with the autopilot prompt
        let shellCommand = "claude \(Self.shellEscape(prompt))"
        try runProcess("tmux", arguments: [
            "new-window", "-t", session, "-n", windowName, "-c", projectDir,
            "bash", "-c", shellCommand,
        ])

        // Set pane border title
        let borderTitle = "\(companySlug.uppercased()): \(title)"
        if let paneId = paneIdForWindow(windowName) {
            try? runProcess("tmux", arguments: [
                "select-pane", "-t", paneId, "-T", borderTitle,
            ])
        }

        // Re-tile the board tab so panes adapt to the new window count
        retileBoard()

        logger.info("Launched task session: \(windowName) in \(projectDir)")
    }

    /// Check if a tmux window with the exact name `slug` exists in the board session.
    public func isSessionRunning(slug: String) async -> Bool {
        do {
            let output = try runProcessCapture("tmux", arguments: [
                "list-windows", "-t", session, "-F", "#{window_name}",
            ])
            return output.split(separator: "\n").contains(where: { String($0) == slug })
        } catch {
            return false
        }
    }

    /// Kill the tmux window for the given session slug and re-tile remaining panes.
    /// Captures the pane scrollback buffer before killing (for session transcripts).
    public func stopSession(slug: String) async throws {
        try runProcess("tmux", arguments: [
            "kill-window", "-t", "\(session):\(slug)",
        ])
        retileBoard()
        logger.info("Stopped session: \(slug)")
    }

    /// Capture the full scrollback buffer of a session's pane before killing it.
    /// Returns the raw terminal output (with ANSI codes stripped).
    public func captureSessionOutput(slug: String) -> String? {
        guard let output = try? runProcessCapture("tmux", arguments: [
            "capture-pane", "-t", "\(session):\(slug)", "-p", "-S", "-",
        ]) else { return nil }
        // Strip ANSI escape codes for cleaner storage
        return output.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "",
            options: .regularExpression
        )
    }

    /// List all active task session window names (excludes `orchestrator` and `research` tabs).
    public func listRunningSessions() async -> [String] {
        do {
            let output = try runProcessCapture("tmux", arguments: [
                "list-windows", "-t", session, "-F", "#{window_name}",
            ])
            return output.split(separator: "\n")
                .map(String.init)
                .filter { $0 != "orchestrator" && $0 != "research" }
        } catch {
            return []
        }
    }

    // MARK: - Window Naming

    /// Generates a tmux window name: "{company}:{task-short}" (max ~25 chars)
    static func windowName(companySlug: String, title: String) -> String {
        let short = String(title.prefix(15))
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        return "\(companySlug):\(short)"
    }

    // MARK: - Autopilot Prompt

    private static func buildAutopilotPrompt(
        companyId: String, companySlug: String,
        taskId: String, title: String
    ) -> String {
        let claimInstruction: String
        if taskId.isEmpty {
            claimInstruction = """
            1. Claim your next task: POST /api/task-queue/claim with {"companyId":"\(companyId)","sessionId":"<generate-a-uuid>"}
            """
        } else {
            claimInstruction = """
            1. Your assigned task: "\(title)" (ID: \(taskId))
               Claim it: POST /api/task-queue/claim with {"companyId":"\(companyId)","sessionId":"<generate-a-uuid>","taskId":"\(taskId)"}
            """
        }

        return """
        You are an autonomous agent for the "\(companySlug)" company in the Shiki orchestrator.

        ORCHESTRATOR API: http://localhost:3900

        YOUR WORKFLOW:
        \(claimInstruction)
        2. Work on the claimed task in this project directory
        3. If you need a human decision, create one: POST /api/decision-queue with {"companyId":"\(companyId)","taskId":"<task-id>","tier":1,"question":"<your question>"}
        4. When done, update the task: PATCH /api/task-queue/<task-id> with {"status":"completed","result":{"summary":"what you did"}}
        5. Claim the next task and repeat

        HEARTBEAT (every 60s):
        POST /api/orchestrator/heartbeat with:
        {"companyId":"\(companyId)","sessionId":"<your-session-id>","data":{
          "contextPct": <your current context usage %>,
          "compactionCount": <times you have been compacted this session>,
          "taskInProgress": "<current task title>"
        }}

        RULES:
        - Follow TDD: write failing test first, then implement
        - Run the full test suite after every change
        - Use /pre-pr before any PR
        - Send heartbeats every 60s with context data
        - If you hit a blocker that needs human input, create a T1 decision and move to the next task
        - Never push to main directly — use feature branches and PRs to develop

        START NOW: claim your first task and begin working.
        """
    }

    private static func shellEscape(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "$'\(escaped)'"
    }

    // MARK: - Helpers

    private func tmuxSessionExists() -> Bool {
        do {
            try runProcess("tmux", arguments: ["has-session", "-t", session])
            return true
        } catch {
            return false
        }
    }

    private func paneIdForWindow(_ windowName: String) -> String? {
        guard let output = try? runProcessCapture("tmux", arguments: [
            "list-panes", "-t", "\(session):\(windowName)", "-F", "#{pane_id}",
        ]) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init)
    }

    private func retileBoard() {
        // Re-tile all windows in the board tab so the layout adapts dynamically
        try? runProcess("tmux", arguments: ["select-layout", "-t", session, "tiled"])
    }

    private func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LauncherError.processExitedWithCode(process.terminationStatus)
        }
    }

    private func runProcessCapture(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum LauncherError: Error {
    case processExitedWithCode(Int32)
}
