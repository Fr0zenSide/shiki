import Foundation
import Testing
@testable import ShikkiKit

@Suite("SessionBootstrap — Zero-to-Running Wave 3: first-run detection + default state")
struct SessionBootstrapTests {

    private func makeTempDir() -> String {
        let path = NSTemporaryDirectory() + "shikki-bootstrap-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - isFirstRun

    @Test("isFirstRun returns true when sessions dir does not exist")
    func isFirstRun_noSessionsDir_returnsTrue() {
        let baseDir = NSTemporaryDirectory() + "shikki-bootstrap-\(UUID().uuidString)"
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: CheckpointManager(directory: cpDir),
            hostname: "test-host"
        )

        #expect(bootstrap.isFirstRun() == true)
    }

    @Test("isFirstRun returns true when sessions dir is empty")
    func isFirstRun_emptySessionsDir_returnsTrue() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        try FileManager.default.createDirectory(
            atPath: sessionsDir, withIntermediateDirectories: true
        )

        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: CheckpointManager(directory: cpDir),
            hostname: "test-host"
        )

        #expect(bootstrap.isFirstRun() == true)
    }

    @Test("isFirstRun returns false when checkpoint exists")
    func isFirstRun_checkpointExists_returnsFalse() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let cpManager = CheckpointManager(directory: cpDir)
        let cp = Checkpoint(
            timestamp: Date(), hostname: "test-host", fsmState: .idle, dbSynced: false
        )
        try cpManager.save(cp)

        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: cpManager,
            hostname: "test-host"
        )

        #expect(bootstrap.isFirstRun() == false)
    }

    @Test("isFirstRun ignores hidden files like .DS_Store")
    func isFirstRun_onlyHiddenFiles_returnsTrue() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        try FileManager.default.createDirectory(
            atPath: sessionsDir, withIntermediateDirectories: true
        )
        // Create a hidden file (like .DS_Store)
        FileManager.default.createFile(
            atPath: "\(sessionsDir)/.DS_Store", contents: Data()
        )

        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: CheckpointManager(directory: cpDir),
            hostname: "test-host"
        )

        #expect(bootstrap.isFirstRun() == true)
    }

    // MARK: - createDefaultState

    @Test("createDefaultState creates sessions directory")
    func createDefaultState_createsSessionsDir() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/new-sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: CheckpointManager(directory: cpDir),
            hostname: "test-host"
        )

        try bootstrap.createDefaultState()

        #expect(FileManager.default.fileExists(atPath: sessionsDir))
    }

    @Test("createDefaultState creates checkpoint with idle state")
    func createDefaultState_createsIdleCheckpoint() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let cpManager = CheckpointManager(directory: cpDir)
        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: cpManager,
            hostname: "test-host"
        )

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try bootstrap.createDefaultState(now: fixedDate)

        let loaded = try cpManager.load()
        #expect(loaded != nil)
        #expect(loaded?.fsmState == .idle)
        #expect(loaded?.hostname == "test-host")
        #expect(loaded?.sessionStats == nil)
        #expect(loaded?.contextSnippet == nil)
        #expect(loaded?.dbSynced == false)
    }

    @Test("createDefaultState is idempotent")
    func createDefaultState_idempotent() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let cpManager = CheckpointManager(directory: cpDir)
        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: cpManager,
            hostname: "test-host"
        )

        // Call twice — should not throw
        try bootstrap.createDefaultState()
        try bootstrap.createDefaultState()

        let loaded = try cpManager.load()
        #expect(loaded != nil)
    }

    // MARK: - welcomeMessage

    @Test("welcomeMessage returns first-run greeting when no checkpoint context")
    func welcomeMessage_firstRun_returnsWelcome() {
        let baseDir = NSTemporaryDirectory() + "shikki-bootstrap-\(UUID().uuidString)"
        let bootstrap = SessionBootstrap(
            sessionsDirectory: "\(baseDir)/sessions",
            checkpointManager: CheckpointManager(directory: "\(baseDir)/cp"),
            hostname: "test-host"
        )

        let message = bootstrap.welcomeMessage()
        #expect(message == "Welcome to Shikki \u{1F525}")
    }

    @Test("welcomeMessage returns resume info when checkpoint has stats")
    func welcomeMessage_withStats_returnsResume() {
        let baseDir = NSTemporaryDirectory() + "shikki-bootstrap-\(UUID().uuidString)"
        let bootstrap = SessionBootstrap(
            sessionsDirectory: "\(baseDir)/sessions",
            checkpointManager: CheckpointManager(directory: "\(baseDir)/cp"),
            hostname: "test-host"
        )

        let cp = Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .idle,
            sessionStats: SessionSnapshot(
                startedAt: Date(), branch: "feature/test", commitCount: 5
            ),
            dbSynced: false
        )

        let message = bootstrap.welcomeMessage(checkpoint: cp)
        #expect(message.contains("Resuming session"))
        #expect(message.contains("feature/test"))
        #expect(message.contains("5 commits"))
    }

    @Test("welcomeMessage returns resume with context snippet")
    func welcomeMessage_withSnippet_includesSnippet() {
        let baseDir = NSTemporaryDirectory() + "shikki-bootstrap-\(UUID().uuidString)"
        let bootstrap = SessionBootstrap(
            sessionsDirectory: "\(baseDir)/sessions",
            checkpointManager: CheckpointManager(directory: "\(baseDir)/cp"),
            hostname: "test-host"
        )

        let cp = Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .idle,
            contextSnippet: "Working on session bootstrap",
            dbSynced: false
        )

        let message = bootstrap.welcomeMessage(checkpoint: cp)
        #expect(message.contains("Working on session bootstrap"))
    }

    @Test("welcomeMessage truncates long context snippets")
    func welcomeMessage_longSnippet_truncates() {
        let baseDir = NSTemporaryDirectory() + "shikki-bootstrap-\(UUID().uuidString)"
        let bootstrap = SessionBootstrap(
            sessionsDirectory: "\(baseDir)/sessions",
            checkpointManager: CheckpointManager(directory: "\(baseDir)/cp"),
            hostname: "test-host"
        )

        let longSnippet = String(repeating: "x", count: 200)
        let cp = Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .idle,
            contextSnippet: longSnippet,
            dbSynced: false
        )

        let message = bootstrap.welcomeMessage(checkpoint: cp)
        #expect(message.contains("..."))
        #expect(message.count < 200)
    }

    // MARK: - bootstrap (integration)

    @Test("bootstrap on first run creates state and returns welcome")
    func bootstrap_firstRun_createsStateAndReturnsWelcome() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let cpManager = CheckpointManager(directory: cpDir)
        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: cpManager,
            hostname: "test-host"
        )

        let message = try bootstrap.bootstrap()

        #expect(message == "Welcome to Shikki \u{1F525}")
        #expect(cpManager.exists())
        #expect(FileManager.default.fileExists(atPath: sessionsDir))
    }

    @Test("bootstrap on returning run loads checkpoint and returns resume")
    func bootstrap_returningRun_returnsResumeMessage() throws {
        let baseDir = makeTempDir()
        let sessionsDir = "\(baseDir)/sessions"
        let cpDir = "\(baseDir)/cp"
        defer { cleanup(baseDir) }

        let cpManager = CheckpointManager(directory: cpDir)

        // Simulate a prior session: create checkpoint with stats
        let priorCheckpoint = Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .idle,
            sessionStats: SessionSnapshot(
                startedAt: Date(), branch: "develop", commitCount: 3
            ),
            dbSynced: false
        )
        try cpManager.save(priorCheckpoint)

        // Also create sessions dir so it's not first-run
        try FileManager.default.createDirectory(
            atPath: sessionsDir, withIntermediateDirectories: true
        )

        let bootstrap = SessionBootstrap(
            sessionsDirectory: sessionsDir,
            checkpointManager: cpManager,
            hostname: "test-host"
        )

        let message = try bootstrap.bootstrap()

        #expect(message.contains("Resuming session"))
        #expect(message.contains("develop"))
    }
}
