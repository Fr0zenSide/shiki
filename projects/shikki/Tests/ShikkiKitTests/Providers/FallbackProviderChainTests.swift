import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Stubbed Providers for Chain Tests

/// A provider that always succeeds with a fixed response.
private final class SucceedingProvider: AgentProviding, @unchecked Sendable {
    let response: String
    var callCount = 0

    init(response: String = "success") {
        self.response = response
    }

    func run(prompt: String, timeout: TimeInterval) async throws -> String {
        callCount += 1
        return response
    }
}

/// A provider that always fails with a configurable error.
private final class FailingProvider: AgentProviding, @unchecked Sendable {
    let error: any Error
    var callCount = 0

    init(error: any Error) {
        self.error = error
    }

    func run(prompt: String, timeout: TimeInterval) async throws -> String {
        callCount += 1
        throw error
    }
}

// MARK: - FallbackProviderChain Tests

@Suite("FallbackProviderChain — Priority-Ordered Fallback")
struct FallbackProviderChainTests {

    // MARK: - Test 5: Uses primary when available

    @Test("uses primary provider when it succeeds")
    func usesPrimaryWhenAvailable() async throws {
        let primary = SucceedingProvider(response: "from-claude")
        let fallback = SucceedingProvider(response: "from-lmstudio")

        let chain = FallbackProviderChain(providers: [primary, fallback])
        let result = try await chain.run(prompt: "test", timeout: 60)

        #expect(result == "from-claude")
        #expect(primary.callCount == 1)
        #expect(fallback.callCount == 0)
    }

    // MARK: - Test 6: Falls back on rate limit (429)

    @Test("falls back to next provider on rate limit error")
    func fallsBackOnRateLimit() async throws {
        let rateLimitedPrimary = FailingProvider(
            error: LMStudioProvider.LMStudioError.rateLimited
        )
        let fallback = SucceedingProvider(response: "from-fallback")

        let chain = FallbackProviderChain(providers: [rateLimitedPrimary, fallback])
        let result = try await chain.run(prompt: "test", timeout: 60)

        #expect(result == "from-fallback")
        #expect(rateLimitedPrimary.callCount == 1)
        #expect(fallback.callCount == 1)
    }

    // MARK: - Test 7: Falls back on connection error

    @Test("falls back to next provider on connection error")
    func fallsBackOnConnectionError() async throws {
        let offlinePrimary = FailingProvider(
            error: LMStudioProvider.LMStudioError.connectionRefused("Server offline")
        )
        let fallback = SucceedingProvider(response: "local-model-response")

        let chain = FallbackProviderChain(providers: [offlinePrimary, fallback])
        let result = try await chain.run(prompt: "generate spec", timeout: 120)

        #expect(result == "local-model-response")
        #expect(offlinePrimary.callCount == 1)
        #expect(fallback.callCount == 1)
    }

    // MARK: - Test 8: All exhausted throws final error

    @Test("throws allProvidersFailed when every provider fails")
    func allExhaustedThrows() async throws {
        let provider1 = FailingProvider(
            error: LMStudioProvider.LMStudioError.rateLimited
        )
        let provider2 = FailingProvider(
            error: LMStudioProvider.LMStudioError.connectionRefused("offline")
        )

        let chain = FallbackProviderChain(providers: [provider1, provider2])

        await #expect(throws: FallbackProviderChain.ChainError.self) {
            try await chain.run(prompt: "test", timeout: 60)
        }

