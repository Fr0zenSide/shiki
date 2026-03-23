import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Concurrency & Crash Recovery — BR-50, BR-53")
struct ConcurrencyIntegrationTests {

    private func cleanup(_ paths: String...) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // BR-53: Second startup blocked by lockfile
    @Test("Second startup blocked by lockfile held by live process")
    func concurrentStartup_secondInstanceBlocked() throws {
        let dir = NSTemporaryDirectory() + "shikki-conc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }

        let pidPath = "\(dir)/shikki.pid"
        let lock1 = LockfileManager(path: pidPath)
        let lock2 = LockfileManager(path: pidPath)

        // First instance acquires
        try lock1.acquire()
        #expect(lock1.isHeld())

        // Second instance should fail (same PID = our process, so re-acquire succeeds)
        // To test real blocking, write a different live PID
        // PID 1 (launchd) is always alive
        try "1".write(toFile: pidPath, atomically: true, encoding: .utf8)

        #expect(throws: LockfileError.self) {
            try lock2.acquire()
        }

        // Cleanup
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    // BR-53: Stale PID lockfile overridden
    @Test("Stale PID lockfile is overridden by new startup")
    func lockfile_stalePid_isOverridden() throws {
        let dir = NSTemporaryDirectory() + "shikki-conc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }

        let pidPath = "\(dir)/shikki.pid"
        // Write a PID that doesn't exist
        try "999999999".write(toFile: pidPath, atomically: true, encoding: .utf8)

        let lock = LockfileManager(path: pidPath)
        #expect(lock.isStale())

        // Should be able to acquire over stale lock
        try lock.acquire()
        #expect(lock.isHeld())

        try lock.release()
    }

    // BR-50: Tmux crash → state IDLE, checkpoint preserved for resume
    @Test("After tmux crash: state is IDLE, checkpoint preserved, resume works")
    func afterTmuxCrash_stateIsIdle_checkpointPreserved() async throws {
        let dir = NSTemporaryDirectory() + "shikki-crash-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }

        let cpManager = CheckpointManager(directory: dir)
        let lockManager = LockfileManager(path: "\(dir)/shikki.pid")

        // Simulate: session was RUNNING, checkpoint was saved
        let cp = Checkpoint(
            timestamp: Date().addingTimeInterval(-600),
            hostname: "crash-host",
            fsmState: .running,
            tmuxLayout: TmuxLayout(paneCount: 4, layoutString: "main-vertical"),
            sessionStats: SessionSnapshot(startedAt: Date().addingTimeInterval(-7200), branch: "feature/crash"),
            contextSnippet: "Was working when tmux died",
            dbSynced: true
        )
        try cpManager.save(cp)

        // Simulate: tmux is now dead (crash)
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)
        let engine = ShikkiEngine(
            detector: detector,
            checkpointManager: cpManager,
            lockfileManager: lockManager,
            dbSync: MockDBSync()
        )

        // State should be IDLE (not RUNNING despite checkpoint saying .running)
        let action = try await engine.dispatch()

        // Should be resume (checkpoint exists)
        if case .resume(let loaded) = action {
            #expect(loaded.hostname == "crash-host")
            #expect(loaded.contextSnippet == "Was working when tmux died")
            #expect(loaded.tmuxLayout?.paneCount == 4)
        } else {
            Issue.record("Expected .resume after crash, got \(action)")
        }

        // Checkpoint still exists until confirmResume
        #expect(cpManager.exists())
    }
}
