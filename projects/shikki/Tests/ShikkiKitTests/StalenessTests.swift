import Foundation
import Testing
@testable import ShikkiKit

@Suite("Staleness — BR-20, BR-21")
struct StalenessTests {

    @Test("Fresh — under one hour")
    func fresh_underOneHour() {
        let now = Date()
        let activity = now.addingTimeInterval(-30 * 60) // 30 min ago
        #expect(Staleness.from(lastActivity: activity, now: now) == .fresh)
    }

    @Test("Recent — one to six hours")
    func recent_oneToSixHours() {
        let now = Date()
        let activity = now.addingTimeInterval(-3 * 3600) // 3h ago
        #expect(Staleness.from(lastActivity: activity, now: now) == .recent)
    }

    @Test("Stale — six to twenty-four hours")
    func stale_sixToTwentyFourHours() {
        let now = Date()
        let activity = now.addingTimeInterval(-12 * 3600) // 12h ago
        #expect(Staleness.from(lastActivity: activity, now: now) == .stale)
    }

    @Test("Ancient — over twenty-four hours")
    func ancient_overTwentyFourHours() {
        let now = Date()
        let activity = now.addingTimeInterval(-48 * 3600) // 48h ago
        #expect(Staleness.from(lastActivity: activity, now: now) == .ancient)
    }

    @Test("Boundary: exactly 1 hour is recent")
    func boundary_exactlyOneHour() {
        let now = Date()
        let activity = now.addingTimeInterval(-3600)
        #expect(Staleness.from(lastActivity: activity, now: now) == .recent)
    }

    @Test("Boundary: exactly 6 hours is stale")
    func boundary_exactlySixHours() {
        let now = Date()
        let activity = now.addingTimeInterval(-6 * 3600)
        #expect(Staleness.from(lastActivity: activity, now: now) == .stale)
    }

    @Test("Boundary: exactly 24 hours is ancient")
    func boundary_exactlyTwentyFourHours() {
        let now = Date()
        let activity = now.addingTimeInterval(-24 * 3600)
        #expect(Staleness.from(lastActivity: activity, now: now) == .ancient)
    }

    @Test("Very recent activity is fresh")
    func veryRecent_isFresh() {
        let now = Date()
        let activity = now.addingTimeInterval(-10) // 10 seconds ago
        #expect(Staleness.from(lastActivity: activity, now: now) == .fresh)
    }
}
