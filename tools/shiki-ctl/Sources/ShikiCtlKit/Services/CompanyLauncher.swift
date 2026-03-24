import Foundation
import Logging

/// Pane-based task session launcher.
///
/// Company panes are pre-created in the tmux sidebar during startup.
/// This launcher finds the right pane by title and sends `claude 'prompt'`
/// via `send-keys`. No new windows are ever created.
///
/// Pane mapping is read from `/tmp/shiki-panes-{session}.json`.
public struct TmuxProcessLauncher: ProcessLauncher, Sendable {
    let session: String
    let workspacePath: String
    let logger: Logger
    let templateLoader: PromptTemplateLoader

    public init(
        session: String = "shiki",
        workspacePath: String,
        logger: Logger = Logger(label: "shiki-ctl.launcher")
    ) {
        self.session = session
        self.workspacePath = workspacePath
        self.logger = logger
        self.templateLoader = PromptTemplateLoader(workspacePath: workspacePath, logger: logger)
    }

    public func launchTaskSession(
        taskId: String, companyId: String, companySlug: String,
        title: String, projectPath: String
    ) async throws {
        // Check if the company pane already has Claude running
        guard !(await isCompanyPaneActive(slug: companySlug)) else {
            logger.debug("Company pane already active: \(companySlug)")
            return
        }

        guard let paneId = findCompanyPane(slug: companySlug) else {
            logger.warning("No pane found for company: \(companySlug)")
            return
        }

        let projectDir = "\(workspacePath)/projects/\(projectPath)"

        // Build the autopilot prompt for this task session
        let prompt = Self.buildAutopilotPrompt(
            companyId: companyId, companySlug: companySlug,
            taskId: taskId, title: title,
            templateLoader: templateLoader
        )

        // cd into project dir, then launch Claude with the prompt
        let cdCmd = "cd \(Self.shellEscapePath(projectDir))"
        let claudeCmd = "claude \(Self.shellEscape(prompt))"
        try runProcess("tmux", arguments: [
            "send-keys", "-t", paneId, "\(cdCmd) && \(claudeCmd)", "C-m",
        ])

        logger.info("Launched task session: \(companySlug) in \(projectDir)")
    }

    /// Check if a company's pane has an active Claude process (not idle shell).
    public func isSessionRunning(slug: String) async -> Bool {
        // Extract company slug from "company:task-short" format
        let companySlug = slug.split(separator: ":", maxSplits: 1).first.map(String.init) ?? slug
        return await isCompanyPaneActive(slug: companySlug)
    }

    /// Send Ctrl-C to the company pane to stop the running Claude session.
    public func stopSession(slug: String) async throws {
        let companySlug = slug.split(separator: ":", maxSplits: 1).first.map(String.init) ?? slug
        guard let paneId = findCompanyPane(slug: companySlug) else {
            logger.warning("No pane found for company: \(companySlug)")
            return
        }

        // Send Ctrl-C to interrupt Claude
        try runProcess("tmux", arguments: ["send-keys", "-t", paneId, "C-c", ""])
        // Brief wait for process to exit
        usleep(500_000)
        // Send another Ctrl-C in case Claude is in a prompt
        try? runProcess("tmux", arguments: ["send-keys", "-t", paneId, "C-c", ""])

        logger.info("Stopped session in pane: \(companySlug)")
    }

