import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("ShikkiEngine Entry Point — BR-08, BR-09, BR-10, BR-11, BR-23")
struct ShikkiEntryPointIntegrationTests {

    private func makeEngine(
        tmuxRunning: Bool = false,
        checkpoint: Checkpoint? = nil
    ) throws -> (ShikkiEngine, String) {
        let dir = NSTemporaryDirectory() + "shikki-ep-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = tmuxRunning
        let cpManager = CheckpointManager(directory: dir)
        let lockManager = LockfileManager(path: "\(dir)/shikki.pid")
        let dbSync = MockDBSync()

        if let cp = checkpoint {
            try cpManager.save(cp)
        }

        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: cpManager)
        let engine = ShikkiEngine(
            detector: detector,
            checkpointManager: cpManager,
            lockfileManager: lockManager,
            dbSync: dbSync
        )
        return (engine, dir)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeCheckpoint(minutesAgo: Double = 30) -> Checkpoint {
        Checkpoint(
            timestamp: Date().addingTimeInterval(-minutesAgo * 60),
            hostname: "test-host",
            fsmState: .idle,
            tmuxLayout: TmuxLayout(paneCount: 3, layoutString: "tiled"),
            sessionStats: SessionSnapshot(startedAt: Date().addingTimeInterval(-7200), branch: "feature/test"),
            contextSnippet: "Working on integration tests",
            dbSynced: false
        )
    }

    // BR-08: IDLE + no checkpoint → clean start
    @Test("IDLE with no checkpoint dispatches startClean")
    func noArgs_whenIdleWithoutCheckpoint_startsClean() async throws {
        let (engine, dir) = try makeEngine(tmuxRunning: false)
        defer { cleanup(dir) }

        let action = try await engine.dispatch()
        #expect(action == .startClean)
    }

    // BR-08: RUNNING → attach
    @Test("RUNNING dispatches attach")
    func noArgs_whenRunning_attachesToSession() async throws {
        let (engine, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }

        let action = try await engine.dispatch()
        #expect(action == .attach)
    }

    // BR-08: STOPPING → block
    @Test("STOPPING dispatches blocked")
    func noArgs_whenStopping_blocksWithMessage() async throws {
        // STOPPING is transient — we simulate it with a mock detector
        let dir = NSTemporaryDirectory() + "shikki-ep-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }

        let mockDetector = MockStateDetector(state: .stopping)
        let engine = ShikkiEngine(
            detector: mockDetector,
            checkpointManager: CheckpointManager(directory: dir),
            lockfileManager: LockfileManager(path: "\(dir)/shikki.pid"),
            dbSync: MockDBSync()
        )

        let action = try await engine.dispatch()
        #expect(action == .blocked)
    }

    // BR-09: IDLE + checkpoint → resume with checkpoint data
    @Test("IDLE with checkpoint dispatches resume")
    func noArgs_whenIdleWithCheckpoint_resumesSession() async throws {
        let cp = makeCheckpoint()
        let (engine, dir) = try makeEngine(tmuxRunning: false, checkpoint: cp)
        defer { cleanup(dir) }

        let action = try await engine.dispatch()
        if case .resume(let loaded) = action {
            #expect(loaded.hostname == "test-host")
            #expect(loaded.contextSnippet == "Working on integration tests")
        } else {
            Issue.record("Expected .resume, got \(action)")
        }
    }

    // BR-09 + BR-45: Resume action produces welcome message
    @Test("Resume action produces welcome back message")
    func resume_showsWelcomeBackMessage() async throws {
        let cp = makeCheckpoint(minutesAgo: 120)
        let (engine, dir) = try makeEngine(tmuxRunning: false, checkpoint: cp)
        defer { cleanup(dir) }

        let action = try await engine.dispatch()
        let message = engine.welcomeMessage(for: action)
        #expect(message != nil)
        #expect(message!.contains("Welcome back"))
        #expect(message!.contains("3 panes"))
    }

    // BR-10 + BR-49: Clean start has no welcome message
    @Test("Clean start has no welcome message")
    func cleanStart_showsNoWelcomeBackMessage() async throws {
        let (engine, dir) = try makeEngine(tmuxRunning: false)
        defer { cleanup(dir) }

        let action = try await engine.dispatch()
        let message = engine.welcomeMessage(for: action)
        #expect(message == nil)
    }

    // BR-23: Checkpoint deleted after successful resume
    @Test("Checkpoint deleted after confirmResume")
    func resume_deletesCheckpointAfterSuccess() async throws {
        let cp = makeCheckpoint()
        let (engine, dir) = try makeEngine(tmuxRunning: false, checkpoint: cp)
        defer { cleanup(dir) }

        let action = try await engine.dispatch()
        #expect(action != .startClean) // Should be .resume

        // Simulate successful tmux start
        try engine.confirmResume()
        #expect(engine.checkpointManager.exists() == false)
    }

    // BR-23: Checkpoint preserved on failed resume (don't call confirmResume)
    @Test("Checkpoint preserved when resume not confirmed")
    func resume_preservesCheckpointOnFailure() async throws {
        let cp = makeCheckpoint()
        let (engine, dir) = try makeEngine(tmuxRunning: false, checkpoint: cp)
        defer { cleanup(dir) }

        _ = try await engine.dispatch()
        // Don't call confirmResume — simulate failure
        #expect(engine.checkpointManager.exists() == true)
    }
}

// MARK: - Mock StateDetector for STOPPING state

final class MockStateDetector: StateDetecting, @unchecked Sendable {
    var state: ShikkiState

    init(state: ShikkiState) {
        self.state = state
    }

    func detect() async -> ShikkiState {
        state
    }
}
