import Foundation

// MARK: - AgentMessages

/// Factory for inter-agent messaging events.
/// Uses the EventBus with typed message events — no separate SQLite mail DB.
public enum AgentMessages {

    /// Agent asks a question to another agent.
    public static func question(fromSession: String, toSession: String, question: String) -> ShikiEvent {
        ShikiEvent(
            source: .agent(id: fromSession, name: nil),
            type: .custom("agentQuestion"),
            scope: .session(id: toSession),
            payload: [
                "fromSession": .string(fromSession),
                "toSession": .string(toSession),
                "question": .string(question),
            ]
        )
    }

    /// Agent reports a result.
    public static func result(sessionId: String, summary: String) -> ShikiEvent {
        ShikiEvent(
            source: .agent(id: sessionId, name: nil),
            type: .custom("agentResult"),
            scope: .session(id: sessionId),
            payload: ["summary": .string(summary)]
        )
    }

    /// Agent hands off to the next persona in the chain.
    public static func handoff(fromSession: String, toPersona: AgentPersona, context: String) -> ShikiEvent {
        ShikiEvent(
            source: .agent(id: fromSession, name: nil),
            type: .custom("agentHandoff"),
            scope: .session(id: fromSession),
            payload: [
                "toPersona": .string(toPersona.rawValue),
                "context": .string(context),
            ]
        )
    }

    /// Broadcast message to all agents.
    public static func broadcast(message: String) -> ShikiEvent {
        ShikiEvent(
            source: .orchestrator,
            type: .custom("agentBroadcast"),
            scope: .global,
            payload: ["message": .string(message)]
        )
    }

    /// Decision gate — agent needs human approval before proceeding.
    public static func decisionGate(sessionId: String, question: String, tier: Int) -> ShikiEvent {
        ShikiEvent(
            source: .agent(id: sessionId, name: nil),
            type: .custom("decisionGate"),
            scope: .session(id: sessionId),
            payload: [
                "question": .string(question),
                "tier": .int(tier),
            ]
        )
    }
}
