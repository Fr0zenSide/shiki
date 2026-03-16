import Testing
@testable import ShikiCtlKit

@Suite("StartupRenderer")
struct StartupRendererTests {

    @Test("StartupDisplayData init stores all values")
    func displayDataInit() {
        let data = StartupDisplayData(
            version: "0.2.0",
            isHealthy: true,
            lastSessionTasks: [("maya", 3), ("wabisabi", 2)],
            upcomingTasks: [("maya", 5), ("flsh", 2)],
            sessionStats: [
                ProjectStats(name: "maya", insertions: 127, deletions: 43, commits: 3, filesChanged: 8),
            ],
            weeklyInsertions: 1247,
            weeklyDeletions: 892,
            weeklyProjectCount: 6,
            pendingDecisions: 5,
            staleCompanies: 0,
            spentToday: 12.50
        )

        #expect(data.version == "0.2.0")
        #expect(data.isHealthy == true)
        #expect(data.lastSessionTasks.count == 2)
        #expect(data.upcomingTasks.count == 2)
        #expect(data.sessionStats.count == 1)
        #expect(data.weeklyInsertions == 1247)
        #expect(data.weeklyDeletions == 892)
        #expect(data.weeklyProjectCount == 6)
        #expect(data.pendingDecisions == 5)
        #expect(data.staleCompanies == 0)
        #expect(data.spentToday == 12.50)
    }

    @Test("Render does not crash with empty data")
    func renderEmptyData() {
        let data = StartupDisplayData(
            version: "0.2.0",
            isHealthy: false,
            lastSessionTasks: [],
            upcomingTasks: [],
            sessionStats: [],
            weeklyInsertions: 0,
            weeklyDeletions: 0,
            weeklyProjectCount: 0,
            pendingDecisions: 0,
            staleCompanies: 0,
            spentToday: 0
        )
        // Should not crash
        StartupRenderer.render(data)
    }

    @Test("Render does not crash with full data")
    func renderFullData() {
        let data = StartupDisplayData(
            version: "0.2.0",
            isHealthy: true,
            lastSessionTasks: [("maya", 3), ("wabisabi", 2), ("brainy", 1)],
            upcomingTasks: [("maya", 5), ("flsh", 2)],
            sessionStats: [
                ProjectStats(name: "maya", insertions: 127, deletions: 43, commits: 3, filesChanged: 8),
                ProjectStats(name: "wabisabi", insertions: 89, deletions: 91, commits: 2, filesChanged: 4),
            ],
            weeklyInsertions: 1247,
            weeklyDeletions: 892,
            weeklyProjectCount: 6,
            pendingDecisions: 5,
            staleCompanies: 2,
            spentToday: 12.50
        )
        // Should not crash
        StartupRenderer.render(data)
    }
}
