import Foundation

/// Handles cleanup of child processes when stopping Shiki sessions.
///
/// The core problem: `tmux kill-session` sends SIGHUP to panes, but child processes
/// (claude, xcodebuild, swift-test, simulators) can survive as orphans.
///
/// This service:
/// 1. Enumerates all PIDs in task windows BEFORE killing tmux
/// 2. Kills task windows individually (preserving reserved windows)
/// 3. SIGTERM → wait → SIGKILL any surviving child processes
/// 4. Kills the tmux session last
public struct ProcessCleanup: Sendable {

    /// Windows that are never killed during cleanup — they are infrastructure, not tasks.
    public static let reservedWindows: Set<String> = ["orchestrator", "board", "research"]

    public init() {}

    /// Result of a cleanup operation.
    public struct CleanupResult: Sendable {
        public let windowsKilled: Int
        public let orphanPIDsKilled: Int
    }

    // MARK: - PID Collection

    /// Collect all pane PIDs from a tmux session's task windows.
    /// Returns PIDs only from non-reserved windows.
    public func collectSessionPIDs(session: String) -> [pid_t] {
        // List all windows with their pane PIDs
        guard let output = runCapture("tmux", arguments: [
            "list-panes", "-s", "-t", session,
            "-F", "#{window_name} #{pane_pid}",
        ]) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let windowName = String(parts[0])
            let pidStr = String(parts[1])

            // Skip reserved windows
            guard !Self.reservedWindows.contains(windowName) else { return nil }
            return pid_t(pidStr)
        }
    }

    // MARK: - Process Killing

    /// Kill a process and its children. Sends SIGTERM first, waits briefly, then SIGKILL.
    public func killProcessTree(pid: pid_t) {
        // Get child PIDs first (depth-first so children die before parents)
        let children = getChildPIDs(of: pid)

        // Kill children first
        for child in children {
            kill(child, SIGTERM)
        }
        kill(pid, SIGTERM)

        // Brief wait for graceful shutdown
        usleep(500_000) // 500ms

        // Force kill anything still alive
        for child in children {
            kill(child, SIGKILL)
        }
        kill(pid, SIGKILL)
    }

    /// Get all child PIDs of a process using pgrep.
    private func getChildPIDs(of parentPID: pid_t) -> [pid_t] {
        guard let output = runCapture("pgrep", arguments: ["-P", "\(parentPID)"]) else {
            return []
        }
        return output.split(separator: "\n").compactMap { pid_t(String($0)) }
    }

    // MARK: - Full Cleanup

    /// Clean up all task sessions in a tmux session before killing it.
    /// Returns the count of windows and orphan PIDs killed.
    public func cleanupSession(session: String) -> CleanupResult {
        // Step 1: Collect all task window PIDs before we kill anything
        let taskPIDs = collectSessionPIDs(session: session)

        // If no task PIDs found, the session doesn't exist or has no tasks
        guard !taskPIDs.isEmpty else {
            return CleanupResult(windowsKilled: 0, orphanPIDsKilled: 0)
        }

        // Step 2: Get list of task windows (non-reserved)
        let taskWindows = listTaskWindows(session: session)

        // Step 3: Kill each task window individually
        var windowsKilled = 0
        for windowName in taskWindows {
            if let _ = try? runProcess("tmux", arguments: [
                "kill-window", "-t", "\(session):\(windowName)",
            ]) {
                windowsKilled += 1
            }
        }

        // Step 4: Wait briefly for tmux to propagate SIGHUP
        usleep(200_000) // 200ms

        // Step 5: Kill any surviving PIDs from the collected list
        var orphansKilled = 0
        for pid in taskPIDs {
            // Check if process is still alive (kill with signal 0 = check only)
            if kill(pid, 0) == 0 {
                killProcessTree(pid: pid)
                orphansKilled += 1
            }
        }

        return CleanupResult(windowsKilled: windowsKilled, orphanPIDsKilled: orphansKilled)
    }

    /// Find claude processes that are not attached to any tmux pane.
    public func findOrphanedClaudeProcesses() -> [pid_t] {
        // Use exact binary name match to avoid killing unrelated processes
        // (e.g., "vim ~/notes/claude.txt" would match with -f)
        guard let output = runCapture("pgrep", arguments: ["-x", "claude"]) else {
            return []
        }

        let allClaudePIDs = output.split(separator: "\n").compactMap { pid_t(String($0)) }

        // Filter out our own process tree
        let myPID = ProcessInfo.processInfo.processIdentifier
        let parentPID = getppid()
        return allClaudePIDs.filter { $0 != myPID && $0 != parentPID }
    }

    // MARK: - Window Listing

    /// List task window names (excludes reserved windows).
    private func listTaskWindows(session: String) -> [String] {
        guard let output = runCapture("tmux", arguments: [
            "list-windows", "-t", session, "-F", "#{window_name}",
        ]) else { return [] }

        return output.split(separator: "\n")
            .map(String.init)
            .filter { !Self.reservedWindows.contains($0) }
    }

    // MARK: - Helpers

    private func runCapture(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    @discardableResult
    private func runProcess(_ executable: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
