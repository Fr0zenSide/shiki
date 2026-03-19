import Foundation

// MARK: - DashboardSession

/// A session as viewed from the dashboard.
public struct DashboardSession: Codable, Sendable {
    public let windowName: String
    public let state: SessionState
    public let attentionZone: AttentionZone
    public let companySlug: String?

    public init(windowName: String, state: SessionState, attentionZone: AttentionZone, companySlug: String?) {
        self.windowName = windowName
        self.state = state
        self.attentionZone = attentionZone
        self.companySlug = companySlug
    }
}

// MARK: - DashboardSnapshot

/// Point-in-time snapshot of all sessions for the dashboard TUI.
public struct DashboardSnapshot: Codable, Sendable {
    public let sessions: [DashboardSession]
    public let timestamp: Date

    public init(sessions: [DashboardSession], timestamp: Date = Date()) {
        self.sessions = sessions
        self.timestamp = timestamp
    }

    /// Build a snapshot from the session registry.
    public static func from(registry: SessionRegistry) async -> DashboardSnapshot {
        let sorted = await registry.sessionsByAttention()
        let sessions = sorted.map { reg in
            DashboardSession(
                windowName: reg.windowName,
                state: reg.state,
                attentionZone: reg.attentionZone,
                companySlug: reg.context?.companySlug
            )
        }
        return DashboardSnapshot(sessions: sessions)
    }
}
