/// Routes AI requests to the best available provider.
public struct ProviderRouter: Sendable {
    private let providers: [any AIProvider]

    public init(providers: [any AIProvider]) {
        self.providers = providers
    }

    /// Select best provider for the given capabilities.
    /// Returns the first provider whose capabilities are a superset of the requested ones.
    public func route(capabilities: AICapabilities) async -> (any AIProvider)? {
        for provider in providers {
            if provider.capabilities.contains(capabilities) {
                let status = await provider.status
                if case .ready = status {
                    return provider
                }
            }
        }
        return nil
    }

    /// Try providers in order until one succeeds. Throws allProvidersFailed if none work.
    public func routeWithFallback(
        request: AIRequest,
        providers fallbackProviders: [any AIProvider]
    ) async throws -> AIResponse {
        for provider in fallbackProviders {
            do {
                return try await provider.complete(request: request)
            } catch {
                continue
            }
        }
        throw AIKitError.allProvidersFailed
    }
}

/// User preferences for provider selection.
public struct ProviderPreferences: Sendable, Codable, Equatable {
    /// Prefer local models over API.
    public var preferLocal: Bool
    /// Maximum acceptable latency (ms). 0 = no limit.
    public var maxLatencyMs: Int
    /// Budget: max cost per request (USD). 0 = free only.
    public var maxCostPerRequest: Double
    /// Required capabilities.
    public var requiredCapabilities: AICapabilities

    public init(
        preferLocal: Bool = true,
        maxLatencyMs: Int = 0,
        maxCostPerRequest: Double = 0,
        requiredCapabilities: AICapabilities = []
    ) {
        self.preferLocal = preferLocal
        self.maxLatencyMs = maxLatencyMs
        self.maxCostPerRequest = maxCostPerRequest
        self.requiredCapabilities = requiredCapabilities
    }
}
