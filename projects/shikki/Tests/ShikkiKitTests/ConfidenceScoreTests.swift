import Foundation
import Testing
@testable import ShikkiKit

@Suite("ConfidenceScore — BR-16 to BR-19")
struct ConfidenceScoreTests {

    @Test("Full DB + full checkpoint + full git returns 100")
    func fullDB_fullCheckpoint_fullGit_returns100() {
        let score = ConfidenceScore(dbScore: 100, checkpointScore: 100, gitScore: 100)
        #expect(score.overall == 100)
    }

    @Test("Empty DB + full checkpoint + full git returns 50")
    func emptyDB_fullCheckpoint_fullGit_returns50() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 100, gitScore: 100)
        #expect(score.overall == 50)
    }

    @Test("DB only with 10+ events returns 50")
    func dbOnly_tenPlusEvents_returns50() {
        let score = ConfidenceScore(dbScore: 100, checkpointScore: 0, gitScore: 0)
        #expect(score.overall == 50)
    }

    @Test("Checkpoint only fresh returns 30")
    func checkpointOnly_fresh_returns30() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 100, gitScore: 0)
        #expect(score.overall == 30)
    }

    @Test("Checkpoint only stale returns 15")
    func checkpointOnly_stale_returns15() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 50, gitScore: 0)
        #expect(score.overall == 15)
    }

    @Test("Git only with commits returns 20")
    func gitOnly_withCommits_returns20() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 0, gitScore: 100)
        #expect(score.overall == 20)
    }

    @Test("Git only dirty tree returns 10")
    func gitOnly_dirtyTree_returns10() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 0, gitScore: 50)
        #expect(score.overall == 10)
    }

    @Test("No sources returns zero")
    func noSources_returnsZero() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 0, gitScore: 0)
        #expect(score.overall == 0)
    }

    @Test("Weighted average matches formula")
    func weightedAverage_matchesFormula() {
        let score = ConfidenceScore(dbScore: 70, checkpointScore: 50, gitScore: 100)
        let expected = Int((70.0 * 0.50 + 50.0 * 0.30 + 100.0 * 0.20).rounded())
        #expect(score.overall == expected)
    }

    // MARK: - Source score helpers

    @Test("DB source score: 100 for >10 events")
    func dbSourceScore_manyEvents() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 15, available: true) == 100)
    }

    @Test("DB source score: 70 for 1-10 events")
    func dbSourceScore_fewEvents() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 5, available: true) == 70)
    }

    @Test("DB source score: 0 when unavailable")
    func dbSourceScore_unavailable() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 50, available: false) == 0)
    }

    @Test("Checkpoint source score: 100 if within window")
    func checkpointSourceScore_withinWindow() {
        #expect(ConfidenceScore.checkpointSourceScore(exists: true, withinWindow: true) == 100)
    }

    @Test("Checkpoint source score: 50 if stale")
    func checkpointSourceScore_stale() {
        #expect(ConfidenceScore.checkpointSourceScore(exists: true, withinWindow: false) == 50)
    }

    @Test("Checkpoint source score: 0 if none")
    func checkpointSourceScore_none() {
        #expect(ConfidenceScore.checkpointSourceScore(exists: false, withinWindow: false) == 0)
    }

    @Test("Git source score: 100 if has commits")
    func gitSourceScore_hasCommits() {
        #expect(ConfidenceScore.gitSourceScore(hasCommits: true, isDirty: false) == 100)
    }

    @Test("Git source score: 50 if dirty only")
    func gitSourceScore_dirty() {
        #expect(ConfidenceScore.gitSourceScore(hasCommits: false, isDirty: true) == 50)
    }

    @Test("Git source score: 0 if clean")
    func gitSourceScore_clean() {
        #expect(ConfidenceScore.gitSourceScore(hasCommits: false, isDirty: false) == 0)
    }
}
