import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("ShikkiEngine Subcommand Routing — BR-36 to BR-40, BR-44")
struct SubcommandRoutingIntegrationTests {

    private func makeEngine(tmuxRunning: Bool) throws -> (ShikkiEngine, String) {
        let dir = NSTemporaryDirectory() + "shikki-route-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = tmuxRunning
        let detector = StateDetector(sessionName: "shikki", environment: env, checkpointManager: CheckpointManager(directory: dir))
        let engine = ShikkiEngine(
            detector: detector,
            checkpointManager: CheckpointManager(directory: dir),
            lockfileManager: LockfileManager(path: "\(dir)/shikki.pid"),
            dbSync: MockDBSync()
        )
        return (engine, dir)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // BR-36: Retained commands are recognized
    @Test("Retained subcommands are recognized")
    func subcommand_retainedAreKnown() {
        let retained = ["pr", "board", "dashboard", "doctor", "report",
                        "search", "ship", "menu", "decide", "heartbeat",
                        "history", "status", "stop"]
        for cmd in retained {
            #expect(ShikkiEngine.isKnownCommand(cmd), "Expected '\(cmd)' to be known")
        }
    }

    // BR-37: Deleted commands are NOT recognized
    @Test("Deleted subcommands are not recognized")
    func subcommand_deletedAreNotKnown() {
        let deleted = ["start", "attach", "session"]
        for cmd in deleted {
            #expect(!ShikkiEngine.isKnownCommand(cmd), "Expected '\(cmd)' to NOT be known")
        }
    }

    // BR-38: stop is recognized
    @Test("Stop is a recognized subcommand")
    func subcommand_stopIsKnown() {
        #expect(ShikkiEngine.isKnownCommand("stop"))
    }

    // BR-39: board requires RUNNING, fails when IDLE
    @Test("Board requires RUNNING — fails when IDLE")
    func runningRequired_whenIdle_throwsNotRunningError() async throws {
        let (engine, dir) = try makeEngine(tmuxRunning: false)
        defer { cleanup(dir) }

        let error = await engine.validateStateForCommand("board")
        #expect(error != nil)
        #expect(error!.contains("requires a running session"))
    }

    // BR-39: board succeeds when RUNNING
    @Test("Board succeeds when RUNNING")
    func runningRequired_whenRunning_executes() async throws {
        let (engine, dir) = try makeEngine(tmuxRunning: true)
        defer { cleanup(dir) }

        let error = await engine.validateStateForCommand("board")
        #expect(error == nil)
    }

    // BR-40: pr works regardless of state
    @Test("PR works regardless of state")
    func nonRunningSubcommand_executesInAnyState() async throws {
        let (engine, dir) = try makeEngine(tmuxRunning: false)
        defer { cleanup(dir) }

        let error = await engine.validateStateForCommand("pr")
        #expect(error == nil) // No state requirement

        // Also check doctor, search, ship
        #expect(await engine.validateStateForCommand("doctor") == nil)
        #expect(await engine.validateStateForCommand("search") == nil)
        #expect(await engine.validateStateForCommand("ship") == nil)
    }
}
