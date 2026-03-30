import Foundation

// MARK: - DecisionTier

/// Decision urgency tier. T1 blocks progress, T2 can be deferred.
public enum DecisionTier: Int, Codable, Sendable, Comparable {
    case t1 = 1  // blocks pipeline — must be answered before continuing
    case t2 = 2  // deferrable — pipeline can continue, answer improves quality

    public static func < (lhs: DecisionTier, rhs: DecisionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DecisionItem

/// A single question queued for @Daimyo to answer.
public struct DecisionItem: Codable, Sendable, Identifiable {
    public let id: String
    public let featureId: String
    public let tier: DecisionTier
    public let question: String
    public let context: String?
    public let options: [String]?
    public let createdAt: Date
    public var answer: String?
    public var answeredAt: Date?

    public var isAnswered: Bool { answer != nil }

    public init(
        id: String = UUID().uuidString,
        featureId: String,
        tier: DecisionTier,
        question: String,
        context: String? = nil,
        options: [String]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.featureId = featureId
        self.tier = tier
        self.question = question
        self.context = context
        self.options = options
        self.createdAt = createdAt
    }
}

// MARK: - DecisionQueue

/// Queues T1/T2 questions for human decision, blocks lifecycle until answered.
/// Governor gate: the reactor stops here, @Daimyo walks through.
public actor DecisionQueue {
    private var items: [DecisionItem] = []
    private let persister: (any EventPersisting)?

    public init(persister: (any EventPersisting)? = nil) {
        self.persister = persister
    }

    /// Enqueue a new decision. Returns the item ID.
    @discardableResult
    public func enqueue(_ item: DecisionItem) async -> String {
        items.append(item)

        if let persister {
            let payload = CoreEvent.governorGateReached(
                featureId: item.featureId,
                gate: "decision-\(item.tier)"
            )
            await persister.persist(payload)
        }

        return item.id
    }

    /// Answer a queued decision by ID.
    public func answer(id: String, answer: String) async -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        items[idx].answer = answer
        items[idx].answeredAt = Date()

        if let persister {
            let payload = CoreEvent.governorGateCleared(
                featureId: items[idx].featureId,
                gate: "decision-\(items[idx].tier)"
            )
            await persister.persist(payload)
        }

        return true
    }

    /// All pending (unanswered) decisions for a feature.
    public func pending(featureId: String) -> [DecisionItem] {
        items.filter { $0.featureId == featureId && !$0.isAnswered }
    }

    /// All pending T1 decisions (blockers) for a feature.
    public func blockers(featureId: String) -> [DecisionItem] {
        pending(featureId: featureId).filter { $0.tier == .t1 }
    }

    /// Check if a feature has any blocking (T1) decisions pending.
    public func isBlocked(featureId: String) -> Bool {
        !blockers(featureId: featureId).isEmpty
    }

    /// All decisions (pending + answered) for a feature.
    public func all(featureId: String) -> [DecisionItem] {
        items.filter { $0.featureId == featureId }
    }

    /// Total count of pending decisions.
    public var pendingCount: Int {
        items.filter { !$0.isAnswered }.count
    }
}
