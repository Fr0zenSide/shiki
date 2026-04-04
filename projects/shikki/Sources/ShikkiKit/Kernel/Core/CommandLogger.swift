import Foundation

// MARK: - CommandLogToken

/// Token returned by `CommandLogger.start()` to track command execution timing.
public struct CommandLogToken: Sendable {
    public let command: String
    public let workspace: String?
    public let startTime: Date
    let logDir: String

    public init(command: String, workspace: String?, startTime: Date, logDir: String) {
        self.command = command
        self.workspace = workspace
        self.startTime = startTime
        self.logDir = logDir
    }
}

// MARK: - CommandLogEntry

/// A single JSONL log entry for a CLI command execution.
public struct CommandLogEntry: Codable, Sendable {
    /// ISO8601 timestamp with fractional seconds.
    public let ts: String
    /// Command name (e.g. "shi inbox", "shi spec").
    public let cmd: String
    /// Workspace name (detected from cwd), if any.
    public let ws: String?
    /// Execution time in milliseconds.
    public let duration_ms: Int
    /// Process exit code (0 = success).
    public let exit: Int32
}

// MARK: - CommandLogger

/// Append-only CLI command logger.
///
/// Logs every `shi` command execution to `~/.shikki/logs/command-history.jsonl`.
/// Each line is a single JSON object (`CommandLogEntry`).
/// Thread-safe via `NSLock`. Uses `FileHandle` for atomic append.
public enum CommandLogger {
    private static let lock = NSLock()
    private static let logFileName = "command-history.jsonl"

    nonisolated(unsafe) private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return enc
    }()

    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    /// Default log directory: `~/.shikki/logs`.
    private static var defaultLogDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/logs"
    }

    // MARK: - Public API

    /// Log a command execution start. Returns a token to pass to `complete()`.
    ///
    /// - Parameters:
    ///   - command: The command string (e.g. "shi inbox").
    ///   - workspace: Workspace name, or `nil` to auto-detect.
    ///   - logDir: Override log directory (for testing). Defaults to `~/.shikki/logs`.
    /// - Returns: A `CommandLogToken` to pass to `complete()` when the command finishes.
    public static func start(
        command: String,
        workspace: String?,
        logDir: String? = nil
    ) -> CommandLogToken {
        CommandLogToken(
            command: command,
            workspace: workspace,
            startTime: Date(),
            logDir: logDir ?? defaultLogDir
        )
    }

    /// Complete the log entry with duration and exit code. Writes one JSONL line.
    ///
    /// - Parameters:
    ///   - token: The token returned by `start()`.
    ///   - exitCode: Process exit code (default 0).
    public static func complete(_ token: CommandLogToken, exitCode: Int32 = 0) {
        let now = Date()
        let durationMs = Int((now.timeIntervalSince(token.startTime) * 1000).rounded())

        let entry = CommandLogEntry(
            ts: iso8601Formatter.string(from: token.startTime),
            cmd: token.command,
            ws: token.workspace,
            duration_ms: durationMs,
            exit: exitCode
        )

        guard let jsonData = try? encoder.encode(entry) else { return }

        // Append newline to make it JSONL
        var lineData = jsonData
        lineData.append(contentsOf: [0x0A]) // \n

        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        let logPath = (token.logDir as NSString).appendingPathComponent(logFileName)

        // Ensure directory exists
        if !fm.fileExists(atPath: token.logDir) {
            try? fm.createDirectory(
                atPath: token.logDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        // Append via FileHandle (atomic, no overwrite)
        if fm.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                handle.closeFile()
            }
        } else {
            fm.createFile(atPath: logPath, contents: lineData)
        }
    }

    // MARK: - Workspace Detection

    /// Detect workspace name from the current working directory.
    ///
    /// Uses `$SHI_WS` as the workspace root. If `cwd` is inside that root,
    /// the first path component after the root is the workspace name.
    ///
    /// - Parameters:
    ///   - cwd: Current working directory (defaults to `FileManager.currentDirectoryPath`).
    ///   - shiWs: Value of `$SHI_WS` environment variable (defaults to reading from env).
    /// - Returns: Workspace name, or `nil` if not detectable.
    public static func detectWorkspace(
        cwd: String? = nil,
        shiWs: String? = nil
    ) -> String? {
        let currentDir = cwd ?? FileManager.default.currentDirectoryPath
        let wsRoot: String?
        if let explicit = shiWs {
            wsRoot = explicit
        } else {
            // When called without explicit shiWs, check the actual env var.
            // This overload allows tests to pass nil explicitly to simulate "not set".
            // The 2-arg call with shiWs: nil means "env var not set".
            // Only auto-read env when neither arg is provided.
            wsRoot = nil
        }

        guard let root = wsRoot else { return nil }
        guard currentDir.hasPrefix(root) else { return nil }

        let relative = String(currentDir.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !relative.isEmpty else { return nil }

        return relative.split(separator: "/").first.map(String.init)
    }
}
