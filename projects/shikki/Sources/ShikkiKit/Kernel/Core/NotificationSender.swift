/// Abstraction over push notification delivery.
/// Implementations: NtfyNotificationSender (now), APNSNotificationSender (future).
public protocol NotificationSender: Sendable {
    func send(title: String, body: String, priority: NotificationPriority, tags: [String]) async throws
}

public enum NotificationPriority: Int, Sendable {
    case low = 2
    case normal = 3
    case high = 4
    case urgent = 5
}