        #expect(provider1.callCount == 1)
        #expect(provider2.callCount == 1)
    }

    // MARK: - Additional: Non-fallback error propagates immediately

    @Test("non-fallback error propagates without trying next provider")
    func nonFallbackErrorPropagates() async throws {
        let brokenPrimary = FailingProvider(
            error: LMStudioProvider.LMStudioError.invalidResponse("bad json")
        )
        let fallback = SucceedingProvider(response: "should-not-reach")

        let chain = FallbackProviderChain(providers: [brokenPrimary, fallback])

        await #expect(throws: LMStudioProvider.LMStudioError.self) {
            try await chain.run(prompt: "test", timeout: 60)
        }

        #expect(brokenPrimary.callCount == 1)
        #expect(fallback.callCount == 0)
    }

    // MARK: - Additional: Empty chain throws

    @Test("empty provider chain throws noProviders")
    func emptyChainThrows() async throws {
        let chain = FallbackProviderChain(providers: [])

        await #expect(throws: FallbackProviderChain.ChainError.self) {
            try await chain.run(prompt: "test", timeout: 60)
        }
    }

    // MARK: - Additional: Three-provider chain

    @Test("three-provider chain falls through two failures")
    func threeProviderChain() async throws {
        let p1 = FailingProvider(error: LMStudioProvider.LMStudioError.rateLimited)
        let p2 = FailingProvider(
            error: LMStudioProvider.LMStudioError.connectionRefused("down")
        )
        let p3 = SucceedingProvider(response: "third-provider-wins")

        let chain = FallbackProviderChain(providers: [p1, p2, p3])
        let result = try await chain.run(prompt: "test", timeout: 60)

        #expect(result == "third-provider-wins")
        #expect(p1.callCount == 1)
        #expect(p2.callCount == 1)
        #expect(p3.callCount == 1)
    }

    // MARK: - Test 9: HealthCheck returns available with latency

    @Test("HealthCheck available result has latency")
    func healthCheckAvailableHasLatency() {
        let status = ProviderHealthCheck.HealthStatus(
            available: true,
            latencyMs: 42.5,
            message: "OK (42ms)"
        )

        #expect(status.available == true)
        #expect(status.latencyMs == 42.5)
        #expect(status.message.contains("OK"))
    }

    // MARK: - Test 10: HealthCheck returns unavailable when offline

    @Test("HealthCheck unavailable result has nil latency")
    func healthCheckUnavailableNilLatency() {
        let status = ProviderHealthCheck.HealthStatus(
            available: false,
            latencyMs: nil,
            message: "Connection failed: could not connect"
        )

        #expect(status.available == false)
        #expect(status.latencyMs == nil)
        #expect(status.message.contains("Connection failed"))
    }

    // MARK: - Additional: HealthCheck against unreachable host

    @Test("HealthCheck against unreachable host returns unavailable")
    func healthCheckUnreachableHost() async {
        // Use a port that is almost certainly not listening
        let status = await ProviderHealthCheck.check(
            baseURL: "http://127.0.0.1:59999",
            timeout: 2
        )

        #expect(status.available == false)
        #expect(status.latencyMs == nil)
    }

    // MARK: - Additional: Fallback eligibility for URLError

    @Test("URLError.cannotConnectToHost is fallback-eligible")
    func urlErrorFallbackEligible() {
        let error = URLError(.cannotConnectToHost)
        #expect(FallbackProviderChain.isFallbackEligible(error))
    }

    @Test("URLError.badURL is NOT fallback-eligible")
    func urlErrorBadURLNotEligible() {
        let error = URLError(.badURL)
        #expect(!FallbackProviderChain.isFallbackEligible(error))
    }

    // MARK: - Additional: SpecPipelineError agent fallback

    @Test("SpecPipelineError with rate limit message is fallback-eligible")
    func specPipelineRateLimitFallback() {
        let error = SpecPipelineError.agentFailed("claude -p exited: rate limit exceeded (429)")
        #expect(FallbackProviderChain.isFallbackEligible(error))
    }

    @Test("SpecPipelineError with generic message is NOT fallback-eligible")
    func specPipelineGenericNotFallback() {
        let error = SpecPipelineError.agentFailed("claude -p exited with status 1")
        #expect(!FallbackProviderChain.isFallbackEligible(error))
    }
}
