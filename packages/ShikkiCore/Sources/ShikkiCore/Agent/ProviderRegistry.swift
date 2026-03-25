import Foundation

/// Capability tags for filtering providers by what they support.
public enum ProviderCapability: String, Sendable, Hashable {
    case codeExecution
    case longContext
    case cheap
    case offline
}

/// Central registry for available agent providers.
/// Providers register themselves with capability tags for selection by `CompanyManager`.
public final class ProviderRegistry: @unchecked Sendable {
    public static let shared = ProviderRegistry()

    private var entries: [(name: String, provider: any AgentProvider, capabilities: Set<ProviderCapability>)] = []
    private let lock = NSLock()

    public init() {}

    /// Register a provider with its capability tags.
    public func register(name: String, provider: any AgentProvider, capabilities: Set<ProviderCapability> = []) {
        lock.lock()
        defer { lock.unlock() }
        // Replace existing entry with same name
        entries.removeAll { $0.name == name }
        entries.append((name: name, provider: provider, capabilities: capabilities))
    }

    /// Retrieve a provider by name.
    public func provider(named name: String) -> (any AgentProvider)? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.name == name }?.provider
    }

    /// All registered provider names.
    public var registeredNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.map(\.name)
    }

    /// Filter providers by a required capability.
    public func providers(with capability: ProviderCapability) -> [any AgentProvider] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.capabilities.contains(capability) }.map(\.provider)
    }

    /// Build a default fallback chain from registered providers.
    /// Order: claude > openrouter > local (if registered).
    public func defaultChain() -> FallbackChain {
        lock.lock()
        defer { lock.unlock() }
        let preferred = ["claude", "openrouter", "local"]
        let ordered = preferred.compactMap { name in
            entries.first { $0.name == name }?.provider
        }
        // Append any remaining providers not in the preferred list
        let extra = entries.filter { entry in !preferred.contains(entry.name) }.map(\.provider)
        return FallbackChain(providers: ordered + extra)
    }

    /// Remove all registered providers (useful for testing).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
