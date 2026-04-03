import Foundation

// MARK: - DaemonPIDError

/// Errors thrown by DaemonPIDManager.
public enum DaemonPIDError: Error, Sendable {
    case alreadyRunning(pid: Int32)
    case ioError(String)
}

// MARK: - DaemonPIDManager

/// Manages PID file lifecycle for the Shikki daemon process.
///
/// The PID file at `~/.shikki/daemon.pid` tracks whether a daemon instance
/// is currently running. Uses `kill(pid, 0)` to verify process liveness
/// and handles stale PID cleanup.
public struct DaemonPIDManager: Sendable {

    /// Path to the PID file.
    public let pidPath: String

    public init(pidPath: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.pidPath = pidPath ?? "\(home)/.shikki/daemon.pid"
    }

    // MARK: - Public API

    /// Write current process PID to the PID file.
    /// Fails if PID file exists with an alive process.
    /// Succeeds over stale PID files (dead process).
    public func acquire() throws {
        let fm = FileManager.default

        // Ensure parent directory exists
        let dir = (pidPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700,
            ])
        }

        // Check for existing PID file
        if fm.fileExists(atPath: pidPath) {
            if let existingPid = readPID(), processIsAlive(existingPid) {
                throw DaemonPIDError.alreadyRunning(pid: existingPid)
            }
            // Stale PID file — remove it
            try? fm.removeItem(atPath: pidPath)
        }

        // Write our PID
        let pid = "\(ProcessInfo.processInfo.processIdentifier)"
        try pid.write(toFile: pidPath, atomically: true, encoding: .utf8)
    }

    /// Remove PID file.
    public func release() {
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    /// Read PID from file. Returns nil if no file or unparseable content.
    public func readPID() -> Int32? {
        guard let content = try? String(contentsOfFile: pidPath, encoding: .utf8) else {
            return nil
        }
        return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Check if a daemon is currently running (PID file exists + process alive).
    public func isRunning() -> Bool {
        guard let pid = readPID() else { return false }
        return processIsAlive(pid)
    }

    /// Remove stale PID file (process dead but file remains).
    /// Returns true if a stale file was cleaned up.
    @discardableResult
    public func cleanStale() -> Bool {
        guard let pid = readPID() else { return false }

        if processIsAlive(pid) {
            return false
        }

        // PID file exists but process is dead — stale
        try? FileManager.default.removeItem(atPath: pidPath)
        return true
    }

    // MARK: - Private

    private func processIsAlive(_ pid: Int32) -> Bool {
        // kill(pid, 0) sends no signal, just checks if process exists.
        // Returns 0 if we can signal the process.
        // Returns -1 with errno ESRCH if process doesn't exist.
        // Returns -1 with errno EPERM if process exists but we lack permission — still alive.
        let result = kill(pid, 0)
        if result == 0 { return true }
        return errno != ESRCH
    }
}
