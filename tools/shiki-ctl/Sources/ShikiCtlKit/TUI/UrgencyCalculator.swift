import Foundation

// MARK: - Urgency Level

public enum UrgencyLevel: String, Sendable {
    case critical   // red — blocking within scope
    case aging      // yellow — past scope cadence
    case ready      // green — actionable
    case deferred   // dim — explicitly deferred
}

// MARK: - Urgency Calculator

/// Computes urgency level for a list item relative to its scope peers.
/// Urgency is scoped: a maya P1 blocking 3 maya items is critical within maya,
/// but a kintsugi P1 with no blockers is just ready.
public enum UrgencyCalculator {

    /// Cadence thresholds (hours) per priority level.
    private static let cadence: [String: Int] = [
        "P0": 48,
        "P1": 96,
        "P2": 168,
        "P3": 336,
    ]

    /// Compute urgency for an item relative to its scope peers.
    public static func urgency(
        for item: ListItem,
        withinScope scopeItems: [ListItem]
    ) -> UrgencyLevel {
        // Deferred check
        if item.metadata["deferred"] == "true" {
            return .deferred
        }

        // Only actionable items get urgency
        guard !item.status.isReviewed else {
            return .ready
        }

        // Critical: item blocks a P0/P1 peer within scope
        if let blocksStr = item.metadata["blocks"] {
            let blockedIds = Set(
                blocksStr
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            )
            let blockedPeers = scopeItems.filter { blockedIds.contains($0.id) }
            let blocksHighPriority = blockedPeers.contains { peer in
                let priority = peer.metadata["priority"] ?? ""
                return priority == "P0" || priority == "P1"
            }
            if blocksHighPriority {
                return .critical
            }
        }

        // Aging: past cadence threshold for its priority
        if let created = item.metadata["created"],
           let priority = item.metadata["priority"],
           let threshold = cadence[priority] {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: created) {
                let hours = Int(Date().timeIntervalSince(date) / 3600)
                if hours > threshold {
                    return .aging
                }
            }
        }

        return .ready
    }
}
