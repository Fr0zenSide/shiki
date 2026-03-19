import ArgumentParser
import Foundation

struct RestartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart the orchestrator heartbeat (preserves tmux session)"
    )

    @Option(name: .long, help: "Tmux session name (defaults to workspace folder name)")
    var session: String = "shiki"

    @Option(name: .long, help: "Workspace root path (auto-detected if omitted)")
    var workspace: String?

    func run() async throws {
        let workspacePath = resolveWorkspaceForRestart()

        guard tmuxSessionExists(session) else {
            print("\u{1B}[2mNo session running — use 'shiki start' for full startup\u{1B}[0m")
            return
        }

        print("\u{1B}[33mRestarting Shiki orchestrator...\u{1B}[0m")

        // Find orchestrator window
        guard let orchPane = findOrchestratorPane(session) else {
            print("  \u{1B}[31mCould not find orchestrator window\u{1B}[0m")
            return
        }

        // Send Ctrl-C to stop current heartbeat
        try shellExec("tmux", arguments: ["send-keys", "-t", orchPane, "C-c"])
        try await Task.sleep(for: .seconds(1))

        // Resolve binary path
        let binaryPath = "\(workspacePath)/tools/shiki-ctl/.build/debug/shiki-ctl"
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            print("  \u{1B}[31mBinary not found at \(binaryPath)\u{1B}[0m")
            return
        }

        // Relaunch heartbeat
        let cmd = "\(binaryPath) heartbeat --workspace \(workspacePath)"
        try shellExec("tmux", arguments: ["send-keys", "-t", orchPane, cmd, "C-m"])

        print("  \u{1B}[32mOrchestrator restarted (session preserved)\u{1B}[0m")
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

    private func findOrchestratorPane(_ session: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "list-windows", "-t", session, "-F", "#{window_id} #{window_name}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard let orchLine = output.split(separator: "\n").first(where: { $0.contains("orchestrator") }) else {
            return nil
        }
        let windowId = String(orchLine.split(separator: " ").first ?? "")
        guard !windowId.isEmpty else { return nil }

        // Get first pane in that window
        let paneProcess = Process()
        paneProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        paneProcess.arguments = ["tmux", "list-panes", "-t", windowId, "-F", "#{pane_id}"]
        let panePipe = Pipe()
        paneProcess.standardOutput = panePipe
        paneProcess.standardError = FileHandle.nullDevice
        try? paneProcess.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let paneData = panePipe.fileHandleForReading.readDataToEndOfFile()
        paneProcess.waitUntilExit()
        let paneOutput = String(data: paneData, encoding: .utf8) ?? ""
        return paneOutput.split(separator: "\n").first.map(String.init)
    }

    private func resolveWorkspaceForRestart() -> String {
        if let workspace, !workspace.isEmpty { return workspace }
        let binaryPath = ProcessInfo.processInfo.arguments.first ?? ""
        let resolved = (binaryPath as NSString).resolvingSymlinksInPath
        if resolved.contains("/tools/shiki-ctl/.build/") {
            let components = resolved.components(separatedBy: "/tools/shiki-ctl/.build/")
            if let root = components.first, !root.isEmpty { return root }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let known = "\(home)/Documents/Workspaces/shiki"
        if FileManager.default.fileExists(atPath: "\(known)/docker-compose.yml") { return known }
        return FileManager.default.currentDirectoryPath
    }

    private func shellExec(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
