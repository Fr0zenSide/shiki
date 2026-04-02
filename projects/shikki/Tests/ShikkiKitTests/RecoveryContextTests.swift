import Foundation
import Testing
@testable import ShikkiKit

// MARK: - ConfidenceScore Tests

@Suite("ConfidenceScore — BR-16 weighted confidence calculation")
struct ConfidenceScoreRecoveryTests {

    // MARK: - Weight constants

    @Test("Weights are DB 50%, checkpoint 30%, git 20%")
    func weightsAreCorrect() {
        #expect(ConfidenceScore.dbWeight == 0.50)
        #expect(ConfidenceScore.checkpointWeight == 0.30)
        #expect(ConfidenceScore.gitWeight == 0.20)
    }

    // MARK: - Overall calculation

    @Test("All sources at 100 produces overall 100")
    func allSourcesMax() {
        let score = ConfidenceScore(dbScore: 100, checkpointScore: 100, gitScore: 100)
        #expect(score.overall == 100)
    }

    @Test("All sources at 0 produces overall 0")
    func allSourcesZero() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 0, gitScore: 0)
        #expect(score.overall == 0)
    }

    @Test("Only DB available at 100 produces overall 50")
    func onlyDBAvailable() {
        let score = ConfidenceScore(dbScore: 100, checkpointScore: 0, gitScore: 0)
        #expect(score.overall == 50)
    }

    @Test("Only checkpoint available at 100 produces overall 30")
    func onlyCheckpointAvailable() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 100, gitScore: 0)
        #expect(score.overall == 30)
    }

    @Test("Only git available at 100 produces overall 20")
    func onlyGitAvailable() {
        let score = ConfidenceScore(dbScore: 0, checkpointScore: 0, gitScore: 100)
        #expect(score.overall == 20)
    }

    @Test("Weighted calculation: DB=70, checkpoint=100, git=50 rounds correctly")
    func weightedCalculationRounding() {
        // 70*0.5 + 100*0.3 + 50*0.2 = 35 + 30 + 10 = 75
        let score = ConfidenceScore(dbScore: 70, checkpointScore: 100, gitScore: 50)
        #expect(score.overall == 75)
    }

    @Test("computeOverall static matches init")
    func computeOverallMatchesInit() {
        let computed = ConfidenceScore.computeOverall(dbScore: 70, checkpointScore: 50, gitScore: 100)
        let score = ConfidenceScore(dbScore: 70, checkpointScore: 50, gitScore: 100)
        #expect(computed == score.overall)
    }

    @Test("Rounding: DB=33, checkpoint=33, git=33 rounds to 33")
    func roundingBehavior() {
        // 33*0.5 + 33*0.3 + 33*0.2 = 16.5 + 9.9 + 6.6 = 33.0
        let score = ConfidenceScore(dbScore: 33, checkpointScore: 33, gitScore: 33)
        #expect(score.overall == 33)
    }

    // MARK: - DB source score (BR-17)

    @Test("DB score: >10 events and available returns 100")
    func dbSourceScore_moreThan10Events() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 11, available: true) == 100)
        #expect(ConfidenceScore.dbSourceScore(eventCount: 50, available: true) == 100)
    }

    @Test("DB score: 1-10 events and available returns 70")
    func dbSourceScore_fewEvents() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 1, available: true) == 70)
        #expect(ConfidenceScore.dbSourceScore(eventCount: 10, available: true) == 70)
    }

    @Test("DB score: 0 events and available returns 0")
    func dbSourceScore_emptyDB() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 0, available: true) == 0)
    }

    @Test("DB score: unavailable returns 0 regardless of count")
    func dbSourceScore_unavailable() {
        #expect(ConfidenceScore.dbSourceScore(eventCount: 100, available: false) == 0)
        #expect(ConfidenceScore.dbSourceScore(eventCount: 0, available: false) == 0)
    }

    // MARK: - Checkpoint source score (BR-18)

    @Test("Checkpoint score: exists and within window returns 100")
    func checkpointSourceScore_freshCheckpoint() {
        #expect(ConfidenceScore.checkpointSourceScore(exists: true, withinWindow: true) == 100)
    }

    @Test("Checkpoint score: exists but stale returns 50")
    func checkpointSourceScore_staleCheckpoint() {
        #expect(ConfidenceScore.checkpointSourceScore(exists: true, withinWindow: false) == 50)
    }

    @Test("Checkpoint score: does not exist returns 0")
    func checkpointSourceScore_noCheckpoint() {
        #expect(ConfidenceScore.checkpointSourceScore(exists: false, withinWindow: true) == 0)
        #expect(ConfidenceScore.checkpointSourceScore(exists: false, withinWindow: false) == 0)
    }

    // MARK: - Git source score (BR-19)

    @Test("Git score: commits in window returns 100")
    func gitSourceScore_hasCommits() {
        #expect(ConfidenceScore.gitSourceScore(hasCommits: true, isDirty: false) == 100)
        #expect(ConfidenceScore.gitSourceScore(hasCommits: true, isDirty: true) == 100)
    }

    @Test("Git score: dirty but no commits returns 50")
    func gitSourceScore_dirty() {
        #expect(ConfidenceScore.gitSourceScore(hasCommits: false, isDirty: true) == 50)
    }

    @Test("Git score: clean and no commits returns 0")
    func gitSourceScore_clean() {
        #expect(ConfidenceScore.gitSourceScore(hasCommits: false, isDirty: false) == 0)
    }

    // MARK: - Codable

    @Test("ConfidenceScore is Codable round-trip")
    func codableRoundTrip() throws {
        let original = ConfidenceScore(dbScore: 70, checkpointScore: 100, gitScore: 50)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConfidenceScore.self, from: data)
        #expect(decoded == original)
        #expect(decoded.overall == original.overall)
    }
}

