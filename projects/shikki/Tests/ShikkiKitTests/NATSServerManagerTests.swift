import Foundation
import Testing
@testable import ShikkiKit

// MARK: - MockNATSProcessLauncher

/// Mock process launcher that records calls and returns configurable results.
/// No real processes are spawned.
final class MockNATSProcessLauncher: NATSProcessLauncher, @unchecked Sendable {

    // MARK: - Tracking

    var binaryExistsChecks: [String] = []
    var binaryOnPathChecks: [String] = []
    var launchCalls: [(path: String, args: [String])] = []
    var signalsSent: [(signal: Int32, pid: Int32)] = []
    var aliveChecks: [Int32] = []
    var waitCalls: [Int32] = []

    // MARK: - Configurable Responses

    var binaryExistsResult: [String: Bool] = [:]
    var binaryOnPathResult: [String: String?] = [:]
    var launchPid: Int32 = 12345
    var launchShouldThrow: Error?
    var isAliveResult: Bool = true
    var waitForExitResult: Bool = true
    var sendSignalResult: Bool = true

    // Track "alive" state — becomes false after SIGTERM/SIGKILL
    var processAlive: Bool = true

    func binaryExists(at path: String) -> Bool {
        binaryExistsChecks.append(path)
        return binaryExistsResult[path] ?? false
    }

    func binaryOnPath(_ name: String) async -> String? {
        binaryOnPathChecks.append(name)
        return binaryOnPathResult[name] ?? nil
    }

    func launch(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) throws -> Int32 {
        if let error = launchShouldThrow { throw error }
        launchCalls.append((path: executablePath, args: arguments))
        processAlive = true
        return launchPid
    }

    func sendSignal(_ signal: Int32, to pid: Int32) -> Bool {
        signalsSent.append((signal: signal, pid: pid))
        if signal == SIGTERM || signal == SIGKILL {
            processAlive = false
        }
        return sendSignalResult
    }

    func isProcessAlive(pid: Int32) -> Bool {
        aliveChecks.append(pid)
        return processAlive
    }

    func waitForExit(pid: Int32, timeout: Duration) async -> Bool {
        waitCalls.append(pid)
        return waitForExitResult
    }
}

// MARK: - Tests

@Suite("NATSServerManager — Binary resolution")
struct NATSServerManagerBinaryTests {

    @Test("Finds binary at managed path")
    func findsManagedBinary() async throws {
        let launcher = MockNATSProcessLauncher()
        launcher.binaryExistsResult[NATSConfig.binaryPath] = true

        let healthCheck = MockNATSHealthCheck(results: [.healthy(latencyMs: 1.0)])
        let config = NATSConfig(authToken: "test-token")
        let manager = NATSServerManager(
            config: config,
            processLauncher: launcher,
            healthCheck: healthCheck
        )

        let path = try await manager.resolveBinaryPath()
        #expect(path == NATSConfig.binaryPath)
    }

    @Test("Falls back to PATH when managed binary missing")
    func fallsBackToPath() async throws {
        let launcher = MockNATSProcessLauncher()
        launcher.binaryExistsResult[NATSConfig.binaryPath] = false
        launcher.binaryOnPathResult["nats-server"] = "/usr/local/bin/nats-server"

        let healthCheck = MockNATSHealthCheck(results: [.healthy(latencyMs: 1.0)])
        let config = NATSConfig(authToken: "test-token")
        let manager = NATSServerManager(
            config: config,
            processLauncher: launcher,
            healthCheck: healthCheck
        )

        let path = try await manager.resolveBinaryPath()
        #expect(path == "/usr/local/bin/nats-server")
    }

    @Test("Throws binaryNotFound when neither location has binary")
    func throwsBinaryNotFound() async throws {
        let launcher = MockNATSProcessLauncher()
        launcher.binaryExistsResult[NATSConfig.binaryPath] = false
        launcher.binaryOnPathResult["nats-server"] = nil

        let healthCheck = MockNATSHealthCheck()
        let config = NATSConfig(authToken: "test-token")
        let manager = NATSServerManager(
            config: config,
            processLauncher: launcher,
            healthCheck: healthCheck
        )

        await #expect(throws: NATSServerError.self) {
            try await manager.resolveBinaryPath()
        }
    }
}

@Suite("NATSServerManager — Config generation")
struct NATSServerManagerConfigTests {

    @Test("Generates config to temp directory")
    func generatesConfig() async throws {
        let tmpDir = NSTemporaryDirectory() + "nats-cfg-\(UUID().uuidString)/"
        let configPath = "\(tmpDir)nats-server.conf"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let config = NATSConfig(
            host: "127.0.0.1",
            port: 4222,
            authToken: "gen-test-token",
            logFile: "\(tmpDir)nats.log",
            pidFile: "\(tmpDir)nats.pid"
        )

        try config.writeToFile(at: configPath)

        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        #expect(content.contains("listen: 127.0.0.1:4222"))
        #expect(content.contains("gen-test-token"))
        #expect(content.contains("max_payload: 1048576"))
    }
}

