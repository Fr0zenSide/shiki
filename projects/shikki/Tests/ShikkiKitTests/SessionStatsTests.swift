import Testing
@testable import ShikkiKit

@Suite("SessionStats")
struct SessionStatsTests {

    @Test("ProjectStats maturity: equal insertions and deletions is mature")
    func maturityEqual() {
        let stats = ProjectStats(name: "test", insertions: 100, deletions: 100, commits: 5, filesChanged: 10)
        #expect(stats.isMatureStage == true)
    }

    @Test("ProjectStats maturity: ratio 1.2 is still mature")
    func maturityUpperBound() {
        let stats = ProjectStats(name: "test", insertions: 120, deletions: 100, commits: 5, filesChanged: 10)
        #expect(stats.isMatureStage == true)
    }

    @Test("ProjectStats maturity: ratio 0.8 is still mature")
    func maturityLowerBound() {
        let stats = ProjectStats(name: "test", insertions: 80, deletions: 100, commits: 5, filesChanged: 10)
        #expect(stats.isMatureStage == true)
    }

    @Test("ProjectStats maturity: ratio 2.0 is not mature (growing)")
    func maturityGrowing() {
        let stats = ProjectStats(name: "test", insertions: 200, deletions: 100, commits: 5, filesChanged: 10)
        #expect(stats.isMatureStage == false)
    }

    @Test("ProjectStats maturity: zero deletions is not mature")
    func maturityZeroDeletions() {
        let stats = ProjectStats(name: "test", insertions: 100, deletions: 0, commits: 5, filesChanged: 10)
        #expect(stats.isMatureStage == false)
    }

    @Test("MockSessionStats tracks call counts")
    func mockTracksCalls() async throws {
        let mock = MockSessionStats()
        _ = await mock.computeStats(workspace: "/tmp", projects: ["test"])
        _ = await mock.computeStats(workspace: "/tmp", projects: ["test"])
        try mock.recordSessionEnd()

        #expect(mock.computeStatsCallCount == 2)
        #expect(mock.recordSessionEndCallCount == 1)
    }

    @Test("MockSessionStats returns stubbed summary")
    func mockReturnsStubbedSummary() async {
        let stubbed = SessionSummary(
            sinceSession: [ProjectStats(name: "maya", insertions: 50, deletions: 20, commits: 3, filesChanged: 5)],
            weeklyAggregate: [],
            lastSessionEnd: nil
        )
        let mock = MockSessionStats(stubbedSummary: stubbed)
        let result = await mock.computeStats(workspace: "/tmp", projects: ["maya"])

        #expect(result.sinceSession.count == 1)
        #expect(result.sinceSession.first?.name == "maya")
        #expect(result.sinceSession.first?.insertions == 50)
    }

    @Test("Real SessionStats: compute on non-git directory returns empty")
    func realStatsNonGitDir() async {
        let stats = SessionStats()
        let result = await stats.computeStats(workspace: "/tmp", projects: ["nonexistent-project"])
        #expect(result.sinceSession.isEmpty)
    }
}
