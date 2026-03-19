import Testing
@testable import ShikiCore

@Suite("BudgetEnforcer Concurrency Stress")
struct BudgetEnforcerStressTests {

    @Test("100 concurrent trySpend calls never exceed budget")
    func concurrentSpendNeverExceedsBudget() async throws {
        let enforcer = BudgetEnforcer()
        await enforcer.setDailyLimit(company: "stress-co", limit: 10.0)

        // 100 concurrent attempts to spend $1 each
        // Only 10 should succeed (budget is $10)
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await enforcer.trySpend(company: "stress-co", amount: 1.0)
                }
            }
            var count = 0
            for await success in group {
                if success { count += 1 }
            }
            return count
        }

        #expect(successes == 10, "Expected exactly 10 successes for $10 budget with $1 spends, got \(successes)")

        // Verify remaining is 0
        let remaining = await enforcer.remaining(company: "stress-co")
        #expect(remaining == 0.0)
    }

    @Test("Concurrent spend on different companies don't interfere")
    func crossCompanyIsolation() async throws {
        let enforcer = BudgetEnforcer()
        await enforcer.setDailyLimit(company: "alpha", limit: 5.0)
        await enforcer.setDailyLimit(company: "beta", limit: 5.0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { _ = await enforcer.trySpend(company: "alpha", amount: 1.0) }
                group.addTask { _ = await enforcer.trySpend(company: "beta", amount: 1.0) }
            }
        }

        let alphaRemaining = await enforcer.remaining(company: "alpha")
        let betaRemaining = await enforcer.remaining(company: "beta")

        #expect(alphaRemaining! >= 0.0, "Alpha budget went negative")
        #expect(betaRemaining! >= 0.0, "Beta budget went negative")
    }
}
