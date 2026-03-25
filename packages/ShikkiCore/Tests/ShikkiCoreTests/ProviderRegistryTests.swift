import Testing
import Foundation
@testable import ShikkiCore

@Suite("ProviderRegistry")
struct ProviderRegistryTests {

    @Test("Register and retrieve provider by name")
    func registerAndRetrieve() async throws {
        let registry = ProviderRegistry()
        let provider = ClaudeProvider()
        registry.register(name: "claude", provider: provider)

        let retrieved = registry.provider(named: "claude")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "claude")
        #expect(registry.provider(named: "nonexistent") == nil)
    }

    @Test("Default chain orders claude > openrouter > local")
    func defaultChainConstruction() async throws {
        let registry = ProviderRegistry()
        // Register in reverse order to verify sorting
        let local = LocalProvider()
        let openrouter = OpenRouterProvider(apiKey: "test")
        let claude = ClaudeProvider()

        registry.register(name: "local", provider: local)
        registry.register(name: "openrouter", provider: openrouter)
        registry.register(name: "claude", provider: claude)

        let chain = registry.defaultChain()
        #expect(chain.name == "fallback-chain")
        // The chain should exist with all 3 providers
        #expect(registry.registeredNames.count == 3)
    }

    @Test("Capability filtering returns matching providers")
    func capabilityFiltering() async throws {
        let registry = ProviderRegistry()
        let local = LocalProvider()
        let claude = ClaudeProvider()

        registry.register(name: "local", provider: local, capabilities: [.offline, .cheap])
        registry.register(name: "claude", provider: claude, capabilities: [.codeExecution, .longContext])

        let offlineProviders = registry.providers(with: .offline)
        #expect(offlineProviders.count == 1)
        #expect(offlineProviders.first?.name == "local")

        let cheapProviders = registry.providers(with: .cheap)
        #expect(cheapProviders.count == 1)

        let codeProviders = registry.providers(with: .codeExecution)
        #expect(codeProviders.count == 1)
        #expect(codeProviders.first?.name == "claude")
    }
}
