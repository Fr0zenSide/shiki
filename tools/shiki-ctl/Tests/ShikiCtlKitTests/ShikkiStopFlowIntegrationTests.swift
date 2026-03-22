import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("ShikkiEngine Stop Flow — BR-12, BR-14, BR-16, BR-18, BR-25, BR-55")
struct ShikkiStopFlowIntegrationTests {

    private func makeEngine(
        tmuxRunning: Bool = true
    ) throws -> (ShikkiEngine, MockDBSync, String) {
        let dir = NSTemporaryDirectory() + "shikki-stop-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = tmuxRunning
        let cpManager = CheckpointManager(directory: dir)
        let lockManager = LockfileManager(path: "\(dir)/shikki.pid")
        let dbSync = MockDBSync()

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

    private func makeCheckpoint() -> Checkpoint {
        Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .running,
            tmuxLayout: TmuxLayout(paneCount: 3, layoutString: "tiled"),
            sessionStats: SessionSnapshot(startedAt: Date().addingTimeInterval(-3600), branch: "main"),
            contextSnippet: "stop test",
            dbSynced: false
        )
    }

    private func makeTimer(
        escapeAtTick: Int? = nil
    ) -> (CountdownTimer, TickCollector, MockKeyReader) {
        let collector = TickCollector()
        let mockReader = MockKeyReader(escapeAtTick: escapeAtTick)
        let timer = CountdownTimer(
            isInteractive: escapeAtTick != nil,
            keyReader: mockReader,
            onTick: { remaining in
                collector.append(remaining)
                mockReader.setCurrentTick(remaining)
            },
            sleepDuration: .zero
        )
        return (timer, collector, mockReader)
    }

    // BR-12: RUNNING → save + countdown + cleanup
    @Test("Stop from RUNNING saves checkpoint and completes")
    func stop_fromRunning_savesAndCompletes() async throws {
        let (engine, dbSync, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }
        let (timer, collector, _) = makeTimer()

        let result = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 3, timer: timer)

        #expect(result == .stopped)
        #expect(collector.values == [3, 2, 1])
        #expect(engine.checkpointManager.exists()) // Checkpoint was saved
        #expect(dbSync.uploadCallCount == 1) // DB sync attempted
    }

    // BR-12: IDLE → no-op
    @Test("Stop when IDLE returns nothingRunning")
    func stop_whenIdle_isNoOp() async throws {
        let (engine, dbSync, dir) = try makeEngine(tmuxRunning: false)
        defer { cleanup(dir) }
        let (timer, _, _) = makeTimer()

        let result = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 3, timer: timer)

        #expect(result == .nothingRunning)
        #expect(dbSync.uploadCallCount == 0) // Never called
    }

    // BR-18: STOPPING → no-op
    @Test("Stop while already STOPPING returns alreadyStopping")
    func stop_whileAlreadyStopping_isNoOp() async throws {
        let dir = NSTemporaryDirectory() + "shikki-stop-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }

        let mockDetector = MockStateDetector(state: .stopping)
        let engine = ShikkiEngine(
            detector: mockDetector,
            checkpointManager: CheckpointManager(directory: dir),
            lockfileManager: LockfileManager(path: "\(dir)/shikki.pid"),
            dbSync: MockDBSync()
        )
        let (timer, _, _) = makeTimer()

        let result = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 3, timer: timer)
        #expect(result == .alreadyStopping)
    }

    // BR-25: Save order — local first, DB second (soft-fail)
    @Test("Stop saves local first, DB fails softly")
    func stop_dbFails_localSaved() async throws {
        let (engine, dbSync, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }
        dbSync.uploadResult = false // DB will fail
        let (timer, _, _) = makeTimer()

        let result = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 1, timer: timer)

        #expect(result == .stopped) // Still completes
        #expect(engine.checkpointManager.exists()) // Local saved
        #expect(dbSync.uploadCallCount == 1) // Attempted
    }

    // BR-16: Esc cancels → checkpoint preserved as resume point
    @Test("Esc during countdown cancels, checkpoint preserved")
    func stop_escCancels_checkpointPreserved() async throws {
        let (engine, _, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }
        let (timer, _, _) = makeTimer(escapeAtTick: 2)

        let result = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 3, timer: timer)

        #expect(result == .cancelled)
        #expect(engine.checkpointManager.exists()) // Checkpoint preserved for resume
    }

    // BR-14: --countdown 0 → immediate save + stop
    @Test("Countdown 0 stops immediately")
    func stop_countdownZero_stopsImmediately() async throws {
        let (engine, _, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }
        let (timer, collector, _) = makeTimer()

        let result = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 0, timer: timer)

        #expect(result == .stopped)
        #expect(collector.values.isEmpty) // No ticks — immediate
        #expect(engine.checkpointManager.exists()) // Still saved
    }

    // BR-55: Stop produces checkpoint that can be loaded for resume
    @Test("Checkpoint from stop can be loaded for resume")
    func stop_checkpoint_loadableForResume() async throws {
        let (engine, _, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }
        let (timer, _, _) = makeTimer()
        let cp = makeCheckpoint()

        _ = try await engine.stop(checkpoint: cp, countdown: 1, timer: timer)

        // Simulate next `shikki` invocation on idle (tmux killed)
        let env2 = MockEnvironmentChecker()
        env2.tmuxSessionRunning = false
        let detector2 = StateDetector(sessionName: "shikki", environment: env2, checkpointManager: engine.checkpointManager)
        let engine2 = ShikkiEngine(
            detector: detector2,
            checkpointManager: engine.checkpointManager,
            lockfileManager: engine.lockfileManager,
            dbSync: MockDBSync()
        )

        let action = try await engine2.dispatch()
        if case .resume(let loaded) = action {
            #expect(loaded.hostname == "test-host")
            #expect(loaded.contextSnippet == "stop test")
        } else {
            Issue.record("Expected .resume after stop, got \(action)")
        }
    }

    // BR-12: Lockfile released after stop
    @Test("Lockfile released after completed stop")
    func stop_releasesLockfile() async throws {
        let (engine, _, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }

        // Acquire lockfile first
        try engine.lockfileManager.acquire()
        #expect(engine.lockfileManager.isHeld())

        let (timer, _, _) = makeTimer()
        _ = try await engine.stop(checkpoint: makeCheckpoint(), countdown: 1, timer: timer)

        #expect(!engine.lockfileManager.isHeld()) // Released
    }
}
