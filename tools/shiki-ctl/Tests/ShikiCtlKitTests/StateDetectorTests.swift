import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("StateDetector — BR-02, BR-03, BR-07, BR-50")
struct StateDetectorTests {

    private func makeTempDir() -> String {
        let path = NSTemporaryDirectory() + "shikki-detect-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // BR-02: IDLE = no tmux + no checkpoint
    @Test("No tmux and no checkpoint → idle")
    func detectIdle_whenNoTmuxAndNoCheckpoint() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let cpManager = CheckpointManager(directory: dir)
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)

        let state = await detector.detect()
        #expect(state == .idle)
    }

    // BR-03: RUNNING = tmux session exists
    @Test("Tmux session running → running")
    func detectRunning_whenTmuxSessionExists() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = true
        let cpManager = CheckpointManager(directory: dir)
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)

        let state = await detector.detect()
        #expect(state == .running)
    }

    // BR-50: tmux dies while RUNNING → FSM sees IDLE (checkpoint preserved)
    @Test("Checkpoint exists but no tmux → idle (crash recovery)")
    func detectIdle_whenCheckpointButNoTmux() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let cpManager = CheckpointManager(directory: dir)

        // Write a checkpoint as if we were running
        let cp = Checkpoint(timestamp: Date(), hostname: "test", fsmState: .running, dbSynced: false)
        try cpManager.save(cp)

        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)
        let state = await detector.detect()
        #expect(state == .idle) // Crash recovery: tmux dead = idle
        #expect(cpManager.exists()) // Checkpoint preserved for resume
    }

    // Tmux running + checkpoint → still running
    @Test("Tmux running with checkpoint → running")
    func detectRunning_whenTmuxAndCheckpoint() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = true
        let cpManager = CheckpointManager(directory: dir)

        let cp = Checkpoint(timestamp: Date(), hostname: "test", fsmState: .running, dbSynced: false)
        try cpManager.save(cp)

        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)
        let state = await detector.detect()
        #expect(state == .running)
    }

    // BR-07: State detection checks tmux + checkpoint
    @Test("Detection uses injected environment checker")
    func stateDetection_usesInjectedChecker() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = false
        let detector = StateDetector(sessionName: "test-session", environment: env, checkpointManager: CheckpointManager(directory: dir))

        let state = await detector.detect()
        #expect(state == .idle)
    }

    // BR-07: Performance — detection should be fast
    @Test("State detection completes quickly")
    func stateDetection_completesQuickly() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let env = MockEnvironmentChecker()
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: CheckpointManager(directory: dir))

        let start = ContinuousClock.now
        _ = await detector.detect()
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(200))
    }
}
