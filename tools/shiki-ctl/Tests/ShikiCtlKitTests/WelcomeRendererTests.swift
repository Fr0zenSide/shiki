import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("WelcomeRenderer — BR-45 to BR-49")
struct WelcomeRendererTests {

    private let now = Date()

    private func makeCheckpoint(
        minutesAgo: Double = 30,
        durationMinutes: Double = 120,
        paneCount: Int = 3
    ) -> Checkpoint {
        Checkpoint(
            timestamp: now.addingTimeInterval(-minutesAgo * 60),
            hostname: "test-host",
            fsmState: .idle,
            tmuxLayout: TmuxLayout(paneCount: paneCount, layoutString: "tiled"),
            sessionStats: SessionSnapshot(
                startedAt: now.addingTimeInterval(-(minutesAgo + durationMinutes) * 60),
                branch: "feature/test"
            ),
            contextSnippet: "test",
            dbSynced: false
        )
    }

    // BR-49: Clean start — no message
    @Test("Clean start (nil checkpoint) returns nil")
    func cleanStart_showsNoWelcomeBackMessage() {
        let result = WelcomeRenderer.renderToString(checkpoint: nil, now: now)
        #expect(result == nil)
    }

    // BR-45: Resume shows "Welcome back"
    @Test("Resume shows 'Welcome back' message")
    func resume_showsWelcomeBackMessage() {
        let cp = makeCheckpoint()
        let result = WelcomeRenderer.renderToString(checkpoint: cp, now: now)
        #expect(result != nil)
        #expect(result!.contains("Welcome back"))
    }

    // BR-46: Shows pane count
    @Test("Resume shows pane count")
    func resume_showsPaneCount() {
        let cp = makeCheckpoint(paneCount: 5)
        let result = WelcomeRenderer.renderToString(checkpoint: cp, now: now)!
        #expect(result.contains("5 panes"))
    }

    // BR-46: Shows session duration
    @Test("Resume shows session duration")
    func resume_showsSessionDuration() {
        let cp = makeCheckpoint(durationMinutes: 150) // 2h 30m
        let result = WelcomeRenderer.renderToString(checkpoint: cp, now: now)!
        #expect(result.contains("2h 30m"))
    }

    // BR-47: Relative time — under 1 minute
    @Test("Relative time under 1 minute shows '<1m'")
    func relativeTime_underOneMinute() {
        let result = WelcomeRenderer.relativeTime(
            from: now.addingTimeInterval(-30), to: now
        )
        #expect(result == "<1m")
    }

    // BR-47: Minutes
    @Test("Relative time in minutes shows 'Xm'")
    func relativeTime_minutes() {
        let result = WelcomeRenderer.relativeTime(
            from: now.addingTimeInterval(-300), to: now
        )
        #expect(result == "5m")
    }

    // BR-47: Hours
    @Test("Relative time in hours shows 'Xh'")
    func relativeTime_hours() {
        let result = WelcomeRenderer.relativeTime(
            from: now.addingTimeInterval(-10800), to: now
        )
        #expect(result == "3h")
    }

    // BR-47: Days
    @Test("Relative time in days shows 'Xd'")
    func relativeTime_days() {
        let result = WelcomeRenderer.relativeTime(
            from: now.addingTimeInterval(-172800), to: now
        )
        #expect(result == "2d")
    }

    // BR-48: Staleness warning for >7d
    @Test("Checkpoint older than 7d shows staleness warning")
    func resume_checkpointOlderThan7d_showsStalenessWarning() {
        let cp = makeCheckpoint(minutesAgo: 60 * 24 * 10) // 10 days ago
        let result = WelcomeRenderer.renderToString(checkpoint: cp, now: now)!
        #expect(result.contains("outdated"))
    }

    // BR-48: No staleness warning for <7d
    @Test("Checkpoint under 7d shows no staleness warning")
    func resume_checkpointUnder7d_noStalenessWarning() {
        let cp = makeCheckpoint(minutesAgo: 60) // 1 hour ago
        let result = WelcomeRenderer.renderToString(checkpoint: cp, now: now)!
        #expect(!result.contains("outdated"))
    }

    // Nil tmuxLayout omits pane count
    @Test("Nil tmuxLayout omits pane count")
    func resume_nilLayout_omitsPaneCount() {
        let cp = Checkpoint(
            timestamp: now.addingTimeInterval(-1800),
            hostname: "test",
            fsmState: .idle,
            tmuxLayout: nil,
            sessionStats: nil,
            contextSnippet: nil,
            dbSynced: false
        )
        let result = WelcomeRenderer.renderToString(checkpoint: cp, now: now)!
        #expect(!result.contains("panes"))
    }
}
