import ArgumentParser
import Foundation
import ShikiCtlKit

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage Shiki sessions — pause, resume, list",
        subcommands: [
            SessionPauseCommand.self,
            SessionResumeCommand.self,
            SessionListCommand.self,
        ]
    )
}

// MARK: - Pause

struct SessionPauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause current session — save state for later resume"
    )

    @Option(name: .long, help: "Summary of current work")
    var summary: String?

    @Option(name: .long, help: "Next action to resume with")
    var next: String?

    func run() async throws {
        let manager = PausedSessionManager()

        // Detect current state from git + environment
        let branch = detectBranch()
        let pendingPRs = detectPendingPRs()
        let workspaceRoot = findWorkspaceRoot()

        let checkpoint = PausedSession(
            branch: branch,
            summary: summary,
            pendingPRs: pendingPRs,
            nextAction: next,
            workspaceRoot: workspaceRoot
        )

        try manager.pause(checkpoint: checkpoint)
        try manager.cleanup(keep: 10)

        // Also save to ShikiDB if available
        saveToDB(checkpoint: checkpoint)

        // Output
        print("\u{1B}[32m●\u{1B}[0m Session paused: \(checkpoint.sessionId)")
        print("  Branch: \(branch)")
        if let summary { print("  Summary: \(summary)") }
        if !pendingPRs.isEmpty { print("  Pending PRs: \(pendingPRs.map { "#\($0)" }.joined(separator: ", "))") }
        if let next { print("  Next: \(next)") }
        print()
        print("  Resume: \u{1B}[2mshiki session resume\u{1B}[0m")
        print("  File: ~/.shiki/sessions/\(checkpoint.sessionId).json")
    }

    private func detectBranch() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    private func detectPendingPRs() -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "pr", "list", "--json", "number", "--jq", ".[].number"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { Int($0) }
    }

    private func findWorkspaceRoot() -> String {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            if FileManager.default.fileExists(atPath: "\(dir)/.git") {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return FileManager.default.currentDirectoryPath
    }

    private func saveToDB(checkpoint: PausedSession) {
        // Build JSON safely via JSONSerialization (no string interpolation injection)
        let data: [String: Any] = [
            "type": "agent_event",
            "scope": "shiki",
            "data": [
                "eventType": "session_paused",
                "sessionId": checkpoint.sessionId,
                "summary": checkpoint.summary ?? "",
                "branch": checkpoint.branch,
                "nextAction": checkpoint.nextAction ?? "",
            ] as [String: Any],
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-s", "--max-time", "5",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", jsonString,
            "http://localhost:3900/api/data-sync",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Best-effort, don't wait
    }
}

// MARK: - Resume

struct SessionResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a paused session — launch tmux and inject context"
    )

    @Argument(help: "Session ID to resume (default: most recent)")
    var sessionId: String?

    @Flag(name: .long, help: "Output raw JSON instead of formatted context")
    var json: Bool = false

    @Flag(name: .long, help: "Only output context, don't launch tmux")
    var contextOnly: Bool = false

    func run() async throws {
        let manager = PausedSessionManager()

        guard let checkpoint = try manager.resume(sessionId: sessionId) else {
            if sessionId != nil {
                FileHandle.standardError.write(Data("\u{1B}[31mError:\u{1B}[0m Session '\(sessionId!)' not found\n".utf8))
            } else {
                FileHandle.standardError.write(Data("\u{1B}[31mError:\u{1B}[0m No paused sessions found\n".utf8))
                FileHandle.standardError.write(Data("  Pause first: \u{1B}[2mshiki session pause --summary \"what I was doing\"\u{1B}[0m\n".utf8))
            }
            throw ExitCode.failure
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(checkpoint)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Build resume context for Claude injection
        let context = manager.buildResumeContext(checkpoint: checkpoint)

        if contextOnly {
            print(context)
            return
        }

        // Copy context to clipboard for pasting into Claude
        copyToClipboard(context)
        FileHandle.standardError.write(Data("\u{1B}[32m●\u{1B}[0m Context copied to clipboard — paste into Claude to resume\n".utf8))

        // Show context summary on stderr (not stdout — don't pollute the terminal)
        FileHandle.standardError.write(Data("\n\(context)\n".utf8))

        // Launch or attach tmux session
        let tmuxSessionName = "shiki"
        let tmuxExists = tmuxSessionExists(tmuxSessionName)

        if tmuxExists {
            FileHandle.standardError.write(Data("\u{1B}[32m●\u{1B}[0m Attaching to existing tmux session '\(tmuxSessionName)'\n".utf8))
            launchTmuxAttach(sessionName: tmuxSessionName)
        } else {
            FileHandle.standardError.write(Data("\u{1B}[32m●\u{1B}[0m Launching tmux session '\(tmuxSessionName)' in \(checkpoint.workspaceRoot)\n".utf8))
            launchTmuxNew(sessionName: tmuxSessionName, workDir: checkpoint.workspaceRoot)
        }
    }

    private func tmuxSessionExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "has-session", "-t", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func launchTmuxAttach(sessionName: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "attach-session", "-t", sessionName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Don't wait — let tmux attach run in the background
    }

    private func copyToClipboard(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe
        try? process.run()
        pipe.fileHandleForWriting.write(Data(text.utf8))
        pipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    private func launchTmuxNew(sessionName: String, workDir: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "new-session", "-d", "-s", sessionName, "-c", workDir]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        // Now attach
        launchTmuxAttach(sessionName: sessionName)
    }
}

// MARK: - List

struct SessionListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all paused sessions"
    )

    func run() async throws {
        let manager = PausedSessionManager()
        let sessions = try manager.listCheckpoints()

        if sessions.isEmpty {
            print("No paused sessions.")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        print("\u{1B}[1mPaused Sessions\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 60))

        for (i, session) in sessions.enumerated() {
            let age = Date().timeIntervalSince(session.pausedAt)
            let ageStr: String
            if age < 3600 { ageStr = "\(Int(age / 60))m ago" }
            else if age < 86400 { ageStr = "\(Int(age / 3600))h ago" }
            else { ageStr = "\(Int(age / 86400))d ago" }

            let marker = i == 0 ? "\u{1B}[32m●\u{1B}[0m" : "\u{1B}[2m○\u{1B}[0m"
            print("  \(marker) \(session.sessionId) (\(ageStr))")
            print("    Branch: \(session.branch)")
            if let summary = session.summary {
                let short = summary.count > 60 ? String(summary.prefix(60)) + "..." : summary
                print("    Summary: \(short)")
            }
            if let next = session.nextAction {
                print("    Next: \(next)")
            }
            print()
        }

        print("Resume: \u{1B}[2mshiki session resume\u{1B}[0m (latest)")
        print("Resume: \u{1B}[2mshiki session resume <id>\u{1B}[0m (specific)")
    }
}
