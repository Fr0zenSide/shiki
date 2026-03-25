import Foundation
import Testing
@testable import ShikkiKit

@Suite("HybridPersistence — BR-25, BR-26, BR-27, BR-29, BR-51")
struct HybridPersistenceIntegrationTests {

    private func makeEngine(
        dbCheckpoint: Checkpoint? = nil,
        dbUploadSucceeds: Bool = true
    ) throws -> (ShikkiEngine, MockDBSync, String) {
        let dir = NSTemporaryDirectory() + "shikki-hybrid-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let env = MockEnvironmentChecker()
        let cpManager = CheckpointManager(directory: dir)
        let lockManager = LockfileManager(path: "\(dir)/shikki.pid")
        let dbSync = MockDBSync()
        dbSync.downloadResult = dbCheckpoint
        dbSync.uploadResult = dbUploadSucceeds
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)

        let engine = ShikkiEngine(
            detector: detector,
            checkpointManager: cpManager,
            lockfileManager: lockManager,
            dbSync: dbSync
        )
        return (engine, dbSync, dir)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeCheckpoint(hostname: String = "test-host", context: String = "test") -> Checkpoint {
        Checkpoint(
            timestamp: Date(),
            hostname: hostname,
            fsmState: .idle,
            tmuxLayout: TmuxLayout(paneCount: 2, layoutString: "tiled"),
            sessionStats: nil,
            contextSnippet: context,
            dbSynced: false
        )
    }

    // BR-26: Resume loads local first
    @Test("Resume loads local checkpoint first")
    func resume_loadsLocalCheckpointFirst() async throws {
        let localCp = makeCheckpoint(context: "local-data")
        let remoteCp = makeCheckpoint(context: "remote-data")
        let (engine, dbSync, dir) = try makeEngine(dbCheckpoint: remoteCp)
        defer { cleanup(dir) }

        // Save local checkpoint
        try engine.checkpointManager.save(localCp)

        let loaded = try await engine.loadCheckpointHybrid(hostname: "test-host")
        #expect(loaded?.contextSnippet == "local-data") // Local wins
        #expect(dbSync.downloadCallCount == 0) // DB never queried
    }

    // BR-26: Fallback to DB when no local
    @Test("Resume falls back to DB when no local checkpoint")
    func resume_fallsBackToDbByHostname_whenNoLocal() async throws {
        let remoteCp = makeCheckpoint(context: "from-db")
        let (engine, dbSync, dir) = try makeEngine(dbCheckpoint: remoteCp)
        defer { cleanup(dir) }

        let loaded = try await engine.loadCheckpointHybrid(hostname: "test-host")
        #expect(loaded?.contextSnippet == "from-db")
        #expect(dbSync.downloadCallCount == 1)
        // DB result should be written to local for next time
        #expect(engine.checkpointManager.exists())
    }

    // BR-27: Local wins when both exist and differ
    @Test("Local checkpoint wins when both exist and differ")
    func resume_localWins_whenBothExistAndDiffer() async throws {
        let localCp = makeCheckpoint(context: "local-version")
        let remoteCp = makeCheckpoint(context: "remote-version")
        let (engine, _, dir) = try makeEngine(dbCheckpoint: remoteCp)
        defer { cleanup(dir) }

        try engine.checkpointManager.save(localCp)

        let loaded = try await engine.loadCheckpointHybrid(hostname: "test-host")
        #expect(loaded?.contextSnippet == "local-version")
    }

    // BR-29: Cold start — no local, no DB → nil, no error
    @Test("Cold start with no DB and no local returns nil")
    func coldStart_noDbNoCheckpoint_startsClean() async throws {
        let (engine, _, dir) = try makeEngine(dbCheckpoint: nil)
        defer { cleanup(dir) }

        let loaded = try await engine.loadCheckpointHybrid(hostname: "new-host")
        #expect(loaded == nil)
    }

    // BR-51: DB unavailable → local-only save succeeds
    @Test("DB unavailable saves locally with dbSynced=false")
    func save_dbUnavailable_savesLocally() async throws {
        let (engine, _, dir) = try makeEngine(dbUploadSucceeds: false)
        defer { cleanup(dir) }

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = true
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: engine.checkpointManager)
        let engineWithRunning = ShikkiEngine(
            detector: detector,
            checkpointManager: engine.checkpointManager,
            lockfileManager: engine.lockfileManager,
            dbSync: engine.dbSync
        )

        let timer = CountdownTimer(isInteractive: false, keyReader: nil, onTick: { _ in }, sleepDuration: .zero)
        let cp = makeCheckpoint()

        let result = try await engineWithRunning.stop(checkpoint: cp, countdown: 0, timer: timer)
        #expect(result == .stopped)
        #expect(engine.checkpointManager.exists()) // Local saved despite DB failure
    }
}
