import Testing
@testable import ShikkiKit

@Suite("TerminalOutput")
struct TerminalOutputTests {

    @Test("visibleLength strips ANSI escape codes")
    func visibleLengthStripsANSI() {
        let plain = "hello"
        #expect(TerminalOutput.visibleLength(plain) == 5)

        let colored = "\u{1B}[32mhello\u{1B}[0m"
        #expect(TerminalOutput.visibleLength(colored) == 5)

        let bold = "\u{1B}[1m\u{1B}[36mStatus\u{1B}[0m"
        #expect(TerminalOutput.visibleLength(bold) == 6)

        let empty = ""
        #expect(TerminalOutput.visibleLength(empty) == 0)
    }

    @Test("visibleLength handles multiple ANSI sequences")
    func visibleLengthMultipleSequences() {
        let mixed = "\u{1B}[1mBold\u{1B}[0m and \u{1B}[31mred\u{1B}[0m"
        #expect(TerminalOutput.visibleLength(mixed) == 12) // "Bold and red"
    }

    @Test("pad adds correct whitespace accounting for ANSI")
    func padAccountsForANSI() {
        let plain = TerminalOutput.pad("hi", 10)
        #expect(plain == "hi        ")
        #expect(plain.count == 10)

        let colored = TerminalOutput.pad("\u{1B}[32mhi\u{1B}[0m", 10)
        // Visible "hi" = 2 chars, so 8 spaces padding, but total string includes ANSI
        #expect(TerminalOutput.visibleLength(colored) == 10)
    }

    @Test("pad returns original if already wider")
    func padNoTruncation() {
        let wide = "this is a long string"
        let result = TerminalOutput.pad(wide, 5)
        #expect(result == wide)
    }

    @Test("terminalWidth returns at least 66")
    func terminalWidthMinimum() {
        let width = TerminalOutput.terminalWidth()
        #expect(width >= 66)
    }
}
