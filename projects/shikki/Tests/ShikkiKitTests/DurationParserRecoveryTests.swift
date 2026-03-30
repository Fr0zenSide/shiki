import Foundation
import Testing
@testable import ShikkiKit

@Suite("DurationParser recovery extensions — BR-01, BR-06")
struct DurationParserRecoveryTests {

    @Test("Parse hours — 2h equals 7200s")
    func parseDuration_hours() throws {
        let result = try DurationParser.parseForRecovery("2h")
        #expect(result.seconds == 7200)
        #expect(result.clamped == false)
    }

    @Test("Parse minutes — 30m equals 1800s")
    func parseDuration_minutes() throws {
        let result = try DurationParser.parseForRecovery("30m")
        #expect(result.seconds == 1800)
        #expect(result.clamped == false)
    }

    @Test("Parse seconds — 3600s equals 3600s")
    func parseDuration_seconds() throws {
        let result = try DurationParser.parseForRecovery("3600s")
        #expect(result.seconds == 3600)
        #expect(result.clamped == false)
    }

    @Test("Parse days — 7d equals 604800s")
    func parseDuration_days() throws {
        let result = try DurationParser.parseForRecovery("7d")
        #expect(result.seconds == 604800)
        #expect(result.clamped == false)
    }

    @Test("Invalid format throws error with examples")
    func parseDuration_invalidFormat_throwsError() {
        #expect(throws: DurationParseError.self) {
            try DurationParser.parseForRecovery("abc")
        }
    }

    @Test("Exceeds max clamps to 7d")
    func parseDuration_exceedsMax_clampsTo7d() throws {
        let result = try DurationParser.parseForRecovery("10d")
        #expect(result.seconds == DurationParser.maxRecoveryDuration)
        #expect(result.clamped == true)
    }

    @Test("Empty string throws error")
    func parseDuration_emptyString_throwsError() {
        #expect(throws: DurationParseError.self) {
            try DurationParser.parseForRecovery("")
        }
    }

    @Test("Whitespace-only string throws error")
    func parseDuration_whitespaceOnly_throwsError() {
        #expect(throws: DurationParseError.self) {
            try DurationParser.parseForRecovery("   ")
        }
    }

    @Test("Large hours value clamps to 7d")
    func parseDuration_largeHours_clampsTo7d() throws {
        let result = try DurationParser.parseForRecovery("200h")
        #expect(result.seconds == DurationParser.maxRecoveryDuration)
        #expect(result.clamped == true)
    }
}
