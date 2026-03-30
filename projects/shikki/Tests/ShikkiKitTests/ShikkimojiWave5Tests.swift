import Foundation
import Testing
@testable import ShikkiKit

@Suite("Shikkimoji Wave 5 — Polish")
struct ShikkimojiWave5Tests {

    // MARK: - BR-EM-10: Splash emoji shortcuts

    @Test("Splash renderToString contains emoji shortcuts (starter kit)")
    func testSplashContainsEmojiShortcuts() {
        let output = SplashRenderer.renderToString(version: "0.3.0")
        #expect(output.contains("Quick commands:"))
        #expect(output.contains("🥕"))
        #expect(output.contains("doctor"))
        #expect(output.contains("🌡️"))
        #expect(output.contains("status"))
        #expect(output.contains("📊"))
        #expect(output.contains("board"))
        #expect(output.contains("🚀"))
        #expect(output.contains("wave"))
        #expect(output.contains("📃"))
        #expect(output.contains("help"))
    }

    // MARK: - BR-EM-17: Shell alias generation

    @Test("generateShellAliases contains doctor text alias")
    func testGenerateShellAliases_containsDoctor() {
        let aliases = EmojiRegistry.generateShellAliases()
        // Text alias
        #expect(aliases.contains("alias sk-doctor='shikki doctor'"))
        // Emoji alias for 🥕 → doctor
        #expect(aliases.contains("shikki doctor"))
    }

    @Test("generateShellAliases produces valid bash syntax (alias keyword, no bare lines)")
    func testGenerateShellAliases_validBashSyntax() {
        let aliases = EmojiRegistry.generateShellAliases()
        let nonCommentLines = aliases
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix("#") }

        for line in nonCommentLines {
            // Every non-comment, non-empty line must start with `alias `
            #expect(line.hasPrefix("alias "), "Invalid line: \(line)")
            // Must contain `=` (key=value)
            #expect(line.contains("="), "Missing = in alias line: \(line)")
            // Value must be single-quoted
            #expect(line.contains("='"), "Missing single-quote in alias line: \(line)")
        }
    }
}
