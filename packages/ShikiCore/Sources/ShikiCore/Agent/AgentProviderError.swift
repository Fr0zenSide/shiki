import Foundation

/// Errors specific to agent provider operations.
public enum AgentProviderError: Error, Sendable, Equatable {
    /// The provider is not reachable or not running.
    case unavailable(provider: String)

    /// Authentication failed (invalid or missing API key).
    case authenticationFailed(provider: String)

    /// Rate limited by the provider. `retryAfter` is seconds if the provider returned a hint.
    case rateLimited(retryAfterSeconds: Double?)

    /// The provider returned an unparseable or unexpected response.
    case invalidResponse(provider: String, detail: String)
}