// MARK: - Staleness Tests

@Suite("Staleness — BR-20 time-based staleness computation")
struct StalenessRecoveryTests {

    @Test("Fresh: less than 1 hour")
    func fresh_lessThanOneHour() {
        let now = Date()
        let recent = now.addingTimeInterval(-30 * 60) // 30 minutes ago
        #expect(Staleness.from(lastActivity: recent, now: now) == .fresh)
    }

    @Test("Fresh: exactly 0 seconds ago")
    func fresh_justNow() {
        let now = Date()
        #expect(Staleness.from(lastActivity: now, now: now) == .fresh)
    }

    @Test("Fresh: 59 minutes ago")
    func fresh_boundary() {
        let now = Date()
        let activity = now.addingTimeInterval(-59 * 60)
        #expect(Staleness.from(lastActivity: activity, now: now) == .fresh)
    }

    @Test("Recent: 1 to 6 hours")
    func recent_oneToSixHours() {
        let now = Date()
        let oneHour = now.addingTimeInterval(-1 * 3600)
        let threeHours = now.addingTimeInterval(-3 * 3600)
        let fiveHours = now.addingTimeInterval(-5 * 3600)
        #expect(Staleness.from(lastActivity: oneHour, now: now) == .recent)
        #expect(Staleness.from(lastActivity: threeHours, now: now) == .recent)
        #expect(Staleness.from(lastActivity: fiveHours, now: now) == .recent)
    }

    @Test("Stale: 6 to 24 hours")
    func stale_sixTo24Hours() {
        let now = Date()
        let sixHours = now.addingTimeInterval(-6 * 3600)
        let twelveHours = now.addingTimeInterval(-12 * 3600)
        let twentyThreeHours = now.addingTimeInterval(-23 * 3600)
        #expect(Staleness.from(lastActivity: sixHours, now: now) == .stale)
        #expect(Staleness.from(lastActivity: twelveHours, now: now) == .stale)
        #expect(Staleness.from(lastActivity: twentyThreeHours, now: now) == .stale)
    }

    @Test("Ancient: more than 24 hours")
    func ancient_moreThan24Hours() {
        let now = Date()
        let twentyFourHours = now.addingTimeInterval(-24 * 3600)
        let twoDays = now.addingTimeInterval(-48 * 3600)
        let oneWeek = now.addingTimeInterval(-7 * 24 * 3600)
        #expect(Staleness.from(lastActivity: twentyFourHours, now: now) == .ancient)
        #expect(Staleness.from(lastActivity: twoDays, now: now) == .ancient)
        #expect(Staleness.from(lastActivity: oneWeek, now: now) == .ancient)
    }

    @Test("All staleness values are raw-string representable")
    func rawValues() {
        #expect(Staleness.fresh.rawValue == "fresh")
        #expect(Staleness.recent.rawValue == "recent")
        #expect(Staleness.stale.rawValue == "stale")
        #expect(Staleness.ancient.rawValue == "ancient")
    }
}
