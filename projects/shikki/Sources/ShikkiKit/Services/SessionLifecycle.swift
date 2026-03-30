import Foundation

// MARK: - Session State Machine

/// 11-state lifecycle for orchestrator sessions.
public enum SessionState: String, Sendable, Codable, Equatable {
    case spawning
    case working
    case awaitingApproval
    case budgetPaused
    case prOpen
    case ciFailed
    case reviewPending
    case changesRequested
    case approved
    case merged
    case done
}

/// Attention zones — always visible, intensity gradient (never filter).
/// Lower rawValue = higher urgency.
public enum AttentionZone: Int, Sendable, Codable, Comparable, Equatable {
    case merge = 0
    case respond = 1
    case review = 2
    case pending = 3
    case working = 4
    case idle = 5

    public static func < (lhs: AttentionZone, rhs: AttentionZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Who triggered the transition.
public enum TransitionActor: Sendable, Codable, Equatable {
    case system
    case user(String)
    case agent(String)
    case governance
}

/// Recorded state transition with full context.
public struct SessionTransition: Sendable, Codable {
    public let from: SessionState
    public let to: SessionState
    public let actor: TransitionActor
    public let reason: String
    public let timestamp: Date

    public init(from: SessionState, to: SessionState, actor: TransitionActor, reason: String, timestamp: Date = Date()) {
        self.from = from
        self.to = to
        self.actor = actor
        self.reason = reason
        self.timestamp = timestamp
    }
}

/// Context for a dispatched task session.
public struct TaskContext: Sendable, Codable {
    public let taskId: String
    public let companySlug: String
    public let projectPath: String
    public var parentSessionId: String?
    public var wakeReason: String?
    public var budgetDailyUsd: Double
    public var spentTodayUsd: Double

    public init(
        taskId: String, companySlug: String, projectPath: String,
        parentSessionId: String? = nil, wakeReason: String? = nil,
        budgetDailyUsd: Double = 0, spentTodayUsd: Double = 0
    ) {
        self.taskId = taskId
        self.companySlug = companySlug
        self.projectPath = projectPath
        self.parentSessionId = parentSessionId
        self.wakeReason = wakeReason
        self.budgetDailyUsd = budgetDailyUsd
        self.spentTodayUsd = spentTodayUsd
    }
}

// MARK: - Errors

public enum SessionLifecycleError: Error, Equatable {
    case invalidTransition(from: SessionState, to: SessionState)
}

// MARK: - Valid Transitions

private let validTransitions: [SessionState: Set<SessionState>] = [
    .spawning: [.working, .done],
    .working: [.awaitingApproval, .budgetPaused, .prOpen, .done],
    .awaitingApproval: [.working, .done],
    .budgetPaused: [.working, .done],
    .prOpen: [.ciFailed, .reviewPending, .approved, .done],
    .ciFailed: [.prOpen, .working, .done],
    .reviewPending: [.changesRequested, .approved, .done],
    .changesRequested: [.prOpen, .working, .done],
    .approved: [.merged, .done],
    .merged: [.done, .working],
    .done: [],
]

// MARK: - State → Attention Zone

extension SessionState {
    /// The attention zone for this state. Single source of truth.
    public var attentionZone: AttentionZone {
        switch self {
        case .spawning: .pending
        case .working: .working
        case .awaitingApproval, .budgetPaused, .ciFailed: .respond
        case .prOpen, .reviewPending, .changesRequested: .review
        case .approved: .merge
        case .merged, .done: .idle
        }
    }
}

// MARK: - SessionLifecycle Actor

/// Manages the lifecycle of a single session with enforced transitions,
/// attention zone mapping, and ZFC reconciliation.
public actor SessionLifecycle {
    public let sessionId: String
    public let context: TaskContext
    public private(set) var currentState: SessionState
    public private(set) var transitionHistory: [SessionTransition] = []

    public init(sessionId: String, context: TaskContext, initialState: SessionState = .spawning) {
        self.sessionId = sessionId
        self.context = context
        self.currentState = initialState
    }

    /// Transition to a new state. Throws if the transition is not valid.
    public func transition(to newState: SessionState, actor: TransitionActor, reason: String) throws {
        guard let allowed = validTransitions[currentState], allowed.contains(newState) else {
            throw SessionLifecycleError.invalidTransition(from: currentState, to: newState)
        }
        let record = SessionTransition(from: currentState, to: newState, actor: actor, reason: reason)
        transitionHistory.append(record)
        currentState = newState
    }

    /// The current attention zone — maps state to urgency level.
    public var attentionZone: AttentionZone {
        currentState.attentionZone
    }

    /// Whether the session should be budget-paused (spent >= daily limit).
    public var shouldBudgetPause: Bool {
        context.budgetDailyUsd > 0 && context.spentTodayUsd >= context.budgetDailyUsd
    }

    /// ZFC reconciliation: observable state (tmux) overrides recorded state.
    /// If tmux is dead but state says we're active, force-transition to done.
    /// If tmux is alive but state is done, trust the recorded state (no-op).
    public func reconcile(tmuxAlive: Bool, pidAlive: Bool) throws {
        let isActiveState = currentState != .done && currentState != .merged
        if !tmuxAlive && !pidAlive && isActiveState {
            try transition(to: .done, actor: .system, reason: "ZFC reconcile: tmux dead, pid dead")
        }
    }
}
