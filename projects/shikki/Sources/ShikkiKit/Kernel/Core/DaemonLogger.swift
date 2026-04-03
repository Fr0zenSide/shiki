import Foundation

/// Severity levels for daemon log entries.
public enum DaemonLogLevel: String, Sendable {
    case debug
    case error
    case info
    case warning
}

/// File-based logger with size-based rotation for the Shikki daemon.
///
/// Thread-safe via `NSLock`. Writes to `~/.shikki/logs/daemon.log` by default.
/// When the current log exceeds `maxFileSize`, rotates:
///   daemon.log -> daemon.log.1 -> daemon.log.2 -> ... -> daemon.log.{maxFiles}
/// The oldest file beyond `maxFiles` is deleted.
public final class DaemonLogger: @unchecked Sendable {
    public let logPath: String
    public let maxFileSize: Int
    public let maxFiles: Int

    private let lock = NSLock()
    private let fm = FileManager.default
    private let dateFormatter: DateFormatter

    /// - Parameters:
    ///   - logPath: Absolute path to the log file. Defaults to `~/.shikki/logs/daemon.log`.
    ///   - maxFileSize: Maximum bytes before rotation (default 10 MB).
    ///   - maxFiles: Number of rotated files to keep (default 5).
    public init(logPath: String? = nil, maxFileSize: Int = 10_485_760, maxFiles: Int = 5) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.logPath = logPath ?? "\(home)/.shikki/logs/daemon.log"
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles

        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
    }

    /// Append a log line. Creates the file and parent directories if needed.
    public func log(_ message: String, level: DaemonLogLevel = .info) {
        lock.lock()
        defer { lock.unlock() }

        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)\n"
        let data = Data(line.utf8)

        // Ensure parent directory exists
        let dir = (logPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700,
            ])
        }

        if fm.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            fm.createFile(atPath: logPath, contents: data)
        }
    }

    /// Rotate log files if the current log exceeds `maxFileSize`.
    ///
    /// Rotation chain: daemon.log -> daemon.log.1 -> ... -> daemon.log.{maxFiles}.
    /// Files beyond `maxFiles` are deleted.
    public func rotateIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard let attrs = try? fm.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? Int,
              size >= maxFileSize else {
            return
        }

        // Delete the oldest rotated file if it exists
        let oldest = "\(logPath).\(maxFiles)"
        try? fm.removeItem(atPath: oldest)

        // Shift rotated files: N-1 -> N, N-2 -> N-1, ..., 1 -> 2
        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let src = "\(logPath).\(index)"
            let dst = "\(logPath).\(index + 1)"
            if fm.fileExists(atPath: src) {
                try? fm.moveItem(atPath: src, toPath: dst)
            }
        }

        // Current log -> .1
        try? fm.moveItem(atPath: logPath, toPath: "\(logPath).1")
    }
}
