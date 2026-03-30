import Foundation

/// Errors thrown by LockfileManager.
public enum LockfileError: Error, Sendable {
    case alreadyLocked(pid: Int)
    case ioError(String)
}

/// PID lockfile manager to prevent concurrent IDLE→RUNNING transitions.
/// BR-53: PID lockfile at `~/.shikki/shikki.pid`.
/// Acquire/release/stale check. Stale PID → overwrite.
public struct LockfileManager: Sendable {
    public let path: String

    public init(path: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.path = path ?? "\(home)/.shikki/shikki.pid"
    }

    /// Acquire the lock by writing our PID to the lockfile.
    /// If a lockfile exists with a stale PID, it is overridden.
    /// If a lockfile exists with a live PID (different process), throws `alreadyLocked`.
    public func acquire() throws {
        let fm = FileManager.default

        // Ensure parent directory exists
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        // Check for existing lock
        if fm.fileExists(atPath: path) {
            if let existingPid = readPid(), processIsAlive(existingPid) {
                let myPid = ProcessInfo.processInfo.processIdentifier
                if existingPid != Int(myPid) {
                    throw LockfileError.alreadyLocked(pid: existingPid)
                }
                // Same PID — re-acquiring our own lock is fine
                return
            }
            // Stale lock — remove it
            try? fm.removeItem(atPath: path)
        }

        // Write our PID
        let pid = "\(ProcessInfo.processInfo.processIdentifier)"
        try pid.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Release the lock by removing the lockfile.
    public func release() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }

    /// Check if the lock is currently held (lockfile exists with a live PID).
    public func isHeld() -> Bool {
        guard let pid = readPid() else { return false }
        return processIsAlive(pid)
    }

    /// Check if the lockfile contains a stale PID (process no longer running).
    public func isStale() -> Bool {
        guard let pid = readPid() else { return false }
        return !processIsAlive(pid)
    }

    // MARK: - Private

    private func readPid() -> Int? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func processIsAlive(_ pid: Int) -> Bool {
        // kill(pid, 0) returns 0 if we can signal the process.
        // Returns -1 with errno ESRCH if process doesn't exist.
        // Returns -1 with errno EPERM if process exists but we lack permission — still alive.
        let result = kill(Int32(pid), 0)
        if result == 0 { return true }
        return errno != ESRCH
    }
}
