import Foundation

// MARK: - FlameEmotion

/// The emotional state of the Blue Flame mascot.
/// Each emotion maps to a distinct visual behavior and color palette.
public enum FlameEmotion: String, Sendable, Codable, CaseIterable {
    /// Resting state — slow, gentle pulse. Cool blue tones.
    case calm

    /// Active work in progress — steady burn. Warm blue with white core.
    case focused

    /// Something great happened — bright, expansive. Electric blue + cyan sparks.
    case excited

    /// Error or failure detected — rapid flicker. Blue-red shift.
    case alarmed

    /// Ship completed, all gates passed — firework burst. Full spectrum blue + gold.
    case celebrating
}

// MARK: - FlameSize

/// Rendering size for the flame.
/// Mini fits in a status bar, medium in a dashboard widget, large for splash screens.
public enum FlameSize: String, Sendable, Codable, CaseIterable {
    /// 1-2 characters wide, suitable for tmux status bar or inline text.
    case mini

    /// ~12 lines tall, suitable for dashboard sidebar.
    case medium

    /// ~20 lines tall, suitable for splash screen or celebration.
    case large
}

// MARK: - FlameEmotionResolver

/// Maps ShikkiEvent types to flame emotions.
/// The resolver uses a simple priority system: more significant events
/// override less significant ones within a time window.
public enum FlameEmotionResolver: Sendable {

    /// Resolve the flame emotion from a single event type.
    public static func resolve(_ eventType: EventType) -> FlameEmotion {
        switch eventType {
        // Calm — routine, low-significance events
        case .heartbeat, .contextCompaction:
            return .calm

        // Focused — active work happening
        case .sessionStart, .sessionTransition:
            return .focused
        case .codeChange:
            return .focused
        case .testRun:
            return .focused
        case .buildResult:
            return .focused
        case .companyDispatched, .companyRelaunched:
            return .focused
        case .prCacheBuilt, .prRiskAssessed:
            return .focused
        case .decisionPending:
            return .focused
        case .codeGenStarted, .codeGenSpecParsed, .codeGenContractVerified,
             .codeGenPlanCreated, .codeGenAgentDispatched, .codeGenAgentCompleted,
             .codeGenMergeStarted, .codeGenMergeCompleted,
             .codeGenFixStarted, .codeGenFixCompleted:
            return .focused

        // Excited — positive milestones
        case .prVerdictSet, .prFixCompleted:
            return .excited
        case .decisionAnswered, .decisionUnblocked:
            return .excited
        case .shipGatePassed:
            return .excited
        case .notificationActioned:
            return .excited
        case .codeGenPipelineCompleted:
            return .excited

        // Alarmed — errors and failures
        case .budgetExhausted, .companyStale:
            return .alarmed
        case .shipGateFailed, .shipAborted:
            return .alarmed
        case .codeGenPipelineFailed:
            return .alarmed

        // Celebrating — major completions
        case .shipStarted:
            return .excited
        case .shipGateStarted:
            return .focused
        case .shipCompleted:
            return .celebrating

        // Neutral
        case .sessionEnd:
            return .calm
        case .notificationSent:
            return .calm
        case .prFixSpawned:
            return .focused

        // Custom — default to calm
        case .custom:
            return .calm
        }
    }

    /// Resolve from multiple recent events, picking the highest-priority emotion.
    /// Priority: celebrating > alarmed > excited > focused > calm.
    public static func resolve(from events: [EventType]) -> FlameEmotion {
        guard !events.isEmpty else { return .calm }
        return events
            .map { resolve($0) }
            .max(by: { priority($0) < priority($1) }) ?? .calm
    }

    /// Priority ranking for emotion override logic.
    public static func priority(_ emotion: FlameEmotion) -> Int {
        switch emotion {
        case .calm: return 0
        case .focused: return 1
        case .excited: return 2
        case .alarmed: return 3
        case .celebrating: return 4
        }
    }
}
