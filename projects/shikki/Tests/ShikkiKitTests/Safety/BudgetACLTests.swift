import Foundation
import Testing
@testable import ShikkiKit

// MARK: - BudgetACLTests

@Suite("BudgetACL — per-user budget enforcement")
struct BudgetACLTests {

    // MARK: - Helpers

    /// Fixed clock where all periods started 1 hour ago.
    private func makeFixedClock() -> FixedBudgetClock {
        let now = Date()
        return FixedBudgetClock(
            now: now,
            periodStarts: [
                .daily: now.addingTimeInterval(-3600),
                .weekly: now.addingTimeInterval(-3600),
                .monthly: now.addingTimeInterval(-3600),
            ]
        )
    }

    private func makeACL() -> BudgetACL {
        BudgetACL(clock: makeFixedClock())
    }

    // MARK: - Policy Management

    @Test("setPolicy stores a policy for a user")
    func setPolicy_storesPolicy() async {
        let acl = makeACL()
        let policy = BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0)
        await acl.setPolicy(policy)

        let effective = await acl.effectivePolicy(userId: "alice", workspaceId: nil, period: .daily)
        #expect(effective != nil)
        #expect(effective?.capUsd == 10.0)
    }

    @Test("setPolicy overwrites existing policy for same period")
    func setPolicy_overwritesSamePeriod() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 20.0))

        let effective = await acl.effectivePolicy(userId: "alice", workspaceId: nil, period: .daily)
        #expect(effective?.capUsd == 20.0)
    }

    @Test("removePolicy deletes policy for a period")
    func removePolicy_removesIt() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.removePolicy(userId: "alice", period: .daily)

        let effective = await acl.effectivePolicy(userId: "alice", workspaceId: nil, period: .daily)
        #expect(effective == nil)
    }

    @Test("allPolicies returns every stored policy")
    func allPolicies_returnsAll() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .weekly, capUsd: 50.0))

        let all = await acl.allPolicies()
        #expect(all.count == 2)
    }

    // MARK: - Policy Inheritance

    @Test("user-workspace policy takes precedence over user global")
    func policyInheritance_userWorkspaceOverGlobal() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.setPolicy(BudgetPolicy(userId: "alice", workspaceId: "ws1", period: .daily, capUsd: 5.0))

        let effective = await acl.effectivePolicy(userId: "alice", workspaceId: "ws1", period: .daily)
        #expect(effective?.capUsd == 5.0)
    }

    @Test("user global policy used when no workspace-specific exists")
    func policyInheritance_fallsBackToUserGlobal() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))

        let effective = await acl.effectivePolicy(userId: "alice", workspaceId: "ws1", period: .daily)
        #expect(effective?.capUsd == 10.0)
    }

    @Test("workspace default policy used when no user-specific exists")
    func policyInheritance_fallsBackToWorkspaceDefault() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "*", workspaceId: "ws1", period: .daily, capUsd: 20.0))

        let effective = await acl.effectivePolicy(userId: "bob", workspaceId: "ws1", period: .daily)
        #expect(effective?.capUsd == 20.0)
    }

    @Test("global default (wildcard user, no workspace) used as last resort")
    func policyInheritance_fallsBackToGlobalDefault() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "*", period: .daily, capUsd: 100.0))

        let effective = await acl.effectivePolicy(userId: "unknown", workspaceId: "ws1", period: .daily)
        #expect(effective?.capUsd == 100.0)
    }

    @Test("no policy returns nil")
    func policyInheritance_nilWhenNoPolicyExists() async {
        let acl = makeACL()
        let effective = await acl.effectivePolicy(userId: "ghost", workspaceId: nil, period: .daily)
        #expect(effective == nil)
    }

    // MARK: - Budget Check — Allowed

    @Test("check allows spending within budget")
    func check_allowsWithinBudget() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))

        let result = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 3.0)
        if case .allowed(let remaining) = result {
            #expect(remaining == 7.0)
        } else {
            Issue.record("Expected .allowed, got \(result)")
        }
    }

    @Test("check returns noPolicyDefined when no policy exists")
    func check_noPolicyDefined() async {
        let acl = makeACL()
        let result = await acl.check(userId: "ghost", toolName: "search", estimatedCostUsd: 1.0)
        #expect(result == .noPolicyDefined)
    }

    // MARK: - Budget Check — Blocked

    @Test("check blocks when spending exceeds budget")
    func check_blocksOverBudget() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 8.0)

        let result = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 5.0)
        if case .blocked(let reason) = result {
            #expect(reason.contains("exceeded"))
        } else {
            Issue.record("Expected .blocked, got \(result)")
        }
    }

    @Test("check blocks when single request exceeds full budget")
    func check_blocksWhenSingleRequestExceedsCap() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 5.0))

        let result = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 10.0)
        if case .blocked = result {
            // Expected
        } else {
            Issue.record("Expected .blocked, got \(result)")
        }
    }

    @Test("check blocks on tightest constraint across periods")
    func check_blocksTightestPeriod() async {
        let acl = makeACL()
        // Monthly is generous, daily is tight
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .monthly, capUsd: 100.0))
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 5.0))
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 4.0)

        let result = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 3.0)
        if case .blocked(let reason) = result {
            #expect(reason.contains("daily"))
        } else {
            Issue.record("Expected .blocked on daily constraint, got \(result)")
        }
    }

    // MARK: - Budget Reset

    @Test("clearLedger resets all spend history")
    func clearLedger_resetsAllSpend() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 8.0)
        await acl.clearLedger()

        let spent = await acl.spentInPeriod(userId: "alice", period: .daily)
        #expect(spent == 0.0)

        let result = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 5.0)
        if case .allowed = result {
            // Expected — budget is fresh
        } else {
            Issue.record("Expected .allowed after clear, got \(result)")
        }
    }

    // MARK: - Ledger & Spend Tracking

    @Test("recordSpend accumulates correctly")
    func recordSpend_accumulates() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 100.0))
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 3.0)
        await acl.recordSpend(userId: "alice", toolName: "upsert", costUsd: 7.0)

        let spent = await acl.spentInPeriod(userId: "alice", period: .daily)
        #expect(spent == 10.0)
    }

    @Test("allEntries returns every ledger entry")
    func allEntries_returnsAll() async {
        let acl = makeACL()
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 1.0)
        await acl.recordSpend(userId: "bob", toolName: "upsert", costUsd: 2.0)

        let entries = await acl.allEntries()
        #expect(entries.count == 2)
    }

    @Test("spend is workspace-scoped when workspace provided")
    func spentInPeriod_workspaceScoped() async {
        let acl = makeACL()
        await acl.recordSpend(userId: "alice", workspaceId: "ws1", toolName: "search", costUsd: 5.0)
        await acl.recordSpend(userId: "alice", workspaceId: "ws2", toolName: "search", costUsd: 3.0)

        let ws1Spent = await acl.spentInPeriod(userId: "alice", workspaceId: "ws1", period: .daily)
        let ws2Spent = await acl.spentInPeriod(userId: "alice", workspaceId: "ws2", period: .daily)
        let globalSpent = await acl.spentInPeriod(userId: "alice", period: .daily)

        #expect(ws1Spent == 5.0)
        #expect(ws2Spent == 3.0)
        #expect(globalSpent == 8.0)
    }

    // MARK: - Multiple Users / Scopes

    @Test("different users have independent budgets")
    func multipleUsers_independentBudgets() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 10.0))

        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 9.0)

        let aliceResult = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 5.0)
        let bobResult = await acl.check(userId: "bob", toolName: "search", estimatedCostUsd: 5.0)

        if case .blocked = aliceResult {
            // Expected
        } else {
            Issue.record("Expected alice blocked, got \(aliceResult)")
        }

        if case .allowed = bobResult {
            // Expected — bob hasn't spent anything
        } else {
            Issue.record("Expected bob allowed, got \(bobResult)")
        }
    }

    @Test("multiple periods can coexist for same user")
    func multiplePeriods_coexist() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .weekly, capUsd: 50.0))
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .monthly, capUsd: 200.0))

        let all = await acl.allPolicies()
        let alicePolicies = all.filter { $0.userId == "alice" }
        #expect(alicePolicies.count == 3)
    }

    // MARK: - Snapshot

    @Test("snapshot returns correct budget state")
    func snapshot_returnsCorrectState() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 3.5)

        let snap = await acl.snapshot(userId: "alice", period: .daily)
        #expect(snap != nil)
        #expect(snap?.capUsd == 10.0)
        #expect(snap?.spentUsd == 3.5)
        #expect(snap?.remainingUsd == 6.5)
        #expect(snap?.percentUsed == 35.0)
    }

    @Test("snapshot returns nil when no policy exists")
    func snapshot_returnsNilWithoutPolicy() async {
        let acl = makeACL()
        let snap = await acl.snapshot(userId: "ghost", period: .daily)
        #expect(snap == nil)
    }

    // MARK: - Budget Exceeded Callback

    @Test("onBudgetExceeded callback fires when blocked")
    func callback_firesWhenBlocked() async {
        let acl = makeACL()
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 5.0))
        await acl.recordSpend(userId: "alice", toolName: "search", costUsd: 4.0)

        nonisolated(unsafe) var callbackFired = false
        nonisolated(unsafe) var callbackUserId: String?
        await acl.setOnBudgetExceeded { userId, _, _ in
            callbackFired = true
            callbackUserId = userId
        }

        _ = await acl.check(userId: "alice", toolName: "search", estimatedCostUsd: 3.0)
        #expect(callbackFired)
        #expect(callbackUserId == "alice")
    }

    // MARK: - FixedBudgetClock

    @Test("FixedBudgetClock returns fixed values")
    func fixedClock_returnsFixedValues() {
        let now = Date()
        let dailyStart = now.addingTimeInterval(-3600)
        let clock = FixedBudgetClock(now: now, periodStarts: [.daily: dailyStart])

        #expect(clock.now() == now)
        #expect(clock.periodStart(for: .daily) == dailyStart)
    }

    @Test("FixedBudgetClock defaults period start to 24h before now")
    func fixedClock_defaultPeriodStart() {
        let now = Date()
        let clock = FixedBudgetClock(now: now)
        let start = clock.periodStart(for: .weekly)
        let diff = now.timeIntervalSince(start)
        #expect(abs(diff - 86400) < 1.0)
    }

    // MARK: - BudgetPolicy Model

    @Test("BudgetPolicy defaults are correct")
    func budgetPolicy_defaults() {
        let policy = BudgetPolicy(userId: "test", capUsd: 50.0)
        #expect(policy.userId == "test")
        #expect(policy.period == .daily)
        #expect(policy.capUsd == 50.0)
        #expect(policy.workspaceId == nil)
    }

    // MARK: - BudgetSnapshot Model

    @Test("BudgetSnapshot calculates remainingUsd and percentUsed")
    func budgetSnapshot_calculations() {
        let snap = BudgetSnapshot(userId: "alice", period: .daily, capUsd: 10.0, spentUsd: 7.5)
        #expect(snap.remainingUsd == 2.5)
        #expect(snap.percentUsed == 75.0)
    }

    @Test("BudgetSnapshot clamps remaining to zero when overspent")
    func budgetSnapshot_clampsToZero() {
        let snap = BudgetSnapshot(userId: "alice", period: .daily, capUsd: 5.0, spentUsd: 8.0)
        #expect(snap.remainingUsd == 0.0)
        #expect(snap.percentUsed == 100.0) // capped at 100
    }

    @Test("BudgetSnapshot handles zero cap without division error")
    func budgetSnapshot_zeroCap() {
        let snap = BudgetSnapshot(userId: "alice", period: .daily, capUsd: 0.0, spentUsd: 0.0)
        #expect(snap.percentUsed == 0.0)
        #expect(snap.remainingUsd == 0.0)
    }
}
