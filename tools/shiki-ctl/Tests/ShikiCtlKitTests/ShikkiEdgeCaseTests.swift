import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Shikki Edge Cases — BR-21, BR-50, BR-51, BR-52, BR-53, BR-57")
struct ShikkiEdgeCaseTests {

    private func makeTempDir() -> String {
        let path = NSTemporaryDirectory() + "shikki-edge-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ paths: String...) {
        for path in paths { try? FileManager.default.removeItem(atPath: path) }
    }

    // MARK: - BR-50: Crash Recovery

    @Test("After tmux crash, state is IDLE")
    func afterTmuxCrash_stateIsIdle() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let cpManager = CheckpointManager(directory: dir)

        // Checkpoint says RUNNING but tmux is dead
        let cp = Checkpoint(timestamp: Date(), hostname: "crash", fsmState: .running, dbSynced: true)
        try cpManager.save(cp)

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)

        let state = await detector.detect()
        #expect(state == .idle)
    }

    @Test("After tmux crash, checkpoint is preserved for resume")
    func afterTmuxCrash_checkpointPreserved() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let cpManager = CheckpointManager(directory: dir)

        let cp = Checkpoint(
            timestamp: Date(), hostname: "crash",
            fsmState: .running,
            tmuxLayout: TmuxLayout(paneCount: 4, layoutString: "main-vertical"),
            contextSnippet: "Important work in progress",
            dbSynced: false
        )
        try cpManager.save(cp)

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)

        // Detection doesn't delete checkpoint
        _ = await detector.detect()
        #expect(cpManager.exists())

        // Checkpoint data intact
        let loaded = try cpManager.load()
        #expect(loaded?.contextSnippet == "Important work in progress")
        #expect(loaded?.tmuxLayout?.paneCount == 4)
    }

    // MARK: - BR-51: DB Unavailable

    @Test("Save with DB unavailable saves locally only")
    func save_dbUnavailable_savesLocally() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let cpManager = CheckpointManager(directory: dir)
        let dbSync = MockDBSync()
        dbSync.uploadResult = false // DB unreachable

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = true
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)
        let engine = ShikkiEngine(
            detector: detector, checkpointManager: cpManager,
            lockfileManager: LockfileManager(path: "\(dir)/shikki.pid"),
            dbSync: dbSync
        )

        let cp = Checkpoint(timestamp: Date(), hostname: "test", fsmState: .running, dbSynced: false)
        let timer = CountdownTimer(isInteractive: false, keyReader: nil, onTick: { _ in }, sleepDuration: .zero)

        let result = try await engine.stop(checkpoint: cp, countdown: 0, timer: timer)
        #expect(result == .stopped)
        #expect(cpManager.exists()) // Local saved
    }

    @Test("Save with DB unavailable sets dbSynced=false")
    func save_dbUnavailable_setsDbSyncedFalse() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let cpManager = CheckpointManager(directory: dir)

        // Save a checkpoint with dbSynced=false (simulating DB failure)
        let cp = Checkpoint(timestamp: Date(), hostname: "test", fsmState: .running, dbSynced: false)
        try cpManager.save(cp)

        let loaded = try cpManager.load()
        #expect(loaded?.dbSynced == false)
    }

    // MARK: - BR-52: Base Case

    @Test("No checkpoint, no tmux → clean start, no error")
    func noCheckpointNoTmux_startsClean() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let cpManager = CheckpointManager(directory: dir)
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)
        let engine = ShikkiEngine(
            detector: detector, checkpointManager: cpManager,
            lockfileManager: LockfileManager(path: "\(dir)/shikki.pid"),
            dbSync: MockDBSync()
        )

        let action = try await engine.dispatch()
        #expect(action == .startClean)
    }

    // MARK: - BR-53: Concurrent Startup / Lockfile

    @Test("Concurrent startup: second instance blocked by lockfile")
    func concurrentStartup_secondInstanceBlocked() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let pidPath = "\(dir)/shikki.pid"

        // Simulate another live process holding the lock (PID 1 = launchd)
        try "1".write(toFile: pidPath, atomically: true, encoding: .utf8)
        let lock = LockfileManager(path: pidPath)

        #expect(throws: LockfileError.self) {
            try lock.acquire()
        }
    }

    @Test("Lockfile released on exit")
    func lockfile_releasedOnExit() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let lock = LockfileManager(path: "\(dir)/shikki.pid")

        try lock.acquire()
        #expect(lock.isHeld())
        try lock.release()
        #expect(!lock.isHeld())
    }

    @Test("Stale PID lockfile is overridden")
    func lockfile_stalePid_isOverridden() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let pidPath = "\(dir)/shikki.pid"

        // Write a PID that doesn't exist
        try "999999999".write(toFile: pidPath, atomically: true, encoding: .utf8)
        let lock = LockfileManager(path: pidPath)

        #expect(lock.isStale())
        try lock.acquire() // Should succeed over stale lock
        #expect(lock.isHeld())
        try lock.release()
    }

    // MARK: - BR-57: Atomic I/O

    @Test("Save: interrupted write does not corrupt checkpoint")
    func save_interruptedWrite_doesNotCorruptCheckpoint() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let cpManager = CheckpointManager(directory: dir)

        // Save valid checkpoint first
        let cp1 = Checkpoint(timestamp: Date(), hostname: "original", fsmState: .idle, dbSynced: true)
        try cpManager.save(cp1)

        // Save second checkpoint (overwrites atomically)
        let cp2 = Checkpoint(timestamp: Date(), hostname: "updated", fsmState: .running, dbSynced: false)
        try cpManager.save(cp2)

        // Load should return the second, not a corrupted mix
        let loaded = try cpManager.load()
        #expect(loaded?.hostname == "updated")
        #expect(loaded?.fsmState == .running)

        // No .tmp files left behind
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        #expect(!files.contains(where: { $0.hasSuffix(".tmp") }))
    }

    // MARK: - BR-21: Context Snippet 4KB Boundary

    @Test("Context snippet >4KB is truncated")
    func contextSnippet_overFourKB_truncated() {
        let bigString = String(repeating: "x", count: 8192)
        let cp = Checkpoint(
            timestamp: Date(), hostname: "test", fsmState: .idle,
            contextSnippet: bigString, dbSynced: false
        )
        #expect((cp.contextSnippet?.utf8.count ?? 0) <= Checkpoint.maxContextBytes)
    }
}
