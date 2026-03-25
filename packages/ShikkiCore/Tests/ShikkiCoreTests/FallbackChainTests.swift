import Testing
import Foundation
@testable import ShikkiCore

// MARK: - Mock Provider for FallbackChain tests

private actor MockProvider: AgentProvider {
    nonisolated let name: String
    private let shouldFail: Bool
    private let mockOutput: String
    private let mockSpend: Double
    private(set) var dispatchCount = 0
    private(set) var cancelCount = 0

    var currentSessionSpend: Double { mockSpend }

    init(name: String, shouldFail: Bool = false, output: String = "ok", spend: Double = 0) {
        self.name = name
        self.shouldFail = shouldFail
        self.mockOutput = output
        self.mockSpend = spend
    }

    func dispatch(prompt: String, workingDirectory: URL, options: AgentOptions) async throws -> AgentResult {
        dispatchCount += 1
        if shouldFail {
            throw AgentProviderError.unavailable(provider: name)
        }
        return AgentResult(output: mockOutput, exitCode: 0, tokensUsed: 100, duration: .seconds(1))
    }

    func cancel() async {
        cancelCount += 1
    }
}

@Suite("FallbackChain")
struct FallbackChainTests {

    @Test("First provider succeeds — no fallback needed")
    func firstSucceeds() async throws {
        let primary = MockProvider(name: "primary", output: "primary-result")
        let secondary = MockProvider(name: "secondary", output: "secondary-result")
        let chain = FallbackChain(providers: [primary, secondary])

        let result = try await chain.dispatch(
            prompt: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            options: AgentOptions()
        )

        #expect(result.output == "primary-result")
        let primaryCount = await primary.dispatchCount
        let secondaryCount = await secondary.dispatchCount
        #expect(primaryCount == 1)
        #expect(secondaryCount == 0)
    }

    @Test("First fails — second provider is tried")
    func fallbackToSecond() async throws {
        let primary = MockProvider(name: "primary", shouldFail: true)
        let secondary = MockProvider(name: "secondary", output: "fallback-result")
        let chain = FallbackChain(providers: [primary, secondary])

        let result = try await chain.dispatch(
            prompt: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            options: AgentOptions()
        )

        #expect(result.output == "fallback-result")
    }

    @Test("All providers fail — throws last error")
    func allFail() async throws {
        let a = MockProvider(name: "a", shouldFail: true)
        let b = MockProvider(name: "b", shouldFail: true)
        let chain = FallbackChain(providers: [a, b])

        await #expect(throws: AgentProviderError.unavailable(provider: "b")) {
            try await chain.dispatch(
                prompt: "test",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                options: AgentOptions()
            )
        }
    }

    @Test("Cancel propagates to all providers")
    func cancelPropagation() async throws {
        let a = MockProvider(name: "a")
        let b = MockProvider(name: "b")
        let chain = FallbackChain(providers: [a, b])

        await chain.cancel()

        let aCancels = await a.cancelCount
        let bCancels = await b.cancelCount
        #expect(aCancels == 1)
        #expect(bCancels == 1)
    }

    @Test("Spend sums across all providers")
    func spendSummation() async throws {
        let a = MockProvider(name: "a", spend: 0.50)
        let b = MockProvider(name: "b", spend: 0.25)
        let chain = FallbackChain(providers: [a, b])

        let total = await chain.currentSessionSpend
        #expect(total == 0.75)
    }
}
