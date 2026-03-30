import Foundation
import Testing
@testable import ShikkiKit

@Suite("CheckpointManager legacy migration — BR-24, BR-35")
struct CheckpointMigrationTests {

    private func makeTempDir(_ label: String = "shikki") -> String {
        let path = NSTemporaryDirectory() + "\(label)-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ paths: String...) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Write a legacy PausedSession JSON file to simulate ~/.shiki/sessions/*.json
    private func writeLegacyPausedSession(to dir: String, sessionId: String = "abc-2026-03-20") throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let session = PausedSession(
            sessionId: sessionId,
            pausedAt: Date().addingTimeInterval(-3600),
            branch: "feature/test",
            summary: "Working on migration",
            activeTasks: ["task-1"],
            pendingPRs: [42],
            decisions: ["use new schema"],
            nextAction: "continue migration",
            workspaceRoot: "/tmp/workspace"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(session)
        let filePath = "\(dir)/\(sessionId).json"
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    /// Write a legacy SessionJournal JSONL file to simulate ~/.shiki/journal/*.jsonl
    private func writeLegacyJournal(to dir: String, sessionId: String = "s-1") throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let checkpoint = SessionCheckpoint(
            sessionId: sessionId,
            state: .working,
            reason: .stateTransition,
            metadata: ["branch": "feature/test"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)
        let line = String(data: data, encoding: .utf8)! + "\n"
        let filePath = "\(dir)/\(sessionId).jsonl"
        try line.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // BR-24: Convert PausedSessionManager data
    @Test("Migration converts PausedSession data to new checkpoint")
    func migrate_convertsPausedSessionManagerData() throws {
        let shikkiDir = makeTempDir("shikki-migrate")
        let legacySessions = makeTempDir("legacy-sessions")
        let legacyJournal = makeTempDir("legacy-journal")
        defer { cleanup(shikkiDir, legacySessions, legacyJournal) }

        try writeLegacyPausedSession(to: legacySessions)

        let manager = CheckpointManager(directory: shikkiDir)
        try manager.migrateLegacy(
            legacySessionsDir: legacySessions,
            legacyJournalDir: legacyJournal
        )

        let cp = try manager.load()
        #expect(cp != nil)
        #expect(cp?.fsmState == .idle) // Paused session → idle state
        #expect(cp?.sessionStats?.branch == "feature/test")
        #expect(cp?.contextSnippet?.contains("Working on migration") == true)
    }

    // BR-24: Convert SessionJournal data
    @Test("Migration converts SessionJournal data to new checkpoint")
    func migrate_convertsSessionJournalData() throws {
        let shikkiDir = makeTempDir("shikki-migrate")
        let legacySessions = makeTempDir("legacy-sessions")
        let legacyJournal = makeTempDir("legacy-journal")
        defer { cleanup(shikkiDir, legacySessions, legacyJournal) }

        try writeLegacyJournal(to: legacyJournal)

        let manager = CheckpointManager(directory: shikkiDir)
        try manager.migrateLegacy(
            legacySessionsDir: legacySessions,
            legacyJournalDir: legacyJournal
        )

        let cp = try manager.load()
        #expect(cp != nil)
        #expect(cp?.fsmState == .idle)
    }

    // BR-24: Skip when no legacy data
    @Test("Migration skips when no legacy data exists")
    func migrate_skipsWhenNoLegacyData() throws {
        let shikkiDir = makeTempDir("shikki-migrate")
        defer { cleanup(shikkiDir) }

        let manager = CheckpointManager(directory: shikkiDir)
        // Use non-existent paths
        try manager.migrateLegacy(
            legacySessionsDir: "/tmp/nonexistent-sessions-\(UUID())",
            legacyJournalDir: "/tmp/nonexistent-journal-\(UUID())"
        )

        #expect(manager.exists() == false)
    }

    // Idempotent — skips if .migrated/ exists
    @Test("Migration is idempotent — skips if already migrated")
    func migrate_isIdempotent() throws {
        let shikkiDir = makeTempDir("shikki-migrate")
        let legacySessions = makeTempDir("legacy-sessions")
        let legacyJournal = makeTempDir("legacy-journal")
        defer { cleanup(shikkiDir, legacySessions + ".migrated", legacyJournal + ".migrated") }

        try writeLegacyPausedSession(to: legacySessions)

        let manager = CheckpointManager(directory: shikkiDir)

        // First migration
        try manager.migrateLegacy(
            legacySessionsDir: legacySessions,
            legacyJournalDir: legacyJournal
        )
        let cp1 = try manager.load()

        // Second migration should be a no-op (dirs already renamed to .migrated)
        try manager.migrateLegacy(
            legacySessionsDir: legacySessions,
            legacyJournalDir: legacyJournal
        )
        let cp2 = try manager.load()

        #expect(cp1?.hostname == cp2?.hostname)
    }
}
