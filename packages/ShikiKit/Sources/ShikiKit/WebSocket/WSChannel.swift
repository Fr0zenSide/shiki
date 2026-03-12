import Foundation

/// Helper for constructing WebSocket channel names.
/// Channels follow the pattern `project:<uuid>` for project-scoped subscriptions.
public enum WSChannel: Sendable {

    /// Channel for receiving all events related to a specific project.
    public static func project(_ id: UUID) -> String {
        "project:\(id.uuidString.lowercased())"
    }

    /// Channel for receiving session-specific events.
    public static func session(_ id: UUID) -> String {
        "session:\(id.uuidString.lowercased())"
    }

    /// Extracts the UUID from a channel string, if it follows the `prefix:uuid` format.
    public static func extractId(from channel: String) -> UUID? {
        let parts = channel.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    /// Returns the prefix of a channel string (e.g., "project" from "project:<uuid>").
    public static func prefix(of channel: String) -> String? {
        let parts = channel.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }
}
