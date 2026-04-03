import Foundation

/// Generates and manages Linux systemd user units for the Shikki daemon.
///
/// Supports two modes:
/// - **persistent**: Long-running service with `Restart=always`.
/// - **scheduled**: Oneshot service triggered by a companion `.timer` unit every 30 seconds.
///
/// Units are installed to `~/.config/systemd/user/` and managed via `systemctl --user`.
public enum SystemdInstaller {

    // MARK: - Constants

    private static let persistentServiceName = "shikki-daemon.service"
    private static let scheduledServiceName = "shikki-daemon-scheduled.service"
    private static let scheduledTimerName = "shikki-daemon-scheduled.timer"
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    // MARK: - Unit Generation

    /// Generate a persistent systemd service unit.
    ///
    /// - Parameter binaryPath: Absolute path to the `shi` binary.
    /// - Returns: Complete systemd unit file content.
    public static func generatePersistentUnit(binaryPath: String) -> String {
        """
        [Unit]
        Description=Shikki Daemon
        After=network.target

        [Service]
        Type=simple
        ExecStart=\(binaryPath) daemon
        Restart=always
        RestartSec=5
        Environment=PATH=/usr/local/bin:/usr/bin:/bin

        [Install]
        WantedBy=default.target
        """
    }

    /// Generate a scheduled (oneshot) systemd service unit.
    ///
    /// - Parameter binaryPath: Absolute path to the `shi` binary.
    /// - Returns: Complete systemd unit file content.
    public static func generateScheduledService(binaryPath: String) -> String {
        """
        [Unit]
        Description=Shikki Daemon Scheduled Tick

        [Service]
        Type=oneshot
        ExecStart=\(binaryPath) daemon --mode scheduled
        """
    }

    /// Generate a systemd timer unit that triggers the scheduled service every 30 seconds.
    ///
    /// - Returns: Complete systemd timer file content.
    public static func generateScheduledTimer() -> String {
        """
        [Unit]
        Description=Shikki Daemon Scheduled Timer

        [Timer]
        OnCalendar=*:*:0/30
        Persistent=true

        [Install]
        WantedBy=timers.target
        """
    }

    // MARK: - Paths

    /// Path to the systemd user unit directory.
    private static var unitDir: String {
        "\(home)/.config/systemd/user"
    }

    /// Path to the service unit file for the given mode.
    public static func unitPath(for mode: DaemonMode) -> String {
        let name = mode == .persistent ? persistentServiceName : scheduledServiceName
        return "\(unitDir)/\(name)"
    }

    /// Path to the timer unit file (only used for scheduled mode).
    public static func timerPath() -> String {
        "\(unitDir)/\(scheduledTimerName)"
    }

    // MARK: - Install / Uninstall

    /// Install systemd units and enable them via `systemctl --user`.
    ///
    /// - Parameter mode: Daemon mode to install.
    /// - Throws: If unit files cannot be written or `systemctl` commands fail.
    public static func install(mode: DaemonMode) throws {
        let binaryPath = resolveBinaryPath()

        // Ensure unit directory exists
        if !FileManager.default.fileExists(atPath: unitDir) {
            try FileManager.default.createDirectory(
                atPath: unitDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }

        switch mode {
        case .persistent:
            let unit = generatePersistentUnit(binaryPath: binaryPath)
            try unit.write(toFile: unitPath(for: .persistent), atomically: true, encoding: .utf8)
            try systemctl("daemon-reload")
            try systemctl("enable", persistentServiceName)
            try systemctl("start", persistentServiceName)

        case .scheduled:
            let service = generateScheduledService(binaryPath: binaryPath)
            let timer = generateScheduledTimer()
            try service.write(toFile: unitPath(for: .scheduled), atomically: true, encoding: .utf8)
            try timer.write(toFile: timerPath(), atomically: true, encoding: .utf8)
            try systemctl("daemon-reload")
            try systemctl("enable", scheduledTimerName)
            try systemctl("start", scheduledTimerName)
        }
    }

    /// Disable and remove systemd units for the given mode.
    ///
    /// - Parameter mode: Daemon mode to uninstall.
    /// - Throws: If `systemctl` commands or file removal fails.
    public static func uninstall(mode: DaemonMode) throws {
        let fm = FileManager.default

        switch mode {
        case .persistent:
            let path = unitPath(for: .persistent)
            guard fm.fileExists(atPath: path) else { return }
            // Stop and disable (ignore errors -- may not be running)
            try? systemctl("stop", persistentServiceName)
            try? systemctl("disable", persistentServiceName)
            try fm.removeItem(atPath: path)
            try? systemctl("daemon-reload")

        case .scheduled:
            let servicePath = unitPath(for: .scheduled)
            let timerPathValue = timerPath()
            guard fm.fileExists(atPath: servicePath) || fm.fileExists(atPath: timerPathValue) else { return }
            try? systemctl("stop", scheduledTimerName)
            try? systemctl("disable", scheduledTimerName)
            if fm.fileExists(atPath: servicePath) { try fm.removeItem(atPath: servicePath) }
            if fm.fileExists(atPath: timerPathValue) { try fm.removeItem(atPath: timerPathValue) }
            try? systemctl("daemon-reload")
        }
    }

    /// Check if the service unit is installed for the given mode.
    public static func isInstalled(mode: DaemonMode) -> Bool {
        FileManager.default.fileExists(atPath: unitPath(for: mode))
    }

    // MARK: - Private

    /// Run a `systemctl --user` command.
    @discardableResult
    private static func systemctl(_ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemctl")
        process.arguments = ["--user"] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Resolve the absolute path to the current binary.
    private static func resolveBinaryPath() -> String {
        let arg0 = ProcessInfo.processInfo.arguments[0]
        let url = URL(fileURLWithPath: arg0).standardized
        return url.path
    }
}

// MARK: - SystemdInstallerError

public enum SystemdInstallerError: Error, CustomStringConvertible {
    case commandFailed(command: String, exitCode: Int32)

    public var description: String {
        switch self {
        case .commandFailed(let command, let exitCode):
            return "systemctl \(command) failed (exit code \(exitCode))"
        }
    }
}
