import Foundation
import Testing
@testable import ShikkiKit

@Suite("Checkpoint model — BR-20, BR-21")
struct CheckpointTests {

    private func makeCheckpoint(
        contextSnippet: String? = "test context",
        dbSynced: Bool = false
    ) -> Checkpoint {
        Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .idle,
            tmuxLayout: TmuxLayout(paneCount: 3, layoutString: "tiled", paneLabels: ["editor", "shell", "logs"]),
            sessionStats: SessionSnapshot(startedAt: Date(), branch: "main", commitCount: 5, linesChanged: 120),
            contextSnippet: contextSnippet,
            dbSynced: dbSynced
        )
    }

    // BR-21: Schema fields
    @Test("Checkpoint contains version")
    func checkpoint_containsVersion() {
        let cp = makeCheckpoint()
        #expect(cp.version == Checkpoint.currentVersion)
    }

    @Test("Checkpoint contains timestamp")
    func checkpoint_containsTimestamp() {
        let cp = makeCheckpoint()
        #expect(cp.timestamp.timeIntervalSinceNow < 1)
    }

    @Test("Checkpoint contains fsmState")
    func checkpoint_containsFsmState() {
        let cp = makeCheckpoint()
        #expect(cp.fsmState == .idle)
    }

    @Test("Checkpoint contains tmuxLayout")
    func checkpoint_containsTmuxLayout() {
        let cp = makeCheckpoint()
        #expect(cp.tmuxLayout?.paneCount == 3)
    }

    @Test("Checkpoint contains sessionStats")
    func checkpoint_containsSessionStats() {
        let cp = makeCheckpoint()
        #expect(cp.sessionStats?.branch == "main")
        #expect(cp.sessionStats?.commitCount == 5)
    }

    @Test("Checkpoint contains contextSnippet")
    func checkpoint_containsContextSnippet() {
        let cp = makeCheckpoint(contextSnippet: "hello")
        #expect(cp.contextSnippet == "hello")
    }

    @Test("Checkpoint contains dbSynced")
    func checkpoint_containsDbSynced() {
        let cp = makeCheckpoint(dbSynced: true)
        #expect(cp.dbSynced == true)
    }

    // BR-21: contextSnippet max 4KB
    @Test("Context snippet is truncated to 4KB max")
    func checkpoint_contextSnippetMaxFourKB() {
        let bigString = String(repeating: "x", count: 8192)
        let cp = Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .running,
            tmuxLayout: nil,
            sessionStats: nil,
            contextSnippet: bigString,
            dbSynced: false
        )
        #expect((cp.contextSnippet?.utf8.count ?? 0) <= Checkpoint.maxContextBytes)
    }

    // Codable round-trip
    @Test("Checkpoint encodes and decodes via JSON")
    func checkpoint_codableRoundTrip() throws {
        let original = makeCheckpoint()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Checkpoint.self, from: data)

        #expect(decoded.version == original.version)
        #expect(decoded.hostname == original.hostname)
        #expect(decoded.fsmState == original.fsmState)
        #expect(decoded.tmuxLayout?.paneCount == original.tmuxLayout?.paneCount)
        #expect(decoded.dbSynced == original.dbSynced)
    }
}
