import Foundation
import Testing
@testable import ShikkiKit

@Suite("PreviousSessionSummary — Z2R Wave 4")
struct PreviousSessionSummaryTests {

    // MARK: - SessionRecord

    @Test("SessionRecord duration for completed session")
    func sessionRecordDuration() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_045_100) // 12h 31m later (45100s = 751m = 12h 31m)
        let session = SessionRecord(
            startedAt: start,
            endedAt: end,
            branch: "develop"
        )
        #expect(session.duration == 45100)
        #expect(session.formattedDuration == "12h 31m")
    }

    @Test("SessionRecord duration nil for active session")
    func sessionRecordActiveDuration() {
        let session = SessionRecord(startedAt: Date(), branch: "develop")
        #expect(session.duration == nil)
        #expect(session.formattedDuration == nil)
    }

    @Test("SessionRecord dateLabel format")
    func sessionRecordDateLabel() {
        // Use a fixed date: 2026-04-01
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2026, month: 4, day: 1, hour: 6, minute: 0)
        let date = calendar.date(from: components)!
        let session = SessionRecord(startedAt: date, branch: "develop")
        #expect(session.dateLabel.hasPrefix("shikki-2026"))
    }

    @Test("SessionRecord formatDuration: minutes only")
    func formatDurationMinutes() {
        #expect(SessionRecord.formatDuration(300) == "5m")
        #expect(SessionRecord.formatDuration(0) == "0m")
        #expect(SessionRecord.formatDuration(59) == "0m")
    }

    @Test("SessionRecord formatDuration: hours and minutes")
    func formatDurationHoursMinutes() {
        #expect(SessionRecord.formatDuration(3600) == "1h 0m")
        #expect(SessionRecord.formatDuration(7500) == "2h 5m")
        #expect(SessionRecord.formatDuration(86400) == "24h 0m")
    }

    // MARK: - PreviousSessionSummary: format

    @Test("Format session with specs and tests")
    func formatSessionWithActivity() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_045_100) // 12h 31m
        let session = SessionRecord(
            startedAt: start,
            endedAt: end,
            specsDelivered: 30,
            testsGreen: 1882,
            branchesMerged: 4
        )

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSession(session)

        #expect(result.contains("30 specs"))
        #expect(result.contains("1.9k tests"))
        #expect(result.contains("4 branches merged"))
        #expect(result.contains("12h 31m"))
    }

    @Test("Format session with no activity")
    func formatSessionNoActivity() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let session = SessionRecord(startedAt: start, endedAt: end)

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSession(session)

        #expect(result.contains("no recorded activity"))
    }

    @Test("Format session with singular counts")
    func formatSessionSingular() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let session = SessionRecord(
            startedAt: start,
            endedAt: end,
            specsDelivered: 1,
            testsGreen: 1,
            branchesMerged: 1
        )

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSession(session)

        #expect(result.contains("1 spec,"))
        #expect(result.contains("1 test,"))
        #expect(result.contains("1 branch merged"))
    }

    // MARK: - Last Session Summary

    @Test("Last session summary returns nil when no sessions")
    func lastSessionNone() {
        let storage = MockSessionStorage(sessions: [])
        let summary = PreviousSessionSummary(storage: storage)
        #expect(summary.lastSessionSummary() == nil)
    }

    @Test("Last session summary returns formatted string")
    func lastSessionExists() {
        let session = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_003_600),
            specsDelivered: 5,
            testsGreen: 200
        )
        let storage = MockSessionStorage(sessions: [session])
        let summary = PreviousSessionSummary(storage: storage)
        let result = summary.lastSessionSummary()

        #expect(result != nil)
        #expect(result!.contains("5 specs"))
        #expect(result!.contains("200 tests"))
    }

    // MARK: - Render Last Session

    @Test("Render last session: empty when no sessions")
    func renderLastSessionEmpty() {
        let storage = MockSessionStorage(sessions: [])
        let summary = PreviousSessionSummary(storage: storage)
        #expect(summary.renderLastSession() == "")
    }

    @Test("Render last session includes ANSI dim")
    func renderLastSessionANSI() {
        let session = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_003_600),
            specsDelivered: 3
        )
        let storage = MockSessionStorage(sessions: [session])
        let summary = PreviousSessionSummary(storage: storage)
        let result = summary.renderLastSession()

        #expect(result.contains("\u{1B}[2m")) // dim
        #expect(result.contains("3 specs"))
    }

    // MARK: - Session Overview (for shikki session command)

    @Test("Session overview includes all fields")
    func sessionOverview() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_007_200) // exactly 2h
        let session = SessionRecord(
            startedAt: start,
            endedAt: end,
            specsDelivered: 30,
            testsGreen: 1882,
            branchesMerged: 4,
            pendingSpecs: 3,
            pendingReviews: 2
        )

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSessionOverview(session, now: end)

        #expect(result.contains("Session:"))
        #expect(result.contains("Started:"))
        #expect(result.contains("Duration: 2h 0m"))
        #expect(result.contains("Specs delivered: 30"))
        #expect(result.contains("1.9k green"))
        #expect(result.contains("Branches merged: 4"))
        #expect(result.contains("Pending:"))
        #expect(result.contains("3 specs awaiting review"))
        #expect(result.contains("2 reviews pending"))
    }

    @Test("Session overview without pending items omits pending section")
    func sessionOverviewNoPending() {
        let session = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_003_600)
        )

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSessionOverview(session)

        #expect(!result.contains("Pending:"))
    }

    @Test("Session overview for active session shows elapsed time")
    func sessionOverviewActive() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = Date(timeIntervalSince1970: 1_007_200) // 2h later
        let session = SessionRecord(startedAt: start)

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSessionOverview(session, now: now)

        #expect(result.contains("2h 0m"))
    }

    // MARK: - Session History

    @Test("Session history: empty list")
    func sessionHistoryEmpty() {
        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSessionHistory([])
        #expect(result.contains("No session history"))
    }

    @Test("Session history: multiple sessions")
    func sessionHistoryMultiple() {
        let sessions = [
            SessionRecord(
                startedAt: Date(timeIntervalSince1970: 1_045_500),
                endedAt: Date(timeIntervalSince1970: 1_049_100),
                specsDelivered: 5,
                testsGreen: 100,
                branchesMerged: 2
            ),
            SessionRecord(
                startedAt: Date(timeIntervalSince1970: 1_000_000),
                endedAt: Date(timeIntervalSince1970: 1_003_600),
                specsDelivered: 3,
                testsGreen: 50
            ),
        ]

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSessionHistory(sessions)

        // First session gets filled circle, second gets empty
        #expect(result.contains("\u{25CF}")) // filled circle
        #expect(result.contains("\u{25CB}")) // empty circle
        #expect(result.contains("5 specs"))
        #expect(result.contains("3 specs"))
    }

    @Test("Session history: singular pending counts")
    func sessionHistorySingular() {
        let sessions = [
            SessionRecord(
                startedAt: Date(timeIntervalSince1970: 1_000_000),
                endedAt: Date(timeIntervalSince1970: 1_003_600),
                specsDelivered: 1,
                branchesMerged: 1
            ),
        ]

        let summary = PreviousSessionSummary(storage: MockSessionStorage())
        let result = summary.formatSessionHistory(sessions)
        #expect(result.contains("1 specs"))
        #expect(result.contains("1 merged"))
    }

    // MARK: - File Session Storage

    @Test("FileSessionStorage saves and loads session")
    func fileStorageSaveLoad() throws {
        let tempDir = NSTemporaryDirectory() + "shikki-sessions-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let storage = FileSessionStorage(directory: tempDir)
        let session = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_003_600),
            specsDelivered: 5,
            testsGreen: 100
        )

        try storage.saveSession(session)
        let loaded = try storage.loadSessions()

        #expect(loaded.count == 1)
        #expect(loaded.first?.specsDelivered == 5)
        #expect(loaded.first?.testsGreen == 100)
    }

    @Test("FileSessionStorage returns empty for nonexistent directory")
    func fileStorageEmpty() throws {
        let storage = FileSessionStorage(directory: "/tmp/nonexistent-\(UUID().uuidString)")
        let sessions = try storage.loadSessions()
        #expect(sessions.isEmpty)
    }

    @Test("FileSessionStorage lastSession returns most recent")
    func fileStorageLastSession() throws {
        let tempDir = NSTemporaryDirectory() + "shikki-sessions-last-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let storage = FileSessionStorage(directory: tempDir)
        let older = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_003_600),
            specsDelivered: 3
        )
        let newer = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_100_000),
            endedAt: Date(timeIntervalSince1970: 1_103_600),
            specsDelivered: 7
        )

        try storage.saveSession(older)
        try storage.saveSession(newer)

        let last = try storage.lastSession()
        #expect(last?.specsDelivered == 7)
    }

    @Test("FileSessionStorage recentSessions limits count")
    func fileStorageRecent() throws {
        let tempDir = NSTemporaryDirectory() + "shikki-sessions-recent-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let storage = FileSessionStorage(directory: tempDir)

        for i in 0..<5 {
            let session = SessionRecord(
                startedAt: Date(timeIntervalSince1970: Double(1_000_000 + i * 100_000)),
                endedAt: Date(timeIntervalSince1970: Double(1_003_600 + i * 100_000)),
                specsDelivered: i
            )
            try storage.saveSession(session)
        }

        let recent = try storage.recentSessions(count: 3)
        #expect(recent.count == 3)
    }

    // MARK: - Mock Session Storage

    @Test("MockSessionStorage tracks save calls")
    func mockStorageSave() throws {
        let mock = MockSessionStorage()
        let session = SessionRecord(startedAt: Date(), specsDelivered: 1)

        try mock.saveSession(session)
        try mock.saveSession(session)

        #expect(mock.saveCallCount == 2)
        #expect(mock.sessions.count == 2)
    }

    @Test("MockSessionStorage returns sessions sorted by date")
    func mockStorageSorted() throws {
        let older = SessionRecord(startedAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = SessionRecord(startedAt: Date(timeIntervalSince1970: 2_000_000))
        let mock = MockSessionStorage(sessions: [older, newer])

        let loaded = try mock.loadSessions()
        #expect(loaded.first?.startedAt.timeIntervalSince1970 == 2_000_000)
    }
}
