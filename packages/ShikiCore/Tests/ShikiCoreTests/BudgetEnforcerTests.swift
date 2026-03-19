import Testing
import Foundation
@testable import ShikiCore

@Suite("BudgetEnforcer")
struct BudgetEnforcerTests {

    @Test("canSpend returns true under limit")
    func canSpendUnderLimit() async {
        let enforcer = BudgetEnforcer()
        await enforcer.setDailyLimit(company: "acme", limit: 100.0)

        #expect(await enforcer.canSpend(company: "acme", amount: 50.0))
        await enforcer.record(company: "acme", amount: 50.0)
        #expect(await enforcer.canSpend(company: "acme", amount: 49.0))
    }

    @Test("canSpend returns false at limit")
    func canSpendAtLimit() async {
        let enforcer = BudgetEnforcer()
        await enforcer.setDailyLimit(company: "acme", limit: 100.0)
        await enforcer.record(company: "acme", amount: 80.0)

        let overBudget = await enforcer.canSpend(company: "acme", amount: 21.0)
        #expect(!overBudget)
        // Exactly at limit should still be allowed
        #expect(await enforcer.canSpend(company: "acme", amount: 20.0))
    }

    @Test("No limit set returns true (permissive default)")
    func noLimitPermissive() async {
        let enforcer = BudgetEnforcer()

        // No limit set for this company — should always allow
        #expect(await enforcer.canSpend(company: "unknown-corp", amount: 999999.0))
    }
}
