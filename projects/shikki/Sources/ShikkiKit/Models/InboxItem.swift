import Foundation

/// A unified inbox item aggregated from multiple sources.
/// The inbox is virtual — no DB table. Items are fetched from
/// GitHub PRs, pending decisions, specs, completed tasks, and ship gate results.
public struct InboxItem: Sendable, Identifiable, Codable {
    /// Format: "{type}:{source_id}" — e.g. "pr:42", "decision:abc-123"
    public let id: String
    public let type: ItemType
    public let title: String
    public let subtitle: String?
    public let status: ReviewStatus
    /// Seconds since item became actionable
    public let age: TimeInterval
    public let companySlug: String?
    /// 0-100 composite score (age + priority + blocking impact)
    public let urgencyScore: Int
    /// Type-specific fields (pr: number/branch/author, decision: tier/question, etc.)
    public let metadata: [String: String]

    public enum ItemType: String, Sendable, CaseIterable, Codable {
        case pr, decision, spec, task, gate
    }

    public enum ReviewStatus: String, Sendable, Codable {
        case pending
        case inReview
        case validated
        case corrected
        case deferred
    }

    public init(
        id: String,
        type: ItemType,
        title: String,
        subtitle: String? = nil,
        status: ReviewStatus = .pending,
        age: TimeInterval,
        companySlug: String? = nil,
        urgencyScore: Int,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.age = age
        self.companySlug = companySlug
        self.urgencyScore = urgencyScore
        self.metadata = metadata
    }

    // MARK: - ID Parsing

    /// Extract the source-specific ID from the composite id.
    /// "pr:42" -> "42", "decision:abc-123" -> "abc-123"
    public var sourceId: String {
        let parts = id.split(separator: ":", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : id
    }

    /// Extract the PR number from a PR inbox item. Returns nil for non-PR items.
    public var prNumber: Int? {
        guard type == .pr else { return nil }
        return Int(sourceId)
    }
}

// MARK: - Urgency Score Calculation

public enum UrgencyCalculator {

    /// Calculate urgency score from age, priority weight, and blocking status.
    /// Formula: ageWeight (0-40) + priorityWeight (0-30) + blockingWeight (0-30) = 0-100
    public static func score(
        age: TimeInterval,
        priorityWeight: Int,
        isBlocking: Bool
    ) -> Int {
        let aw = ageWeight(age)
        let pw = min(max(priorityWeight, 0), 30)
        let bw = isBlocking ? 30 : 0
        return min(aw + pw + bw, 100)
    }

    /// Age weight: 0-40 based on how long the item has been waiting.
    public static func ageWeight(_ age: TimeInterval) -> Int {
        let hours = age / 3600
        switch hours {
        case ..<1: return 0
        case 1..<4: return 10
        case 4..<12: return 20
        case 12..<24: return 30
        default: return 40
        }
    }

    /// Priority weight for PRs based on files changed count.
    public static func prPriorityWeight(filesChanged: Int) -> Int {
        switch filesChanged {
        case ..<6: return 5
        case 6..<20: return 15
        default: return 30
        }
    }

    /// Priority weight for decisions based on tier.
    public static func decisionPriorityWeight(tier: Int) -> Int {
        switch tier {
        case 1: return 30
        case 2: return 20
        default: return 10
        }
    }

    /// Priority weight for tasks based on task priority (inverse: 0=30, 50=15, 99=0).
    public static func taskPriorityWeight(priority: Int) -> Int {
        max(0, 30 - (priority * 30 / 99))
    }

    /// Priority weight for gate results.
    public static func gatePriorityWeight(failed: Bool) -> Int {
        failed ? 30 : 10
    }
}

// MARK: - Inbox Filters

public struct InboxFilters: Sendable {
    public let companySlug: String?
    public let types: Set<InboxItem.ItemType>?
    public let status: InboxItem.ReviewStatus?

    public init(
        companySlug: String? = nil,
        types: Set<InboxItem.ItemType>? = nil,
        status: InboxItem.ReviewStatus? = nil
    ) {
        self.companySlug = companySlug
        self.types = types
        self.status = status
    }
}

// MARK: - Inbox Count

public struct InboxCount: Codable, Sendable {
    public let prs: Int
    public let decisions: Int
    public let specs: Int
    public let tasks: Int
    public let gates: Int
    public var total: Int { prs + decisions + specs + tasks + gates }

    public init(prs: Int = 0, decisions: Int = 0, specs: Int = 0, tasks: Int = 0, gates: Int = 0) {
        self.prs = prs
        self.decisions = decisions
        self.specs = specs
        self.tasks = tasks
        self.gates = gates
    }
}
