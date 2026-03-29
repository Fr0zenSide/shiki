import Foundation

// MARK: - Types

/// A single step in an emoji chain.
public struct ChainStep: Sendable, Equatable {
    public let emoji: Character
    public let command: String

    public init(emoji: Character, command: String) {
        self.emoji = emoji
        self.command = command
    }
}

/// Targeting for a chain — who executes it.
public enum AgentTarget: Sendable, Equatable {
    case team
    case agent(String)
    case namedTeam(String)

    public init?(string: String) {
        switch string.lowercased() {
        case "t", "team", "shi":
            self = .team
        case "tech", "creative", "marketing":
            self = .namedTeam(string.lowercased())
        default:
            self = .agent(string)
        }
    }
}

/// A parsed emoji chain: steps + optional target + optional trailing args.
public struct EmojiChain: Sendable, Equatable {
    public let steps: [ChainStep]
    public let target: AgentTarget?
    public let rawArgs: String

    public init(steps: [ChainStep], target: AgentTarget?, rawArgs: String) {
        self.steps = steps
        self.target = target
        self.rawArgs = rawArgs
    }
}

/// Result of chain parsing — either a parsed chain, a single command (not a chain),
/// or an error.
public enum ChainParseResult: Sendable, Equatable {
    case chain(EmojiChain)
    case singleCommand(ChainStep)
    case error(String)
}

// MARK: - Team Aliases

/// Built-in team aliases (BR-EM-CHAIN-11).
public enum TeamAliases: Sendable {
    public static let tech: [String] = ["Sensei", "Ronin", "Katana", "Kenshi", "Metsuke"]
    public static let creative: [String] = ["Sensei", "Hanami", "Enso", "Tsubaki", "Kintsugi"]
    public static let marketing: [String] = ["Sensei", "Shogun", "Enso", "Tsubaki"]

    /// Resolve a named team alias to its member list.
    /// Returns nil if the alias is not recognized.
    public static func resolve(_ name: String) -> [String]? {
        switch name.lowercased() {
        case "tech": return tech
        case "creative": return creative
        case "marketing": return marketing
        default: return nil
        }
    }

    /// All built-in team names.
    public static let allTeamNames: [String] = ["tech", "creative", "marketing"]
}

// MARK: - ChainParser

/// Parses emoji chain strings into structured `EmojiChain` values (BR-EM-CHAIN-01..11).
public enum ChainParser: Sendable {

    /// Maximum times the same emoji can repeat in a chain (BR-EM-CHAIN-05).
    public static let maxRepetition = 3

    /// Parse an input string into a chain result.
    ///
    /// The input is the first argument token (e.g. "🌟🧠@t").
    /// Trailing args come from subsequent tokens and are passed separately.
    ///
    /// Format: `[emoji...][@target] [args...]`
    ///
    /// - Parameter input: The full input string (may include spaces for args).
    /// - Returns: A `ChainParseResult`.
    public static func parse(_ input: String) -> ChainParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .error("Empty input")
        }

        // Split on first space: token + args
        let (token, args) = splitTokenAndArgs(trimmed)

        // Split token into emoji portion and @target portion
        let (emojiPortion, targetString) = splitEmojiAndTarget(token)

        guard !emojiPortion.isEmpty else {
            return .error("No emoji found in input")
        }

        // Parse emoji characters
        var steps: [ChainStep] = []
        for char in emojiPortion {
            guard let entry = EmojiRegistry.lookup(char) else {
                // Unrecognized character terminates emoji parsing
                break
            }
            steps.append(ChainStep(emoji: char, command: entry.command))
        }

        guard !steps.isEmpty else {
            return .error("No recognized emoji in input")
        }

        // BR-EM-CHAIN-06: Destructive emoji cannot chain
        if steps.count > 1 {
            for step in steps {
                let entry = EmojiRegistry.lookup(step.emoji)
                if entry?.isDestructive == true {
                    return .error(
                        "Destructive commands cannot be chained. Run `shikki \(step.emoji)` separately."
                    )
                }
            }
        }

        // BR-EM-CHAIN-05: Repetition cap
        if let capError = checkRepetitionCap(steps) {
            return .error(capError)
        }

        // Parse target
        let target: AgentTarget? = targetString.flatMap { AgentTarget(string: $0) }

        // Single emoji = not a chain, delegate to regular routing
        if steps.count == 1 && target == nil {
            return .singleCommand(steps[0])
        }

        let chain = EmojiChain(steps: steps, target: target, rawArgs: args)
        return .chain(chain)
    }

    // MARK: - Private Helpers

    /// Split input on first space into (token, remainingArgs).
    private static func splitTokenAndArgs(_ input: String) -> (String, String) {
        guard let spaceIndex = input.firstIndex(of: " ") else {
            return (input, "")
        }
        let token = String(input[input.startIndex..<spaceIndex])
        let args = String(input[input.index(after: spaceIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return (token, args)
    }

    /// Split a token like "🌟🧠@Sensei" into emoji portion and target string.
    /// The `@` boundary separates emoji from target.
    private static func splitEmojiAndTarget(_ token: String) -> (String, String?) {
        guard let atIndex = token.firstIndex(of: "@") else {
            return (token, nil)
        }
        let emojiPortion = String(token[token.startIndex..<atIndex])
        let targetString = String(token[token.index(after: atIndex)...])
        if targetString.isEmpty {
            return (emojiPortion, nil)
        }
        return (emojiPortion, targetString)
    }

    /// Check repetition cap (BR-EM-CHAIN-05).
    /// Returns an error message if any emoji repeats more than `maxRepetition` times.
    private static func checkRepetitionCap(_ steps: [ChainStep]) -> String? {
        var counts: [String: Int] = [:]
        for step in steps {
            let key = String(step.emoji)
            counts[key, default: 0] += 1
            if counts[key]! > maxRepetition {
                return "Chain repetition limit is \(maxRepetition). Use a loop or separate commands."
            }
        }
        return nil
    }
}
