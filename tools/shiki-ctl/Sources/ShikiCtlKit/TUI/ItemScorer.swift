import Foundation

// MARK: - Item Score

/// Composite score for sorting list items.
public struct ItemScore: Comparable, Sendable {
    public let isPinned: Bool
    public let pinnedRank: Int      // position in pinnedOrder (0 = top)
    public let priorityWeight: Int  // P0=100, P1=75, P2=50, P3=25
    public let ageWeight: Int       // hours since creation, capped at 168
    public let depsWeight: Int      // number of items blocked by this one
    public let blockingWeight: Int  // 50 if blocking a P0 item, else 0

    /// Composite score (excluding pin status, which always wins).
    public var composite: Int {
        priorityWeight + ageWeight + depsWeight + blockingWeight
    }

    public static func < (lhs: ItemScore, rhs: ItemScore) -> Bool {
        // Pinned items always sort first
        if lhs.isPinned && !rhs.isPinned { return true }
        if !lhs.isPinned && rhs.isPinned { return false }

        // Both pinned: by pin rank (lower = first)
        if lhs.isPinned && rhs.isPinned {
            return lhs.pinnedRank < rhs.pinnedRank
        }

        // Both unpinned: by composite score descending
        return lhs.composite > rhs.composite
    }
}

// MARK: - Item Scorer

/// Pure-function scorer for list items.
/// Reads metadata keys: "priority", "created", "blocks".
public enum ItemScorer {

    /// Compute scores for all items and return them sorted.
    /// Stable sort: items with equal scores maintain original order.
    public static func computeScores(
        items: [ListItem],
        pins: [String]
    ) -> [(ListItem, ItemScore)] {
        let pinSet = Set(pins)
        let itemIds = Set(items.map(\.id))

        // Build a reverse dependency map: which items does each item block?
        var blockedBy: [String: [String]] = [:] // itemId -> [blockerIds]
        for item in items {
            if let blocksStr = item.metadata["blocks"] {
                let blockedIds = blocksStr
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { itemIds.contains($0) }
                for blockedId in blockedIds {
                    blockedBy[blockedId, default: []].append(item.id)
                }
            }
        }

        // Priority lookup for blocking weight
        let priorityMap = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, parsePriority($0.metadata["priority"]))
        })

        let scored: [(ListItem, ItemScore)] = items.enumerated().map { index, item in
            let isPinned = pinSet.contains(item.id)
            let pinnedRank = pins.firstIndex(of: item.id) ?? Int.max

            let priorityWeight = parsePriority(item.metadata["priority"])
            let ageWeight = computeAge(item.metadata["created"])

            // Count how many items this one blocks
            let blocksStr = item.metadata["blocks"] ?? ""
            let blockedIds = blocksStr
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { itemIds.contains($0) }
            let depsWeight = blockedIds.count * 10

            // Check if any blocked item is P0
            let blockingWeight: Int = blockedIds.contains { id in
                (priorityMap[id] ?? 0) >= 100
            } ? 50 : 0

            let score = ItemScore(
                isPinned: isPinned,
                pinnedRank: pinnedRank,
                priorityWeight: priorityWeight,
                ageWeight: ageWeight,
                depsWeight: depsWeight,
                blockingWeight: blockingWeight
            )

            return (item, score)
        }

        // Stable sort by score
        return scored.sorted { $0.1 < $1.1 }
    }

    /// Parse priority string to weight. P0=100, P1=75, P2=50, P3=25, unknown=0.
    public static func parsePriority(_ priority: String?) -> Int {
        switch priority {
        case "P0": return 100
        case "P1": return 75
        case "P2": return 50
        case "P3": return 25
        default: return 0
        }
    }

    /// Compute age weight from ISO8601 date string.
    /// Returns hours since creation, capped at 168 (1 week).
    public static func computeAge(_ dateString: String?) -> Int {
        guard let dateString else { return 0 }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return 0 }
        let hours = Int(Date().timeIntervalSince(date) / 3600)
        return min(max(hours, 0), 168)
    }
}