    /// Capture the full scrollback buffer of a company's pane.
    public func captureSessionOutput(slug: String) -> String? {
        let companySlug = slug.split(separator: ":", maxSplits: 1).first.map(String.init) ?? slug
        guard let paneId = findCompanyPane(slug: companySlug) else { return nil }
        guard let output = try? runProcessCapture("tmux", arguments: [
            "capture-pane", "-t", paneId, "-p", "-S", "-",
        ]) else { return nil }
        // Strip ANSI escape codes for cleaner storage
        return output.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "",
            options: .regularExpression
        )
    }

    /// Reserved window names that are NOT task sessions — never clean them up.
    /// With single-window layout, only "orchestrator" exists.
    private static var reservedWindows: Set<String> { ProcessCleanup.reservedWindows }

    /// List active company sessions by checking which panes have Claude running.
    /// Returns slugs in "company:active" format for compatibility with HeartbeatLoop.
    public func listRunningSessions() async -> [String] {
        // List all panes with their title and current command
        guard let output = try? runProcessCapture("tmux", arguments: [
            "list-panes", "-t", "\(session):orchestrator",
            "-F", "#{pane_title} #{pane_current_command}",
        ]) else { return [] }

        let reservedTitles: Set<String> = ["ORCHESTRATOR", "HEARTBEAT"]

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let title = String(parts[0])
            let command = String(parts[1])

            // Skip non-company panes
            guard !reservedTitles.contains(title) else { return nil }

            // Active = running claude (not idle shell)
            let isActive = command != "zsh" && command != "bash" && !command.isEmpty
            guard isActive else { return nil }

            return "\(title.lowercased()):active"
        }
    }

    // MARK: - Window Naming (kept for compatibility)

    /// Generates a session slug: "{company}:{task-short}" (max ~25 chars)
    static func windowName(companySlug: String, title: String) -> String {
        let short = String(title.prefix(15))
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        return "\(companySlug):\(short)"
    }

    // MARK: - Pane Discovery

    /// Find a company pane by slug.
    /// Primary: reads the pane mapping JSON saved during layout creation.
    /// Fallback: scans pane titles (unreliable — zsh precmd can override them).
    private func findCompanyPane(slug: String) -> String? {
        // Primary: JSON mapping file (stable across shell title overrides)
        let mappingFile = "/tmp/shiki-panes-\(session).json"
        if let data = FileManager.default.contents(atPath: mappingFile),
           let mapping = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let paneId = mapping[slug] {
            // Verify the pane still exists
            if let check = try? runProcessCapture("tmux", arguments: [
                "display-message", "-t", paneId, "-p", "#{pane_id}",
            ]), !check.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return paneId
            }
        }

        // Fallback: scan pane titles
        let titleToFind = slug.uppercased()
        guard let output = try? runProcessCapture("tmux", arguments: [
            "list-panes", "-t", "\(session):orchestrator",
            "-F", "#{pane_id} #{pane_title}",
        ]) else { return nil }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if String(parts[1]) == titleToFind {
                return String(parts[0])
            }
        }
        return nil
    }

    /// Check if a company pane has an active process (not idle shell).
    private func isCompanyPaneActive(slug: String) async -> Bool {
        guard let paneId = findCompanyPane(slug: slug) else { return false }
        guard let output = try? runProcessCapture("tmux", arguments: [
            "display-message", "-t", paneId, "-p", "#{pane_current_command}",
        ]) else { return false }

        let command = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return command != "zsh" && command != "bash" && !command.isEmpty
    }

    // MARK: - Autopilot Prompt

    /// Build the autopilot prompt using the template loader fallback chain.
    /// Computes the `claimInstruction` block (conditional on taskId presence),
    /// then renders the template with all variables.
    static func buildAutopilotPrompt(
        companyId: String, companySlug: String,
        taskId: String, title: String,
        apiBaseURL: String = "http://localhost:3900",
        templateLoader: PromptTemplateLoader
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

        let (template, source) = templateLoader.loadTemplate()
        let variables: [String: String] = [
            "companyId": companyId,
            "companySlug": companySlug,
            "taskId": taskId,
            "taskTitle": title,
            "claimInstruction": claimInstruction,
            "apiBaseURL": apiBaseURL,
        ]

        let logger = Logger(label: "shiki-ctl.launcher")
        logger.debug("Using prompt template from: \(source)")

        return templateLoader.render(template: template, variables: variables)
    }

    private static func shellEscape(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "$'\(escaped)'"
    }

    private static func shellEscapePath(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\ ")
    }

    // MARK: - Helpers

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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum LauncherError: Error {
    case processExitedWithCode(Int32)
}
