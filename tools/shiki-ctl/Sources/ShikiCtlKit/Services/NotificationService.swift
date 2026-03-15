import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import NIOFoundationCompat

/// Sends push notifications via ntfy.sh. Reads config from ~/.config/shiki-notify/config.
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
        var request = HTTPClientRequest(url: "\(serverURL)/\(topic)")
        request.method = .POST
        request.headers.add(name: "Title", value: title)
        request.headers.add(name: "Priority", value: "\(priority.rawValue)")
        request.headers.add(name: "Tags", value: tags.joined(separator: ","))
        request.body = .bytes(ByteBuffer(string: body))

        let response = try await httpClient.execute(request, timeout: .seconds(10))
        guard (200...299).contains(Int(response.status.code)) else {
            logger.warning("ntfy send failed: HTTP \(response.status.code)")
            return
        }
        logger.debug("Notification sent: \(title)")
    }
}

/// No-op notification sender for testing or when notifications are disabled.
public struct NoOpNotificationSender: NotificationSender, Sendable {
    public init() {}
    public func send(title: String, body: String, priority: NotificationPriority, tags: [String]) async throws {}
}
