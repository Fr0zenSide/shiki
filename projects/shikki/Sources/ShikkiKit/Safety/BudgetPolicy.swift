import Foundation

// MARK: - BudgetPeriod

/// Time period for budget tracking.
public enum BudgetPeriod: String, Codable, Sendable, Hashable {
    case daily
    case weekly
    case monthly
}

// MARK: - BudgetPolicy

/// A cost cap that applies to a user/team within a workspace.
/// Budget inheritance: workspace default -> team override -> user override.
public struct BudgetPolicy: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let userId: String
    public let workspaceId: String?
    public let period: BudgetPeriod
    public let capUsd: Double
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        userId: String,
        workspaceId: String? = nil,
        period: BudgetPeriod = .daily,
        capUsd: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.workspaceId = workspaceId
        self.period = period
        self.capUsd = capUsd
        self.createdAt = createdAt
    }
}

// MARK: - BudgetLedgerEntry

/// A single cost event recorded against a user's budget.
public struct BudgetLedgerEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let userId: String
    public let workspaceId: String?
    public let toolName: String
    public let costUsd: Double
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        userId: String,
        workspaceId: String? = nil,
        toolName: String,
        costUsd: Double,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.workspaceId = workspaceId
        self.toolName = toolName
        self.costUsd = costUsd
        self.timestamp = timestamp
    }
}

// MARK: - BudgetCheckResult

/// Result of checking whether a tool call is within budget.
public enum BudgetCheckResult: Sendable, Equatable {
    case allowed(remainingUsd: Double)
    case blocked(reason: String)
    case noPolicyDefined
}

// MARK: - BudgetSnapshot

/// Current spend state for a user in a period.
public struct BudgetSnapshot: Sendable {
    public let userId: String
    public let period: BudgetPeriod
    public let capUsd: Double
    public let spentUsd: Double
    public let remainingUsd: Double
    public let percentUsed: Double

    public init(userId: String, period: BudgetPeriod, capUsd: Double, spentUsd: Double) {
        self.userId = userId
        self.period = period
        self.capUsd = capUsd
        self.spentUsd = spentUsd
        self.remainingUsd = max(0, capUsd - spentUsd)
        self.percentUsed = capUsd > 0 ? min(100, (spentUsd / capUsd) * 100) : 0
    }
}
