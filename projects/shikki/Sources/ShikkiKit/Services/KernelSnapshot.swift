import Foundation

// MARK: - HealthStatus

/// Backend health state as seen by the kernel.
public enum HealthStatus: Sendable, Equatable {
    case healthy
    case degraded(reason: String)
    case unreachable
}

// MARK: - KernelSnapshot

/// Batched backend data fetched once per kernel tick.
/// All services in a coalesced tick share the same snapshot,
/// eliminating redundant API calls (BR-02).
public struct KernelSnapshot: Sendable {
    public let health: HealthStatus
    public let companies: [Company]
    public let dispatchQueue: [DispatcherTask]
    public let pendingDecisions: [Decision]
    public let sessions: [SessionInfo]
    public let fetchedAt: Date

    public init(
        health: HealthStatus,
        companies: [Company] = [],
        dispatchQueue: [DispatcherTask] = [],
        pendingDecisions: [Decision] = [],
        sessions: [SessionInfo] = [],
        fetchedAt: Date = Date()
    ) {
        self.health = health
        self.companies = companies
        self.dispatchQueue = dispatchQueue
        self.pendingDecisions = pendingDecisions
        self.sessions = sessions
        self.fetchedAt = fetchedAt
    }

    /// Empty snapshot for when the backend is unreachable.
    public static let unreachable = KernelSnapshot(
        health: .unreachable,
        fetchedAt: Date()
    )
}

// MARK: - SessionInfo

/// Lightweight session descriptor used in KernelSnapshot.
public struct SessionInfo: Sendable {
    public let slug: String
    public let companySlug: String
    public let isRunning: Bool

    public init(slug: String, companySlug: String, isRunning: Bool) {
        self.slug = slug
        self.companySlug = companySlug
        self.isRunning = isRunning
    }
}
