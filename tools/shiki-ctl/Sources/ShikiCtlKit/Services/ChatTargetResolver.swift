import Foundation

// MARK: - Chat Target

/// Resolved target for a chat message.
public enum ChatTarget: Sendable, Equatable {
    case orchestrator
    case agent(sessionId: String)
    case persona(AgentPersona)
    case broadcast
}

// MARK: - Chat Target Resolver

/// Resolves @ targeting syntax to a ChatTarget.
public enum ChatTargetResolver {

    /// Known persona aliases (case-insensitive).
    private static let personaAliases: [String: AgentPersona] = [
        "sensei": .investigate,     // CTO review = investigate persona
        "hanami": .critique,        // UX review = critique persona
        "kintsugi": .critique,      // Philosophy = critique persona
        "tech-expert": .review,     // Code review = review persona
        "ronin": .review,           // Adversarial = review persona
    ]

    /// Resolve a raw input string to a ChatTarget.
    /// Returns nil if the input doesn't start with @.
    public static func resolve(_ input: String) -> ChatTarget? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return nil }

        let target = String(trimmed.dropFirst()).lowercased()

        // Special targets
        if target == "orchestrator" || target == "shiki" || target == "shi" {
            return .orchestrator
        }
        if target == "all" {
            return .broadcast
        }

        // Persona aliases
        if let persona = personaAliases[target] {
            return .persona(persona)
        }

        // Agent session (contains :)
        if target.contains(":") {
            return .agent(sessionId: String(trimmed.dropFirst()))
        }

        // Unknown — try as agent session anyway
        return .agent(sessionId: String(trimmed.dropFirst()))
    }
}

// MARK: - Prompt Composer Helpers

/// Ghost text and trigger detection for the prompt composer / editor mode.
public enum PromptComposer {

    /// Get contextual ghost text based on the previous line.
    public static func ghostText(afterLine line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return "When / For each / ? / ## "
        }
        if trimmed.lowercased().hasPrefix("when ") && trimmed.hasSuffix(":") {
            return "  → show what happens"
        }
        if trimmed.hasPrefix("→") || trimmed.hasPrefix("->") {
            return "  → next expected outcome"
        }
        if trimmed.hasPrefix("## ") {
            return "Section name"
        }
        if trimmed.hasPrefix("? ") {
            return "  expect: what should happen"
        }
        if trimmed.lowercased().hasPrefix("if ") && trimmed.hasSuffix(":") {
            return "    → expected outcome"
        }
        return ""
    }

    /// Detect inline triggers (@ for autocomplete, / for search).
    public static func detectTrigger(in text: String) -> ComposerTrigger? {
        // Find last @ that starts a word
        if let atRange = text.range(of: "@\\w+$", options: .regularExpression) {
            let word = String(text[atRange].dropFirst()) // remove @
            return .at(word)
        }
        // Find last / that starts a search
        if let slashRange = text.range(of: "/[\\w:]+$", options: .regularExpression) {
            let query = String(text[slashRange].dropFirst()) // remove /
            return .search(query)
        }
        // Find last # for scope
        if let hashRange = text.range(of: "#\\w+$", options: .regularExpression) {
            let scope = String(text[hashRange].dropFirst())
            return .scope(scope)
        }
        return nil
    }
}

/// Trigger types detected in composer text.
public enum ComposerTrigger: Sendable, Equatable {
    case at(String)       // @ autocomplete
    case search(String)   // / search
    case scope(String)    // # scope
}
