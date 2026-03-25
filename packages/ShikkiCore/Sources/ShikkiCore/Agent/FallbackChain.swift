import Foundation
import Logging

/// Tries providers in order, falling back to the next on failure.
/// Conforms to `AgentProvider` so it can be used anywhere a single provider is expected.
public actor FallbackChain: AgentProvider {
    public nonisolated let name = "fallback-chain"

    private let providers: [any AgentProvider]
    private let logger = Logger(label: "shikki.core.fallback-chain")

    /// - Parameter providers: Ordered list of providers (highest priority first).
    public init(providers: [any AgentProvider]) {
        self.providers = providers
    }

    /// Accumulated spend across all providers in the chain.
    public var currentSessionSpend: Double {
        get async {
            var total: Double = 0
            for provider in providers {
                total += await provider.currentSessionSpend
            }
            return total
        }
    }

    public func dispatch(
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions
    ) async throws -> AgentResult {
        guard !providers.isEmpty else {
            throw AgentProviderError.unavailable(provider: name)
        }

        var lastError: (any Error)?
        for provider in providers {
            do {
                let result = try await provider.dispatch(
                    prompt: prompt,
                    workingDirectory: workingDirectory,
                    options: options
                )
                return result
            } catch {
                logger.warning("Provider '\(provider.name)' failed: \(error). Trying next.")
                lastError = error
            }
        }

        throw lastError!
    }

    /// Cancel all providers in the chain.
    public func cancel() async {
        for provider in providers {
            await provider.cancel()
        }
    }
}
