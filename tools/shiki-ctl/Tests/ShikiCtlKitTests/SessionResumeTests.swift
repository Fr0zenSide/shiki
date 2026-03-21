import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Session Resume — F2a: tmux launch + context injection")
struct SessionResumeTests {

    private func makeTempManager() throws -> (PausedSessionManager, String) {
        let dir = NSTemporaryDirectory() + "shiki-resume-test-\(UUID().uuidString)"
        let manager = PausedSessionManager(sessionsDir: dir)
        return (manager, dir)
    }

    @Test("Resume with checkpoint loads session and builds context")
    func sessionResume_launchesTmux() async throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // Pause a session first
        let checkpoint = PausedSession(
            branch: "feature/test-resume",
            summary: "Working on tmux integration",
            nextAction: "Wire up signal handlers",
            workspaceRoot: "/tmp/test-workspace"
        )
        try manager.pause(checkpoint: checkpoint)

        // Resume should find it
        let resumed = try manager.resume()
        #expect(resumed != nil)
        #expect(resumed?.branch == "feature/test-resume")
        #expect(resumed?.workspaceRoot == "/tmp/test-workspace")

        // Build context should produce valid injection text
        let context = manager.buildResumeContext(checkpoint: resumed!)
        #expect(context.contains("feature/test-resume"))
        #expect(context.contains("Working on tmux integration"))
        #expect(context.contains("Wire up signal handlers"))
    }

    @Test("Resume with no session shows error")
    func sessionResume_noSession_showsError() async throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // No sessions paused — resume should return nil
        let resumed = try manager.resume()
        #expect(resumed == nil)

        // With specific ID that doesn't exist
        let specific = try manager.resume(sessionId: "nonexistent-id")
        #expect(specific == nil)
    }
}

@Suite("Session Auto-Save — F2b: checkpoint on exit")
struct SessionAutoSaveTests {

    private func makeTempManager() throws -> (PausedSessionManager, String) {
        let dir = NSTemporaryDirectory() + "shiki-autosave-test-\(UUID().uuidString)"
        let manager = PausedSessionManager(sessionsDir: dir)
        return (manager, dir)
    }

    @Test("Auto-save captures current state")
    func autoSave_capturesCurrentState() async throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // autoSave() detects real git state — we just verify it creates a checkpoint
        let checkpoint = manager.autoSave()

        // Should succeed (we're in a git repo)
        #expect(checkpoint != nil)

        // Verify checkpoint was persisted
        let sessions = try manager.listCheckpoints()
        #expect(sessions.count == 1)
        #expect(sessions[0].sessionId == checkpoint?.sessionId)
    }

    @Test("Auto-save includes git branch")
    func autoSave_includesGitBranch() async throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let checkpoint = manager.autoSave()

        #expect(checkpoint != nil)
        // We're on feature/shikki-cli-foundation or similar — should not be "unknown"
        #expect(checkpoint?.branch != "unknown")
        #expect(!checkpoint!.branch.isEmpty)
    }
}
