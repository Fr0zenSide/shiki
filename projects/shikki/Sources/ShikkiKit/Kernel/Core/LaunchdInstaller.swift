import Foundation

/// Generates and manages macOS LaunchAgent plists for the Shikki daemon.
///
/// Supports two modes:
/// - **persistent**: Long-running daemon with `KeepAlive` (auto-restart on crash).
/// - **scheduled**: Oneshot invocation every 30 seconds via `StartInterval`.
///
/// Plists are installed to `~/Library/LaunchAgents/` and loaded via `launchctl`.
public enum LaunchdInstaller {

    // MARK: - Constants

    private static let persistentLabel = "dev.shikki.daemon"
    private static let scheduledLabel = "dev.shikki.daemon-scheduled"
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    // MARK: - Plist Generation

    /// Generate plist XML for a persistent (KeepAlive) daemon.
    ///
    /// - Parameter binaryPath: Absolute path to the `shi` binary.
    /// - Returns: Complete plist XML string.
    public static func generatePersistentPlist(binaryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(persistentLabel)</string>
            <key>ProgramArguments</key><array>
                <string>\(binaryPath)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>StandardOutPath</key><string>\(home)/.shikki/logs/daemon.stdout.log</string>
            <key>StandardErrorPath</key><string>\(home)/.shikki/logs/daemon.stderr.log</string>
            <key>EnvironmentVariables</key><dict>
                <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
            </dict>
        </dict>
        </plist>
        """
    }

    /// Generate plist XML for a scheduled (StartInterval) daemon.
    ///
    /// The process exits after each tick. launchd re-launches every 30 seconds.
    ///
    /// - Parameter binaryPath: Absolute path to the `shi` binary.
    /// - Returns: Complete plist XML string.
    public static func generateScheduledPlist(binaryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(scheduledLabel)</string>
            <key>ProgramArguments</key><array>
                <string>\(binaryPath)</string>
                <string>daemon</string>
                <string>--mode</string>
                <string>scheduled</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>StartInterval</key><integer>30</integer>
            <key>StandardOutPath</key><string>\(home)/.shikki/logs/daemon.stdout.log</string>
            <key>StandardErrorPath</key><string>\(home)/.shikki/logs/daemon.stderr.log</string>
            <key>EnvironmentVariables</key><dict>
                <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
            </dict>
        </dict>
        </plist>
        """
    }

    // MARK: - Install / Uninstall

    /// Path to the plist file for the given mode.
    public static func plistPath(for mode: DaemonMode) -> String {
        let label = mode == .persistent ? persistentLabel : scheduledLabel
        return "\(home)/Library/LaunchAgents/\(label).plist"
    }

    /// Install the plist to `~/Library/LaunchAgents/` and load it via `launchctl`.
    ///
    /// - Parameter mode: Daemon mode to install.
    /// - Throws: If the plist cannot be written or `launchctl load` fails.
    public static func install(mode: DaemonMode) throws {
        let binaryPath = resolveBinaryPath()
        let plistContent: String
        switch mode {
        case .persistent:
            plistContent = generatePersistentPlist(binaryPath: binaryPath)
        case .scheduled:
            plistContent = generateScheduledPlist(binaryPath: binaryPath)
        }

        let path = plistPath(for: mode)
        let dir = (path as NSString).deletingLastPathComponent

        // Ensure ~/Library/LaunchAgents/ exists
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }

        try plistContent.write(toFile: path, atomically: true, encoding: .utf8)

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LaunchdInstallerError.loadFailed(path: path, exitCode: process.terminationStatus)
        }
    }

    /// Unload and remove the plist for the given mode.
    ///
    /// - Parameter mode: Daemon mode to uninstall.
    /// - Throws: If `launchctl unload` or file removal fails.
    public static func uninstall(mode: DaemonMode) throws {
        let path = plistPath(for: mode)

        guard FileManager.default.fileExists(atPath: path) else {
            return // Nothing to uninstall
        }

        // Unload the agent (ignore errors -- it may not be loaded)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", path]
        try process.run()
        process.waitUntilExit()

        try FileManager.default.removeItem(atPath: path)
    }

    /// Check if the plist file is installed for the given mode.
    public static func isInstalled(mode: DaemonMode) -> Bool {
        FileManager.default.fileExists(atPath: plistPath(for: mode))
    }

    // MARK: - Private

    /// Resolve the absolute path to the current binary.
    private static func resolveBinaryPath() -> String {
        let arg0 = ProcessInfo.processInfo.arguments[0]
        // Resolve symlinks to get the real path
        let url = URL(fileURLWithPath: arg0).standardized
        return url.path
    }
}

// MARK: - LaunchdInstallerError

public enum LaunchdInstallerError: Error, CustomStringConvertible {
    case loadFailed(path: String, exitCode: Int32)

    public var description: String {
        switch self {
        case .loadFailed(let path, let exitCode):
            return "launchctl load failed for \(path) (exit code \(exitCode))"
        }
    }
}
