import Foundation
import Logging

/// Sends push notifications via ntfy.sh. Reads config from ~/.config/shiki-notify/config.
/// Uses curl subprocess for reliability (same as BackendClient).
public struct NtfyNotificationSender: NotificationSender, Sendable {
    let topic: String
    let serverURL: String
    let logger: Logger
    private let httpClient: HTTPClient

    public init(logger: Logger = Logger(label: "shiki-ctl.ntfy")) {
        // Read config from ~/.config/shiki-notify/config
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/shiki-notify/config")
        var topic = "shiki-orchestrator"
        var server = "https://ntfy.sh"

        if let contents = try? String(contentsOf: configPath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("NTFY_TOPIC=") {
                    topic = String(trimmed.dropFirst("NTFY_TOPIC=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                } else if trimmed.hasPrefix("NTFY_SERVER=") {
                    server = String(trimmed.dropFirst("NTFY_SERVER=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }

        self.topic = topic
        self.serverURL = server
        self.logger = logger
        self.httpClient = HTTPClient()
    }

    public func send(title: String, body: String, priority: NotificationPriority, tags: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-s",
            "--max-time", "10",
            "-X", "POST",
            "-H", "Title: \(title)",
            "-H", "Priority: \(priority.rawValue)",
            "-H", "Tags: \(tags.joined(separator: ","))",
            "-d", body,
            "\(serverURL)/\(topic)",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            logger.debug("Notification sent: \(title)")
        } else {
            logger.debug("ntfy unreachable (curl exit \(process.terminationStatus))")
        }
    }
}

/// No-op notification sender for testing or when notifications are disabled.
public struct NoOpNotificationSender: NotificationSender, Sendable {
    public init() {}
    public func send(title: String, body: String, priority: NotificationPriority, tags: [String]) async throws {}
}
