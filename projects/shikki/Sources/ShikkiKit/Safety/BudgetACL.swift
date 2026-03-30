import Foundation
import Logging

// MARK: - BudgetACL

/// Per-user budget enforcement with workspace isolation.
///
/// Every MCP tool call passes through budget check:
/// ```
/// User -> MCP Tool -> Budget Check -> Router -> Execute
///                        |
///                    Over budget? -> BLOCKED + notify admin
/// ```
///
/// Budget inheritance: workspace default -> team override -> user override.
public actor BudgetACL {
    private var policies: [String: [BudgetPeriod: BudgetPolicy]] = [:]
    private var ledger: [BudgetLedgerEntry] = []
    private let logger: Logger
    private let clock: BudgetClock

    /// Callback invoked when a user exceeds their budget.
    public var onBudgetExceeded: (@Sendable (String, BudgetPeriod, Double) async -> Void)?

    /// Set the budget-exceeded callback (actor-isolated setter for external callers).
    public func setOnBudgetExceeded(_ handler: (@Sendable (String, BudgetPeriod, Double) async -> Void)?) {
        onBudgetExceeded = handler
    }

    public init(
        clock: BudgetClock = SystemBudgetClock(),
        logger: Logger = Logger(label: "shikki.budget-acl")
    ) {
        self.clock = clock
        self.logger = logger
    }

    // MARK: - Policy Management

    /// Set a budget policy for a user. Overwrites existing policy for that period.
    public func setPolicy(_ policy: BudgetPolicy) {
        let key = policyKey(userId: policy.userId, workspaceId: policy.workspaceId)
        policies[key, default: [:]][policy.period] = policy
    }

    /// Remove a budget policy for a user/period.
    public func removePolicy(userId: String, workspaceId: String? = nil, period: BudgetPeriod) {
        let key = policyKey(userId: userId, workspaceId: workspaceId)
        policies[key]?[period] = nil
    }

    /// Get the effective policy for a user, applying inheritance.
    /// User-specific > workspace default.
    public func effectivePolicy(userId: String, workspaceId: String?, period: BudgetPeriod) -> BudgetPolicy? {
        // 1. User-specific for this workspace
        if let wsId = workspaceId {
            let userWsKey = policyKey(userId: userId, workspaceId: wsId)
            if let policy = policies[userWsKey]?[period] {
                return policy
            }
        }

        // 2. User global (no workspace)
        let userKey = policyKey(userId: userId, workspaceId: nil)
        if let policy = policies[userKey]?[period] {
            return policy
        }

        // 3. Workspace default (userId = "*")
        if let wsId = workspaceId {
            let wsDefaultKey = policyKey(userId: "*", workspaceId: wsId)
            if let policy = policies[wsDefaultKey]?[period] {
                return policy
            }
        }

        // 4. Global default (userId = "*", no workspace)
        let globalKey = policyKey(userId: "*", workspaceId: nil)
        return policies[globalKey]?[period]
    }

    /// Get all policies.
    public func allPolicies() -> [BudgetPolicy] {
        policies.values.flatMap { $0.values }
    }

    // MARK: - Budget Check

    /// Check whether a tool call is within budget for a user.
    /// Returns `.allowed` with remaining budget, `.blocked` if over, or `.noPolicyDefined`.
    public func check(
        userId: String,
        workspaceId: String? = nil,
        toolName: String,
        estimatedCostUsd: Double
    ) async -> BudgetCheckResult {
        // Check all periods, block on the tightest constraint
        for period in BudgetPeriod.allCases {
            guard let policy = effectivePolicy(userId: userId, workspaceId: workspaceId, period: period) else {
                continue
            }

            let spent = spentInPeriod(userId: userId, workspaceId: workspaceId, period: period)
            let remaining = policy.capUsd - spent

            if estimatedCostUsd > remaining {
                let reason = "\(period.rawValue) budget exceeded: spent $\(String(format: "%.2f", spent))/$\(String(format: "%.2f", policy.capUsd)), requested $\(String(format: "%.2f", estimatedCostUsd))"
                logger.warning("Budget blocked: \(userId) — \(reason)")
                await onBudgetExceeded?(userId, period, spent)
                return .blocked(reason: reason)
            }
        }

        // If at least one policy exists, return allowed with the tightest remaining
        let tightestRemaining = BudgetPeriod.allCases.compactMap { period -> Double? in
            guard let policy = effectivePolicy(userId: userId, workspaceId: workspaceId, period: period) else {
                return nil
            }
            let spent = spentInPeriod(userId: userId, workspaceId: workspaceId, period: period)
            return policy.capUsd - spent - estimatedCostUsd
        }.min()

        if let remaining = tightestRemaining {
            return .allowed(remainingUsd: remaining)
        }

        return .noPolicyDefined
    }

    // MARK: - Ledger

    /// Record a cost event against a user's budget.
    public func recordSpend(
        userId: String,
        workspaceId: String? = nil,
        toolName: String,
        costUsd: Double
    ) {
        let entry = BudgetLedgerEntry(
            userId: userId,
            workspaceId: workspaceId,
            toolName: toolName,
            costUsd: costUsd
        )
        ledger.append(entry)
    }

    /// Get a snapshot of the user's budget status for a period.
    public func snapshot(userId: String, workspaceId: String? = nil, period: BudgetPeriod) -> BudgetSnapshot? {
        guard let policy = effectivePolicy(userId: userId, workspaceId: workspaceId, period: period) else {
            return nil
        }
        let spent = spentInPeriod(userId: userId, workspaceId: workspaceId, period: period)
        return BudgetSnapshot(userId: userId, period: period, capUsd: policy.capUsd, spentUsd: spent)
    }

    /// Total spend for a user in the current period window.
    public func spentInPeriod(userId: String, workspaceId: String? = nil, period: BudgetPeriod) -> Double {
        let windowStart = clock.periodStart(for: period)
        return ledger
            .filter { entry in
                entry.userId == userId
                    && entry.timestamp >= windowStart
                    && (workspaceId == nil || entry.workspaceId == workspaceId)
            }
            .reduce(0) { $0 + $1.costUsd }
    }

    /// All ledger entries (for testing/debugging).
    public func allEntries() -> [BudgetLedgerEntry] {
        ledger
    }

    /// Clear all ledger entries (for period reset).
    public func clearLedger() {
        ledger.removeAll()
    }

    // MARK: - Private

    private func policyKey(userId: String, workspaceId: String?) -> String {
        if let wsId = workspaceId {
            return "\(userId)@\(wsId)"
        }
        return userId
    }
}

// MARK: - BudgetPeriod + CaseIterable

extension BudgetPeriod: CaseIterable {
    public static var allCases: [BudgetPeriod] { [.daily, .weekly, .monthly] }
}

// MARK: - BudgetClock

/// Abstraction over time for testability.
public protocol BudgetClock: Sendable {
    func now() -> Date
    func periodStart(for period: BudgetPeriod) -> Date
}

/// System clock implementation.
public struct SystemBudgetClock: BudgetClock, Sendable {
    public init() {}

    public func now() -> Date { Date() }

    public func periodStart(for period: BudgetPeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return calendar.date(from: components) ?? now
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: components) ?? now
        }
    }
}

/// Fixed clock for tests.
public struct FixedBudgetClock: BudgetClock, Sendable {
    public let fixedNow: Date
    public let fixedPeriodStarts: [BudgetPeriod: Date]

    public init(now: Date, periodStarts: [BudgetPeriod: Date] = [:]) {
        self.fixedNow = now
        self.fixedPeriodStarts = periodStarts
    }

    public func now() -> Date { fixedNow }

    public func periodStart(for period: BudgetPeriod) -> Date {
        fixedPeriodStarts[period] ?? fixedNow.addingTimeInterval(-86400)
    }
}
