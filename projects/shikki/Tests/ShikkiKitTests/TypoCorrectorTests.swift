import Foundation
import Testing
@testable import ShikkiKit

@Suite("TypoCorrector — BR-41 to BR-44")
struct TypoCorrectorTests {

    // BR-41: Levenshtein distance 1 → suggest + hint
    @Test("Distance 1 returns suggestion")
    func typo_distance1_executesWithHint() {
        let result = TypoCorrector.suggest("bord")
        #expect(result != nil)
        #expect(result?.corrected == "board")
        #expect(result?.distance == 1)
    }

    // BR-41: Levenshtein distance 2 → suggest + hint
    @Test("Distance 2 returns suggestion")
    func typo_distance2_executesWithHint() {
        let result = TypoCorrector.suggest("boadr")
        #expect(result != nil)
        #expect(result?.corrected == "board")
    }

    // BR-42: Distance > 2 → error, no suggestion
    @Test("Distance 3+ returns nil")
    func typo_distance3_showsError() {
        let result = TypoCorrector.suggest("xyzzy")
        #expect(result == nil)
    }

    @Test("Complete garbage returns nil")
    func typo_completeGarbage_showsError() {
        let result = TypoCorrector.suggest("asdfghjkl")
        #expect(result == nil)
    }

    // BR-43: NEVER auto-correct to "stop" — safety
    @Test("Typo close to 'stop' does NOT suggest stop")
    func typo_closerToStop_neverSuggests() {
        let result1 = TypoCorrector.suggest("stp")
        #expect(result1?.corrected != "stop")

        let result2 = TypoCorrector.suggest("sotp")
        #expect(result2?.corrected != "stop")

        let result3 = TypoCorrector.suggest("stpo")
        #expect(result3?.corrected != "stop")
    }

    // BR-44: Case-insensitive — exact match with different case is NOT a typo
    @Test("Case-insensitive exact match returns nil (just case difference)")
    func typo_caseInsensitive_exactMatchReturnsNil() {
        // "PR" → "pr" is exact, not a typo
        let result1 = TypoCorrector.suggest("PR")
        #expect(result1 == nil)

        // "BoArD" → "board" is exact, not a typo
        let result2 = TypoCorrector.suggest("BoArD")
        #expect(result2 == nil)
    }

    // BR-44: Case-insensitive typo correction
    @Test("Case-insensitive typo still suggests correctly")
    func typo_caseInsensitive_typoSuggests() {
        // "BORD" → "board" (distance 1, case-insensitive)
        let result = TypoCorrector.suggest("BORD")
        #expect(result != nil)
        #expect(result?.corrected == "board")
    }

    // Exact match returns nil (no correction needed)
    @Test("Exact match returns nil — no correction needed")
    func typo_exactMatch_returnsNil() {
        let result = TypoCorrector.suggest("board")
        #expect(result == nil)
    }

    // Empty input
    @Test("Empty input returns nil")
    func typo_empty_returnsNil() {
        let result = TypoCorrector.suggest("")
        #expect(result == nil)
    }
}
