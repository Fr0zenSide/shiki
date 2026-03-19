import Foundation

/// Per-company daily budget caps.
/// Thread-safe via actor isolation.
public actor BudgetEnforcer {

    private struct CompanyBudget {
        var dailyLimit: Double
        var spentToday: Double
        var lastResetDate: String  // ISO8601 date component
    }

    private var budgets: [String: CompanyBudget] = [:]

    public init() {}

    /// Set daily budget for a company.
    public func setDailyLimit(company: String, limit: Double) {
        if budgets[company] != nil {
            budgets[company]!.dailyLimit = limit
        } else {
            let today = Self.todayString()
            budgets[company] = CompanyBudget(dailyLimit: limit, spentToday: 0, lastResetDate: today)
        }
    }

    /// Check if company can spend amount.
    public func canSpend(company: String, amount: Double) -> Bool {
        resetIfNewDay(company: company)
        guard let budget = budgets[company] else { return true } // no limit set
        return budget.spentToday + amount <= budget.dailyLimit
    }

    /// Record spending.
    public func record(company: String, amount: Double) {
        resetIfNewDay(company: company)
        budgets[company]?.spentToday += amount
    }

    /// Atomically check and record spend. Returns true if budget allows.
    public func trySpend(company: String, amount: Double) -> Bool {
        resetIfNewDay(company: company)
        guard let budget = budgets[company] else { return true }
        if budget.spentToday + amount <= budget.dailyLimit {
            budgets[company]?.spentToday += amount
            return true
        }
        return false
    }

    /// Get remaining budget.
    public func remaining(company: String) -> Double? {
        guard let budget = budgets[company] else { return nil }
        return budget.dailyLimit - budget.spentToday
    }

    private func resetIfNewDay(company: String) {
        let today = Self.todayString()
        if budgets[company]?.lastResetDate != today {
            budgets[company]?.spentToday = 0
            budgets[company]?.lastResetDate = today
        }
    }

    private static func todayString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: Date())
    }
}
