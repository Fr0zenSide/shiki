import Foundation

/// Manages N FeatureLifecycles across projects.
public actor CompanyManager {
    private var lifecycles: [String: FeatureLifecycle] = [:]
    private let persister: (any EventPersisting)?
    private let budgetEnforcer: BudgetEnforcer

    public init(persister: (any EventPersisting)? = nil, budgetEnforcer: BudgetEnforcer = BudgetEnforcer()) {
        self.persister = persister
        self.budgetEnforcer = budgetEnforcer
    }

    /// Register a new feature lifecycle for a project.
    @discardableResult
    public func register(featureId: String) -> FeatureLifecycle {
        let lifecycle = FeatureLifecycle(featureId: featureId, persister: persister)
        lifecycles[featureId] = lifecycle
        return lifecycle
    }

    /// Get all registered lifecycles.
    public func allLifecycles() -> [String: FeatureLifecycle] {
        lifecycles
    }

    /// Get lifecycle by feature ID.
    public func lifecycle(for featureId: String) -> FeatureLifecycle? {
        lifecycles[featureId]
    }

    /// Remove completed lifecycle.
    public func remove(featureId: String) {
        lifecycles.removeValue(forKey: featureId)
    }

    /// Check if a company can spend more today.
    public func canSpend(company: String, amount: Double) async -> Bool {
        await budgetEnforcer.canSpend(company: company, amount: amount)
    }

    /// Record spending.
    public func recordSpend(company: String, amount: Double) async {
        await budgetEnforcer.record(company: company, amount: amount)
    }

    /// Atomically check and record spend. Returns true if budget allows.
    public func trySpend(company: String, amount: Double) async -> Bool {
        await budgetEnforcer.trySpend(company: company, amount: amount)
    }

    /// Count active lifecycles.
    public var activeCount: Int { lifecycles.count }
}
