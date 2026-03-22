import Foundation

/// Typo-forgiveness layer for shikki subcommands.
/// BR-41: Levenshtein ≤2 → execute match + soft hint.
/// BR-42: Distance >2 → error.
/// BR-43: NEVER auto-correct to "stop" — safety.
/// BR-44: Case-insensitive comparison.
public enum TypoCorrector {

    /// All known shikki subcommands.
    public static let knownCommands: [String] = [
        "stop", "pr", "board", "dashboard", "doctor", "report",
        "search", "ship", "menu", "decide", "heartbeat", "history",
        "wake", "pause", "restart", "status",
    ]

    /// A typo correction suggestion.
    public struct Suggestion: Equatable, Sendable {
        public let original: String
        public let corrected: String
        public let distance: Int
    }

    /// Suggest a correction for a mistyped command.
    /// Returns nil if: exact match, distance >2, empty input, or best match is "stop" (BR-43).
    public static func suggest(_ input: String, commands: [String]? = nil) -> Suggestion? {
        let input = input.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return nil }

        let lowered = input.lowercased()
        let candidates = commands ?? knownCommands

        // Exact match → no correction needed
        if candidates.contains(lowered) { return nil }

        var bestMatch: String?
        var bestDistance = Int.max

        for cmd in candidates {
            let dist = levenshteinDistance(lowered, cmd)
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = cmd
            }
        }

        // BR-42: Only suggest if distance ≤ 2
        guard bestDistance <= 2, let match = bestMatch else { return nil }

        // BR-43: NEVER suggest "stop"
        guard match != "stop" else { return nil }

        return Suggestion(original: input, corrected: match, distance: bestDistance)
    }

    /// Levenshtein edit distance between two strings.
    public static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,  // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            prev = curr
        }

        return curr[n]
    }
}
