import ArgumentParser
import Foundation
import ShikiCtlKit

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the Shiki system (with confirmation)"
    )

    @Option(name: .long, help: "Tmux session name (defaults to workspace folder name)")
    var session: String = "shiki"

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    func run() async throws {
        guard tmuxSessionExists(session) else {
            print("\u{1B}[2mNo tmux session running.\u{1B}[0m")
            return
        }

        let taskWindows = countTaskWindows(session)

        print("\u{1B}[33mStopping Shiki system...\u{1B}[0m")
        if taskWindows > 0 {
            print("  \u{1B}[31m\(taskWindows) active task window(s) running\u{1B}[0m")
        }

        if !force {
            print("  Confirm kill tmux session? [y/N] ", terminator: "")
            guard let confirm = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  confirm.lowercased() == "y" else {
                print("  Aborted.")
                return
            }
        }

        // Step 0: Journal final state for all sessions (crash recovery)
        let journal = SessionJournal()
        let discoverer = TmuxDiscoverer(sessionName: session)
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        await registry.refresh()
        for sess in await registry.allSessions {
            let checkpoint = SessionCheckpoint(
                sessionId: sess.windowName,
                state: sess.state,
                reason: .userAction,
                metadata: ["action": "shutdown"]
            )
            try? await journal.checkpoint(checkpoint)
        }
        let journaled = await registry.allSessions.count
        if journaled > 0 {
            print("  Journaled \(journaled) session(s)")
        }

        // Step 1: Clean up task windows and child processes BEFORE killing the session
        let cleanup = ProcessCleanup()
        let result = cleanup.cleanupSession(session: session)
        if result.windowsKilled > 0 {
            print("  Killed \(result.windowsKilled) task window(s)")
        }
        if result.orphanPIDsKilled > 0 {
            print("  Killed \(result.orphanPIDsKilled) orphaned process(es)")
        }

        // Step 2: Kill the tmux session last (reserved windows die here)
        try shellExec("tmux", arguments: ["kill-session", "-t", session])
        print("  \u{1B}[32mStopped Shiki system\u{1B}[0m")
        print("\u{1B}[2mContainers left running (use 'docker compose down' to stop)\u{1B}[0m")
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

    private func countTaskWindows(_ session: String) -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "list-windows", "-t", session, "-F", "#{window_name}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        let reserved = ProcessCleanup.reservedWindows
        return output.split(separator: "\n")
            .filter { !reserved.contains(String($0)) }
            .count
    }

    private func shellExec(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ShikiCommandError.processExitedWithCode(process.terminationStatus)
        }
    }
}

enum ShikiCommandError: Error, CustomStringConvertible {
    case processExitedWithCode(Int32)

    var description: String {
        switch self {
        case .processExitedWithCode(let code):
            return "Process exited with code \(code)"
        }
    }
}