@Suite("NATSServerManager — Process lifecycle")
struct NATSServerManagerLifecycleTests {

    /// Create a manager with full mocks pointed at a temp directory.
    private func makeManager(
        launcher: MockNATSProcessLauncher = MockNATSProcessLauncher(),
        healthResults: [NATSHealthResult] = [.healthy(latencyMs: 1.0)]
    ) -> (NATSServerManager, MockNATSProcessLauncher, MockNATSHealthCheck) {
        let tmpDir = NSTemporaryDirectory() + "nats-mgr-\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let config = NATSConfig(
            authToken: "lifecycle-token",
            logFile: "\(tmpDir)nats.log",
            pidFile: "\(tmpDir)nats.pid"
        )

        let healthCheck = MockNATSHealthCheck(results: healthResults)

        // Ensure binary is "found" on PATH
        launcher.binaryOnPathResult["nats-server"] = "/usr/local/bin/nats-server"

        let manager = NATSServerManager(
            config: config,
            processLauncher: launcher,
            healthCheck: healthCheck
        )

        return (manager, launcher, healthCheck)
    }

    @Test("Start launches process and writes PID file")
    func startLaunchesProcess() async throws {
        let (manager, launcher, _) = makeManager()

        try await manager.start()

        #expect(launcher.launchCalls.count == 1)
        #expect(launcher.launchCalls[0].path == "/usr/local/bin/nats-server")
        #expect(launcher.launchCalls[0].args.contains("-c"))

        let pid = await manager.currentPid
        #expect(pid == launcher.launchPid)
    }

    @Test("Start fails with health check failure after retries")
    func startFailsOnUnhealthy() async throws {
        let (manager, launcher, _) = makeManager(
            healthResults: [
                .unhealthy("timeout"),
                .unhealthy("timeout"),
                .unhealthy("timeout"),
            ]
        )

        await #expect(throws: NATSServerError.self) {
            try await manager.start()
        }

        // Process was launched but then killed due to health failure
        #expect(launcher.launchCalls.count == 1)
        // SIGKILL sent during cleanup
        let killSignals = launcher.signalsSent.filter { $0.signal == SIGKILL }
        #expect(killSignals.count >= 1)
    }

    @Test("Start throws alreadyRunning if process is alive")
    func startThrowsIfAlreadyRunning() async throws {
        let (manager, _, _) = makeManager()

        try await manager.start()

        await #expect(throws: NATSServerError.self) {
            try await manager.start()
        }
    }

    @Test("Stop sends SIGTERM and waits")
    func stopSendsSignal() async throws {
        let (manager, launcher, _) = makeManager()

        try await manager.start()
        try await manager.stop()

        let termSignals = launcher.signalsSent.filter { $0.signal == SIGTERM }
        #expect(termSignals.count == 1)
        #expect(termSignals[0].pid == launcher.launchPid)
    }

    @Test("Stop sends SIGKILL if graceful exit times out")
    func stopSendsKillOnTimeout() async throws {
        let launcher = MockNATSProcessLauncher()
        launcher.waitForExitResult = false // Process never exits gracefully
        launcher.processAlive = false // But we pretend it eventually dies

        let (manager, _, _) = makeManager(launcher: launcher)

        try await manager.start()

        // Reset processAlive so stop logic sees it as running
        launcher.processAlive = true
        launcher.waitForExitResult = false

        // Stop will send SIGTERM, wait fails, then SIGKILL
        // After SIGKILL processAlive becomes false via mock
        await #expect(throws: NATSServerError.self) {
            try await manager.stop()
        }

        let killSignals = launcher.signalsSent.filter { $0.signal == SIGKILL }
        #expect(killSignals.count >= 1)
    }

    @Test("Stop throws notRunning when no process started")
    func stopThrowsNotRunning() async {
        let (manager, _, _) = makeManager()

        await #expect(throws: NATSServerError.self) {
            try await manager.stop()
        }
    }

    @Test("Restart stops then starts")
    func restartStopsThenStarts() async throws {
        let (manager, launcher, _) = makeManager()

        try await manager.start()
        try await manager.restart()

        // Should have launched twice (initial start + restart)
        #expect(launcher.launchCalls.count == 2)

        // Should have sent SIGTERM for the stop
        let termSignals = launcher.signalsSent.filter { $0.signal == SIGTERM }
        #expect(termSignals.count == 1)
    }

    @Test("isRunning returns false when no process started")
    func isRunningFalseInitially() async {
        let (manager, _, _) = makeManager()
        let running = await manager.isRunning
        #expect(!running)
    }

    @Test("isRunning returns true after start")
    func isRunningTrueAfterStart() async throws {
        let (manager, _, _) = makeManager()
        try await manager.start()
        let running = await manager.isRunning
        #expect(running)
    }

    @Test("Health check returns result from healthCheck protocol")
    func healthCheckDelegates() async throws {
        let (manager, _, healthCheck) = makeManager(
            healthResults: [
                .healthy(latencyMs: 1.0), // for start
                .healthy(latencyMs: 42.0), // for our explicit check
            ]
        )

        try await manager.start()
        let result = await manager.healthCheckResult()
        #expect(result.latencyMs == 42.0)
        #expect(healthCheck.pingCallCount >= 2)
    }
}

