import Testing
import Foundation
@testable import ShikiCore

@Suite("Spend Tracking — S1b")
struct SpendTrackingTests {

    // MARK: - Mock Provider

    struct MockProvider: AgentProvider {
        let name: String
        let spend: Double

        var currentSessionSpend: Double {
            get async { spend }
        }

        func dispatch(prompt: String, workingDirectory: URL, options: AgentOptions) async throws -> AgentResult {
            AgentResult(output: "", exitCode: 0, tokensUsed: nil, duration: .seconds(0))
        }

        func cancel() async {}
    }

    // MARK: - Tests

    @Test("AgentProvider reports spend through protocol")
    func providerReportsSpend() async {
        let provider = MockProvider(name: "test", spend: 12.50)
        let spend = await provider.currentSessionSpend
        #expect(spend == 12.50)
    }

    @Test("BudgetEnforcer aggregates spend across multiple providers")
    func budgetAggregatesProviders() async {
        let providers: [any AgentProvider] = [
            MockProvider(name: "claude", spend: 8.0),
            MockProvider(name: "openrouter", spend: 4.0),
        ]

        let enforcer = BudgetEnforcer()
        await enforcer.setDailyLimit(company: "acme", limit: 31.0)
        await enforcer.aggregateFromProviders(providers, company: "acme")

        let remaining = await enforcer.remaining(company: "acme")
        #expect(remaining == 19.0)  // 31 - (8 + 4) = 19
    }

    @Test("BudgetEnforcer display string formats correctly")
    func displayStringFormat() async {
        let enforcer = BudgetEnforcer()
        await enforcer.setDailyLimit(company: "acme", limit: 31.0)
        await enforcer.record(company: "acme", amount: 12.0)

        let display = await enforcer.displayString(company: "acme")
        #expect(display == "$12/$31")
    }

    @Test("ClaudeProvider parseSpend extracts cost_usd from JSON")
    func parseSpendFromJSON() {
        let json = #"{"result": "ok", "cost_usd": 0.42}"#
        let spend = ClaudeProvider.parseSpend(from: json)
        #expect(spend == 0.42)
    }

    @Test("ClaudeProvider parseSpend returns nil for non-JSON")
    func parseSpendReturnsNilForNonJSON() {
        let text = "Build complete!"
        let spend = ClaudeProvider.parseSpend(from: text)
        #expect(spend == nil)
    }
}
