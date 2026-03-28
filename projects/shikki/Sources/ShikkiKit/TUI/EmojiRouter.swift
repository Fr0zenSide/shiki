import Foundation

// MARK: - EmojiRouter (BR-EM-01)
// Pre-parser that rewrites emoji in argv before ArgumentParser sees them.
// Pure function, no side effects, no coupling to ArgumentParser.

public enum EmojiRouter: Sendable {

    /// Rewrite argv if the first argument after the binary name is a registered emoji.
    /// Returns the original args unchanged if no emoji match is found.
    ///
    /// Examples:
    ///   ["shikki", "🥕"]           → ["shikki", "doctor"]
    ///   ["shikki", "🔍", "CRDTs"] → ["shikki", "research", "CRDTs"]
    ///   ["shikki", "doctor"]       → ["shikki", "doctor"] (passthrough)
    ///   ["shikki"]                 → ["shikki"] (passthrough)
    public static func rewrite(_ args: [String]) -> [String] {
        guard args.count >= 2 else { return args }

        let candidate = args[1]
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces)

        guard let command = EmojiRegistry.resolve(candidate) else {
            return args
        }

        var rewritten = args
        rewritten[1] = command
        return rewritten
    }
}