@Suite("NATSServerManager — PID file")
struct NATSServerManagerPidTests {

    @Test("Read PID file parses integer")
    func readPidFile() throws {
        let tmpPath = NSTemporaryDirectory() + "nats-pid-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        try "54321".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let pid = NATSServerManager.readPidFile(at: tmpPath)
        #expect(pid == 54321)
    }

    @Test("Read PID file handles whitespace")
    func readPidFileWhitespace() throws {
        let tmpPath = NSTemporaryDirectory() + "nats-pid-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        try "  12345\n".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let pid = NATSServerManager.readPidFile(at: tmpPath)
        #expect(pid == 12345)
    }

    @Test("Read PID file returns nil for missing file")
    func readPidFileMissing() {
        let pid = NATSServerManager.readPidFile(at: "/nonexistent/path/nats.pid")
        #expect(pid == nil)
    }

    @Test("Read PID file returns nil for invalid content")
    func readPidFileInvalid() throws {
        let tmpPath = NSTemporaryDirectory() + "nats-pid-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        try "not-a-number".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let pid = NATSServerManager.readPidFile(at: tmpPath)
        #expect(pid == nil)
    }
}

@Suite("NATSManagedService — Kernel integration")
struct NATSManagedServiceTests {

    @Test("Service ID is natsServer")
    func serviceId() async {
        let launcher = MockNATSProcessLauncher()
        launcher.binaryOnPathResult["nats-server"] = "/usr/local/bin/nats-server"

        let tmpDir = NSTemporaryDirectory() + "nats-svc-\(UUID().uuidString)/"
        let config = NATSConfig(
            authToken: "svc-token",
            logFile: "\(tmpDir)nats.log",
            pidFile: "\(tmpDir)nats.pid"
        )
        let healthCheck = MockNATSHealthCheck(results: [.healthy(latencyMs: 1.0)])
        let manager = NATSServerManager(
            config: config,
            processLauncher: launcher,
            healthCheck: healthCheck
        )

        let service = NATSManagedService(manager: manager)

        #expect(service.id == .natsServer)
        #expect(service.qos == .critical)
        #expect(service.interval == .seconds(30))
    }

    @Test("Service always runs regardless of health status")
    func alwaysRuns() async {
        let launcher = MockNATSProcessLauncher()
        let manager = NATSServerManager(
            config: .default,
            processLauncher: launcher
        )
        let service = NATSManagedService(manager: manager)

        #expect(service.canRun(health: .healthy))
        #expect(service.canRun(health: .degraded(reason: "test")))
        #expect(service.canRun(health: .unreachable))
    }

    @Test("First tick starts nats-server")
    func firstTickStarts() async throws {
        let launcher = MockNATSProcessLauncher()
        launcher.binaryOnPathResult["nats-server"] = "/usr/local/bin/nats-server"

        let tmpDir = NSTemporaryDirectory() + "nats-svc-\(UUID().uuidString)/"
        let config = NATSConfig(
            authToken: "first-tick-token",
            logFile: "\(tmpDir)nats.log",
            pidFile: "\(tmpDir)nats.pid"
        )
        let healthCheck = MockNATSHealthCheck(results: [.healthy(latencyMs: 1.0)])
        let manager = NATSServerManager(
            config: config,
            processLauncher: launcher,
            healthCheck: healthCheck
        )

        let service = NATSManagedService(manager: manager)

        try await service.tick(snapshot: KernelSnapshot(health: .healthy))

        #expect(launcher.launchCalls.count == 1)
    }
}

// MARK: - NATSServerError Tests

@Suite("NATSServerError — Error types")
struct NATSServerErrorTests {

    @Test("Error cases are Equatable")
    func equatable() {
        #expect(NATSServerError.alreadyRunning == NATSServerError.alreadyRunning)
        #expect(NATSServerError.notRunning == NATSServerError.notRunning)
        #expect(
            NATSServerError.binaryNotFound("msg")
            == NATSServerError.binaryNotFound("msg")
        )
        #expect(
            NATSServerError.binaryNotFound("a")
            != NATSServerError.binaryNotFound("b")
        )
    }
}
