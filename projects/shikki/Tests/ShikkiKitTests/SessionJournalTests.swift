import Foundation
import Testing
@testable import ShikkiKit

@Suite("SessionJournal append-only journal")
struct SessionJournalTests {

    /// Creates a temp directory for journal tests and returns (journal, basePath).
    private func makeJournal() -> (SessionJournal, String) {
        let base = NSTemporaryDirectory() + "shiki-journal-test-\(UUID().uuidString)"
        let journal = SessionJournal(basePath: base)
        return (journal, base)
    }

    @Test("Checkpoint appends a JSONL line")
    func appendWritesJsonlLine() async throws {
        let (journal, base) = makeJournal()
        let checkpoint = SessionCheckpoint(
            sessionId: "s-1", state: .working,
            reason: .stateTransition, metadata: nil
        )
        try await journal.checkpoint(checkpoint)

        let filePath = "\(base)/s-1.jsonl"
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 1)

        // Verify it's valid JSON
        let data = Data(lines[0].utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionCheckpoint.self, from: data)
        #expect(decoded.sessionId == "s-1")
        #expect(decoded.state == .working)

        try? FileManager.default.removeItem(atPath: base)
    }

    @Test("Load checkpoints returns ordered list")
    func loadReturnsOrderedList() async throws {
        let (journal, base) = makeJournal()

        let c1 = SessionCheckpoint(sessionId: "s-2", state: .spawning, reason: .stateTransition, metadata: nil)
        let c2 = SessionCheckpoint(sessionId: "s-2", state: .working, reason: .stateTransition, metadata: nil)
        let c3 = SessionCheckpoint(sessionId: "s-2", state: .prOpen, reason: .stateTransition, metadata: nil)

        try await journal.checkpoint(c1)
        try await journal.checkpoint(c2)
        try await journal.checkpoint(c3)

        let loaded = try await journal.loadCheckpoints(sessionId: "s-2")
        #expect(loaded.count == 3)
        #expect(loaded[0].state == .spawning)
        #expect(loaded[1].state == .working)
        #expect(loaded[2].state == .prOpen)

        try? FileManager.default.removeItem(atPath: base)
    }

    @Test("Prune removes files older than threshold")
    func pruneRemovesOldFiles() async throws {
        let (journal, base) = makeJournal()
        let fm = FileManager.default

        // Create a fake old file
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
        let oldFile = "\(base)/old-session.jsonl"
        fm.createFile(atPath: oldFile, contents: Data("{}".utf8))

        // Set modification date to 15 days ago
        let oldDate = Date().addingTimeInterval(-15 * 24 * 3600)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFile)

        // Create a recent file
        let recentCheckpoint = SessionCheckpoint(sessionId: "recent", state: .working, reason: .periodic, metadata: nil)
        try await journal.checkpoint(recentCheckpoint)

        // Prune with 14-day threshold
        let pruned = try await journal.prune(olderThan: 14 * 24 * 3600)
        #expect(pruned == 1)
        #expect(!fm.fileExists(atPath: oldFile))
        #expect(fm.fileExists(atPath: "\(base)/recent.jsonl"))

        try? fm.removeItem(atPath: base)
    }

    @Test("Prune keeps recent files")
    func pruneKeepsRecentFiles() async throws {
        let (journal, base) = makeJournal()

        let c1 = SessionCheckpoint(sessionId: "keep-me", state: .working, reason: .periodic, metadata: nil)
        try await journal.checkpoint(c1)

        let pruned = try await journal.prune(olderThan: 14 * 24 * 3600)
        #expect(pruned == 0)
        #expect(FileManager.default.fileExists(atPath: "\(base)/keep-me.jsonl"))

        try? FileManager.default.removeItem(atPath: base)
    }

    @Test("Empty journal returns empty checkpoints")
    func emptyJournalReturnsEmpty() async throws {
        let (journal, base) = makeJournal()

        let loaded = try await journal.loadCheckpoints(sessionId: "nonexistent")
        #expect(loaded.isEmpty)

        try? FileManager.default.removeItem(atPath: base)
    }

    @Test("Coalesced checkpoint debounces rapid writes")
    func coalescedDebounce() async throws {
        let (journal, base) = makeJournal()

        // Fire 3 rapid checkpoints with very short debounce
        for i in 0..<3 {
            let c = SessionCheckpoint(
                sessionId: "debounce",
                state: i < 2 ? .working : .prOpen,
                reason: .stateTransition, metadata: nil
            )
            await journal.coalescedCheckpoint(c, debounce: .milliseconds(50))
        }

        // Wait for debounce to flush
        try await Task.sleep(for: .milliseconds(200))

        let loaded = try await journal.loadCheckpoints(sessionId: "debounce")
        // Should have fewer than 3 writes due to debounce (typically 1)
        #expect(loaded.count <= 2)
        // The last state should be the final one
        if let last = loaded.last {
            #expect(last.state == .prOpen)
        }

        try? FileManager.default.removeItem(atPath: base)
    }
}
