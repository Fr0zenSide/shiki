import Foundation

// MARK: - CommitAttribution

/// Generates the attribution trailer for git commits.
///
/// Replaces "Co-Authored-By: Claude" with structured attribution:
/// - `Orchestrated-By:` — Shikki version (always present)
/// - `Generated-By:` — AI agent used (with provider info)
/// - `Spec:` — source spec if applicable
/// - `Scope:` — architecture scope from Moto cache
///
/// Configurable per-company in Shikki preferences.
public struct CommitAttribution: Sendable {

    public struct Config: Sendable, Codable {
        /// Whether to include agent attribution (default: true)
        public var includeAgent: Bool
        /// Whether to include spec reference (default: true)
        public var includeSpec: Bool
        /// Custom override for the agent line (e.g., company email format)
        public var agentOverride: String?
        /// Whether to use the legacy "Co-Authored-By" format (default: false)
        public var useLegacyFormat: Bool

        public static let `default` = Config(
            includeAgent: true,
            includeSpec: true,
            agentOverride: nil,
            useLegacyFormat: false
        )

        public init(
            includeAgent: Bool = true,
            includeSpec: Bool = true,
            agentOverride: String? = nil,
            useLegacyFormat: Bool = false
        ) {
            self.includeAgent = includeAgent
            self.includeSpec = includeSpec
            self.agentOverride = agentOverride
            self.useLegacyFormat = useLegacyFormat
        }
    }

    /// Agent identity
    public struct AgentInfo: Sendable {
        public let provider: String      // "claude", "mistral", "local-mlx", etc.
        public let model: String          // "opus-4.6", "codestral-25.01", etc.
        public let version: String?       // "1M context", etc.

        public init(provider: String, model: String, version: String? = nil) {
            self.provider = provider
            self.model = model
            self.version = version
        }

        public var displayName: String {
            var name = "\(provider)/\(model)"
            if let v = version { name += " (\(v))" }
            return name
        }
    }

    /// Shikki version
    public static let shikkiVersion = "0.3.0-pre"

    /// Shikki bot identity for git/GitHub attribution
    public static let shikkiEmail = "shikki@obyw.one"
    public static let shikkiName = "Shikki"

    /// Generate attribution trailer for a commit message.
    public static func trailer(
        agent: AgentInfo,
        spec: String? = nil,
        scope: String? = nil,
        config: Config = .default
    ) -> String {
        if config.useLegacyFormat {
            return legacyTrailer(agent: agent)
        }

        var lines: [String] = []

        // Always first: Shikki as primary contributor
        lines.append("Co-Authored-By: \(shikkiName) <\(shikkiEmail)>")

        // Shikki orchestration version
        lines.append("Orchestrated-By: shikki/\(shikkiVersion)")

        // Agent that did the generation (secondary credit)
        if config.includeAgent {
            if let override = config.agentOverride {
                lines.append("Generated-By: \(override)")
            } else {
                lines.append("Generated-By: \(agent.displayName)")
            }
        }

        // Spec reference (if enabled and provided)
        if config.includeSpec, let spec {
            lines.append("Spec: \(spec)")
        }

        // Architecture scope
        if let scope {
            lines.append("Scope: \(scope)")
        }

        return lines.joined(separator: "\n")
    }

    /// Legacy format for backwards compatibility
    private static func legacyTrailer(agent: AgentInfo) -> String {
        "Co-Authored-By: \(shikkiName) <\(shikkiEmail)>"
    }

    /// Parse an existing trailer to extract attribution info
    public static func parse(_ trailer: String) -> (orchestrator: String?, agent: String?, spec: String?, scope: String?) {
        var orchestrator: String?
        var agent: String?
        var spec: String?
        var scope: String?

        for line in trailer.split(separator: "\n") {
            let l = String(line).trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("Orchestrated-By:") {
                orchestrator = String(l.dropFirst("Orchestrated-By:".count)).trimmingCharacters(in: .whitespaces)
            } else if l.hasPrefix("Generated-By:") {
                agent = String(l.dropFirst("Generated-By:".count)).trimmingCharacters(in: .whitespaces)
            } else if l.hasPrefix("Spec:") {
                spec = String(l.dropFirst("Spec:".count)).trimmingCharacters(in: .whitespaces)
            } else if l.hasPrefix("Scope:") {
                scope = String(l.dropFirst("Scope:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        return (orchestrator, agent, spec, scope)
    }
}
