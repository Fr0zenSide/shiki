import Foundation

// MARK: - WatchdogAction

/// The escalation action the watchdog recommends.
public enum WatchdogAction: String, Sendable, Equatable {
    case none       // No action needed
    case warn       // Log a warning
    case nudge      // Send a notification
    case aiTriage   // Dispatch investigate agent to check on the session
    case terminate  // Kill the session
}

// MARK: - WatchdogConfig

/// Configurable thresholds for the 4-level progressive watchdog.
public struct WatchdogConfig: Sendable {
    public let warnSeconds: TimeInterval
    public let nudgeSeconds: TimeInterval
    public let triageSeconds: TimeInterval
    public let terminateSeconds: TimeInterval
    public let contextPressureThreshold: Double // % at which idle is treated more urgently

    public init(
        warnSeconds: TimeInterval = 120,
        nudgeSeconds: TimeInterval = 300,
        triageSeconds: TimeInterval = 600,
        terminateSeconds: TimeInterval = 900,
        contextPressureThreshold: Double = 80
    ) {
        self.warnSeconds = warnSeconds
        self.nudgeSeconds = nudgeSeconds
        self.triageSeconds = triageSeconds
        self.terminateSeconds = terminateSeconds
        self.contextPressureThreshold = contextPressureThreshold
    }

    public static let `default` = WatchdogConfig()
}

// MARK: - WatchdogFailureMode

/// Named failure modes for agent prompts (Overstory pattern).
/// Injected into system prompts so agents self-identify when they're drifting.
public enum WatchdogFailureMode: String, Sendable, CaseIterable {
    case hierarchyBypass   // Agent ignores decision tiers, makes choices above its authority
    case specWriting       // Agent rewrites the spec instead of implementing it
    case prematureMerge    // Agent creates PR before verification passes
    case scopeExplosion    // Agent starts working on tasks outside its assignment

    public var description: String {
        switch self {
        case .hierarchyBypass: "HIERARCHY_BYPASS — making decisions above your authority level"
        case .specWriting: "SPEC_WRITING — rewriting the spec instead of implementing it"
        case .prematureMerge: "PREMATURE_MERGE — creating PR before verification passes"
        case .scopeExplosion: "SCOPE_EXPLOSION — working on tasks outside your assignment"
        }
    }
}

// MARK: - Watchdog

/// Progressive watchdog that evaluates session health and recommends actions.
/// 4 levels: warn → nudge → AI triage → terminate.
/// Decision-gate aware: skips escalation for intentionally paused sessions.
public struct Watchdog: Sendable {
    public let config: WatchdogConfig

    public init(config: WatchdogConfig = .default) {
        self.config = config
    }

    /// Evaluate a session's health and return the recommended action.
    /// - Parameters:
    ///   - idleSeconds: How long the session has been idle
    ///   - state: Current session state (for decision-gate awareness)
    ///   - contextPct: Current context window usage percentage (0-100)
    public func evaluate(
        idleSeconds: TimeInterval,
        state: SessionState,
        contextPct: Double
    ) -> WatchdogAction {
        // Decision-gate awareness: skip escalation for intentionally paused states
        let pausedStates: Set<SessionState> = [.awaitingApproval, .budgetPaused, .done, .merged]
        guard !pausedStates.contains(state) else { return .none }

        // Context pressure: lower thresholds when context is high
        let effectiveIdle: TimeInterval
        if contextPct >= config.contextPressureThreshold {
            effectiveIdle = idleSeconds * 2 // Double the perceived idle time
        } else {
            effectiveIdle = idleSeconds
        }

        // Progressive escalation
        if effectiveIdle >= config.terminateSeconds {
            return .terminate
        } else if effectiveIdle >= config.triageSeconds {
            return .aiTriage
        } else if effectiveIdle >= config.nudgeSeconds {
            return .nudge
        } else if effectiveIdle >= config.warnSeconds {
            return .warn
        }

        return .none
    }
}
