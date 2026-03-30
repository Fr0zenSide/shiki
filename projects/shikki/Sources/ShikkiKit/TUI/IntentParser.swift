import Foundation

// MARK: - Intent

/// Parsed intent from the `@who #where /what` grammar.
/// Each token is optional; missing dimensions default to global.
public struct Intent: Sendable, Equatable {
    /// Who should handle this (nil = orchestrator).
    public let target: ChatTarget?
    /// Where does this apply (nil = global scope).
    public let scopes: [String]
    /// What should happen (nil = inferred from context).
    public let command: String?
    /// Remaining free text after parsing tokens.
    public let message: String

    public init(
        target: ChatTarget? = nil,
        scopes: [String] = [],
        command: String? = nil,
        message: String = ""
    ) {
        self.target = target
        self.scopes = scopes
        self.command = command
        self.message = message
    }
}

// MARK: - IntentParser

/// Parses the full intent grammar: `@who #where /what message`.
public enum IntentParser {

    /// Parse a raw input string into a structured Intent.
    ///
    /// Examples:
    /// - `@Sensei #maya /review` -> target=persona, scope=maya, command=review
    /// - `@all #today /status` -> target=broadcast, scope=today, command=status
    /// - `Hello world` -> target=nil, scope=[], command=nil, message="Hello world"
    public static func parse(_ input: String) -> Intent {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return Intent()
        }

        var target: ChatTarget?
        var scopes: [String] = []
        var command: String?
        var messageParts: [String] = []

        let tokens = tokenize(trimmed)

        for token in tokens {
            if token.hasPrefix("@") && target == nil {
                target = ChatTargetResolver.resolve(token)
            } else if token.hasPrefix("#") && !token.hasPrefix("#define") {
                let scope = String(token.dropFirst())
                if !scope.isEmpty {
                    scopes.append(scope)
                }
            } else if token.hasPrefix("/") && command == nil {
                let cmd = String(token.dropFirst())
                if !cmd.isEmpty {
                    command = cmd
                }
            } else {
                messageParts.append(token)
            }
        }

        return Intent(
            target: target,
            scopes: scopes,
            command: command,
            message: messageParts.joined(separator: " ")
        )
    }

    /// Split input into tokens, preserving quoted strings.
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false

        for char in input {
            if char == "\"" {
                inQuote.toggle()
                continue
            }
            if char == " " && !inQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
