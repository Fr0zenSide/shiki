import Foundation

// MARK: - NATSConfig

/// Configuration model for nats-server.
/// Generates a valid nats-server.conf from structured Swift values.
///
/// Default config:
/// - listen: 127.0.0.1:4222
/// - max_payload: 1MB
/// - authorization via token
/// - log to ~/.shiki/logs/nats-server.log
public struct NATSConfig: Sendable, Equatable {

    /// Host to bind nats-server.
    public let host: String

    /// Port to bind nats-server.
    public let port: Int

    /// Max message payload in bytes.
    public let maxPayload: Int

    /// Authorization token. Generated on first start if missing.
    public let authToken: String

    /// Path to the log file for nats-server output.
    public let logFile: String

    /// Path to the PID file.
    public let pidFile: String

    public init(
        host: String = "127.0.0.1",
        port: Int = 4222,
        maxPayload: Int = 1_048_576,
        authToken: String = "",
        logFile: String = "",
        pidFile: String = ""
    ) {
        self.host = host
        self.port = port
        self.maxPayload = maxPayload
        self.authToken = authToken.isEmpty ? Self.generateToken() : authToken
        self.logFile = logFile.isEmpty ? Self.defaultLogFile : logFile
        self.pidFile = pidFile.isEmpty ? Self.defaultPidFile : pidFile
    }

    // MARK: - Path Resolution

    /// Base config directory: ~/.config/shiki/
    public static var configDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/shiki"
    }

    /// Config file path: ~/.config/shiki/nats-server.conf
    public static var configFilePath: String {
        "\(configDirectory)/nats-server.conf"
    }

    /// Binary path: ~/.config/shiki/bin/nats-server
    public static var binaryPath: String {
        "\(configDirectory)/bin/nats-server"
    }

    /// Default log file path.
    public static var defaultLogFile: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shiki/logs/nats-server.log"
    }

    /// Default PID file path.
    public static var defaultPidFile: String {
        "\(configDirectory)/nats-server.pid"
    }

    /// NKey seed file path (future use).
    public static var nkeyFilePath: String {
        "\(configDirectory)/nats-key.nk"
    }

    // MARK: - Config Serialization

    /// Generate a nats-server.conf file content string.
    public func toConfigFileContent() -> String {
        """
        # Shikki NATS Server Configuration
        # Auto-generated — do not edit manually.

        listen: \(host):\(port)
        max_payload: \(maxPayload)

        authorization {
            token: "\(authToken)"
        }

        log_file: "\(logFile)"
        pid_file: "\(pidFile)"
        """
    }

    /// Write the config to disk at the standard path.
    /// Creates parent directories if needed.
    public func writeToFile(at path: String? = nil) throws {
        let filePath = path ?? Self.configFilePath
        let dir = (filePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        try toConfigFileContent().write(
            toFile: filePath,
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Token Generation

    /// Generate a random 32-character hex auth token.
    public static func generateToken() -> String {
        (0..<16).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
    }

    // MARK: - Default Config

    /// Default configuration suitable for local development.
    public static var `default`: NATSConfig {
        NATSConfig()
    }
}
