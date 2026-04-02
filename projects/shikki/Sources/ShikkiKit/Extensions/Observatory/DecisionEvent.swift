import Foundation

// MARK: - DecisionCategory

/// What kind of decision this is.
public enum DecisionCategory: String, Codable, Sendable, CaseIterable {
    case architecture      // structural design choice
    case implementation    // how to build something
    case process           // workflow/pipeline decision
    case tradeOff          // explicit X vs Y evaluation
    case scope             // what's in/out of scope
}

// MARK: - DecisionImpact

/// How broadly this decision affects the system.
public enum DecisionImpact: String, Codable, Sendable, CaseIterable {
    case architecture  // affects system structure
    case implementation // affects current task only
    case process       // affects how we work
}

// MARK: - DecisionEvent

/// A structured record of an architecture/implementation/process decision.
/// Immutable once created. Links to parent decisions for chain traceability.
public struct DecisionEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let sessionId: String
    public let agentPersona: String?
    public let companySlug: String?
    public let category: DecisionCategory
    public let question: String
    public let choice: String
    public let rationale: String
    public let alternatives: [String]
    public let impact: DecisionImpact
    public let confidence: Double    // 0.0 to 1.0
    public let parentDecisionId: UUID?
    public let tags: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionId: String,
        agentPersona: String? = nil,
        companySlug: String? = nil,
        category: DecisionCategory,
        question: String,
        choice: String,
        rationale: String,
        alternatives: [String] = [],
        impact: DecisionImpact,
        confidence: Double = 1.0,
        parentDecisionId: UUID? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.agentPersona = agentPersona
        self.companySlug = companySlug
        self.category = category
        self.question = question
        self.choice = choice
        self.rationale = rationale
        self.alternatives = alternatives
        self.impact = impact
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.parentDecisionId = parentDecisionId
        self.tags = tags
    }

    /// Convert to a ShikkiEvent for EventBus publishing.
    public func toShikkiEvent() -> ShikkiEvent {
        let eventType: EventType
        switch category {
        case .architecture:
            eventType = .architectureChoice
        case .tradeOff:
            eventType = .tradeOffEvaluated
        default:
            eventType = .decisionMade
        }

        return ShikkiEvent(
            source: agentPersona.map { .agent(id: sessionId, name: $0) } ?? .system,
            type: eventType,
            scope: companySlug.map { .project(slug: $0) } ?? .session(id: sessionId),
            payload: [
                "question": .string(question),
                "choice": .string(choice),
                "rationale": .string(rationale),
                "category": .string(category.rawValue),
                "impact": .string(impact.rawValue),
                "confidence": .double(confidence),
            ],
            metadata: EventMetadata(tags: tags)
        )
    }
}

// MARK: - DecisionQuery

/// Composable filter for querying decisions.
public struct DecisionQuery: Sendable {
    public var sessionId: String?
    public var companySlug: String?
    public var category: DecisionCategory?
    public var impact: DecisionImpact?
    public var parentDecisionId: UUID?
    public var tags: Set<String>?
    public var since: Date?
    public var until: Date?

    public static let all = DecisionQuery()

    public init(
        sessionId: String? = nil,
        companySlug: String? = nil,
        category: DecisionCategory? = nil,
        impact: DecisionImpact? = nil,
        parentDecisionId: UUID? = nil,
        tags: Set<String>? = nil,
        since: Date? = nil,
        until: Date? = nil
    ) {
        self.sessionId = sessionId
        self.companySlug = companySlug
        self.category = category
        self.impact = impact
        self.parentDecisionId = parentDecisionId
        self.tags = tags
        self.since = since
        self.until = until
    }

    /// Test whether a decision matches this query.
    public func matches(_ decision: DecisionEvent) -> Bool {
        if let sessionId, decision.sessionId != sessionId { return false }
        if let companySlug, decision.companySlug != companySlug { return false }
        if let category, decision.category != category { return false }
        if let impact, decision.impact != impact { return false }
        if let parentDecisionId, decision.parentDecisionId != parentDecisionId { return false }
        if let tags, !tags.isSubset(of: Set(decision.tags)) { return false }
        if let since, decision.timestamp < since { return false }
        if let until, decision.timestamp > until { return false }
        return true
    }
}

// MARK: - DecisionChain

/// Reconstructed chain of decisions linked by parentDecisionId.
public struct DecisionChain: Sendable {
    public let root: DecisionEvent
    public let children: [DecisionEvent]

    public init(root: DecisionEvent, children: [DecisionEvent]) {
        self.root = root
        self.children = children
    }

    /// Total depth of this chain (root = 1).
    public var depth: Int {
        children.isEmpty ? 1 : 1 + children.count
    }

    /// All decisions in order: root first, then children by timestamp.
    public var allDecisions: [DecisionEvent] {
        [root] + children.sorted { $0.timestamp < $1.timestamp }
    }
}
