import Foundation

// MARK: - EmojiRouter (BR-EM-01)
// Pre-parser that rewrites emoji in argv before ArgumentParser sees them.
// Pure function, no side effects, no coupling to ArgumentParser.

public enum EmojiRouter: Sendable {

    /// Rewrite argv if the first argument after the binary name is a registered emoji.
    /// Returns the original args unchanged if no emoji match is found.
    ///
    /// Examples:
    ///   ["shi", "🥕"]           → ["shi", "doctor"]
    ///   ["shi", "🔍", "CRDTs"] → ["shi", "research", "CRDTs"]
    ///   ["shi", "doctor"]       → ["shi", "doctor"] (passthrough)
    ///   ["shi"]                 → ["shi"] (passthrough)
    public static func rewrite(_ args: [String]) -> [String] {
        guard args.count >= 2 else { return args }

        let candidate = args[1]
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces)

        // Try single-character lookup first
        guard candidate.count == 1,
              let char = candidate.first,
              let entry = EmojiRegistry.lookup(char) else {
            return args
        }

        var rewritten = args
        rewritten[1] = entry.command
        return rewritten
    }
}
