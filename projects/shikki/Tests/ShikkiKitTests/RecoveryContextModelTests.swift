import Foundation
import Testing
@testable import ShikkiKit

@Suite("RecoveryContext models — BR-03, K1")
struct RecoveryContextModelTests {

    @Test("RecoveredItem carries provenance")
    func recoveredItem_hasProvenance() {
        let item = RecoveredItem(
            timestamp: Date(),
            provenance: .db,
            kind: .event,
            summary: "session started"
        )
        #expect(item.provenance == .db)
        #expect(item.kind == .event)
        #expect(item.summary == "session started")
    }

    @Test("RecoveredItem detail is nil by default")
    func recoveredItem_detailIsNilByDefault() {
        let item = RecoveredItem(
            timestamp: Date(),
            provenance: .git,
            kind: .commit,
            summary: "fix: update parser"
        )
        #expect(item.detail == nil)
    }

    @Test("RecoveredItem with detail")
    func recoveredItem_withDetail() {
        let item = RecoveredItem(
            timestamp: Date(),
            provenance: .checkpoint,
            kind: .checkpoint,
            summary: "FSM state: running",
            detail: "branch: develop, commits: 5"
        )
        #expect(item.detail != nil)
    }

    @Test("WorkspaceSnapshot never contains file contents")
    func workspaceSnapshot_noFileContents() {
        let snapshot = WorkspaceSnapshot(
            branch: "main",
            recentCommits: [
                CommitInfo(hash: "abc123", message: "fix bug", author: "dev", timestamp: Date()),
            ],
            modifiedFiles: ["Sources/Foo.swift"],
            untrackedFiles: ["new.txt"]
        )
        #expect(snapshot.branch == "main")
        #expect(snapshot.recentCommits.count == 1)
        #expect(snapshot.modifiedFiles.count == 1)
        // modifiedFiles contains paths only, no contents
        #expect(snapshot.modifiedFiles[0] == "Sources/Foo.swift")
    }

    @Test("TimeWindow lookback creates correct window")
    func timeWindow_lookback() {
        let now = Date()
        let window = TimeWindow.lookback(seconds: 7200, from: now)
        #expect(window.until == now)
        #expect(abs(window.duration - 7200) < 0.001)
    }

    @Test("TimeWindow duration is correct")
    func timeWindow_duration() {
        let now = Date()
        let since = now.addingTimeInterval(-3600)
        let window = TimeWindow(since: since, until: now)
        #expect(abs(window.duration - 3600) < 0.001)
    }

    @Test("SourceResult captures error message")
    func sourceResult_capturesError() {
        let result = SourceResult(
            name: "db",
            status: .unavailable,
            itemCount: 0,
            score: 0,
            error: "Connection refused"
        )
        #expect(result.error == "Connection refused")
        #expect(result.status == .unavailable)
    }

    @Test("RecoveryContext is Codable")
    func recoveryContext_isCodable() throws {
        let now = Date()
        let context = RecoveryContext(
            recoveredAt: now,
            timeWindow: TimeWindow.lookback(seconds: 7200, from: now),
            confidence: ConfidenceScore(dbScore: 70, checkpointScore: 100, gitScore: 50),
            staleness: .fresh,
            sources: [
                SourceResult(name: "db", status: .available, itemCount: 5, score: 70),
            ],
            timeline: [
                RecoveredItem(timestamp: now, provenance: .db, kind: .event, summary: "test"),
            ],
            workspace: WorkspaceSnapshot(branch: "main"),
            errors: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecoveryContext.self, from: data)
        #expect(decoded.confidence.overall == context.confidence.overall)
        #expect(decoded.staleness == .fresh)
        #expect(decoded.sources.count == 1)
        #expect(decoded.timeline.count == 1)
    }

    @Test("All provenance values are representable")
    func provenance_allValues() {
        let values: [Provenance] = [.db, .checkpoint, .git, .inferred]
        #expect(values.count == 4)
    }

    @Test("All item kinds are representable")
    func itemKind_allValues() {
        let kinds: [ItemKind] = [.event, .commit, .checkpoint, .decision, .file]
        #expect(kinds.count == 5)
    }

    @Test("All source statuses are representable")
    func sourceStatus_allValues() {
        let statuses: [SourceStatus] = [.available, .partial, .corrupted, .unavailable]
        #expect(statuses.count == 4)
    }
}
