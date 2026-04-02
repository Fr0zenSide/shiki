import Foundation
import Logging

// MARK: - NATSServerError

/// Errors from NATS server lifecycle management.
public enum NATSServerError: Error, Sendable, Equatable {
    case binaryNotFound(String)
    case configGenerationFailed(String)
    case startFailed(String)
    case stopFailed(String)
    case alreadyRunning
    case notRunning
    case healthCheckFailed(String)
    case pidFileError(String)
}

// MARK: - NATSProcessLauncher

/// Abstraction over Process to allow mocking in tests.
/// Concrete implementation wraps Foundation.Process.
public protocol NATSProcessLauncher: Sendable {
    /// Check if a binary exists at the given path.
    func binaryExists(at path: String) -> Bool

    /// Check if a binary is available on PATH via `which`.
    func binaryOnPath(_ name: String) async -> String?

    /// Launch a process and return its PID.
    func launch(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) throws -> Int32

    /// Send a signal to a process.
    func sendSignal(_ signal: Int32, to pid: Int32) -> Bool

    /// Check if a process with the given PID is alive.
    func isProcessAlive(pid: Int32) -> Bool

    /// Wait for a process to exit, with timeout.
    func waitForExit(pid: Int32, timeout: Duration) async -> Bool
}

// MARK: - SystemProcessLauncher

/// Production implementation that wraps Foundation.Process.
public struct SystemProcessLauncher: NATSProcessLauncher {

    public init() {}

    public func binaryExists(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func binaryOnPath(_ name: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    public func launch(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        return process.processIdentifier
    }

    public func sendSignal(_ signal: Int32, to pid: Int32) -> Bool {
        kill(pid, signal) == 0
    }

    public func isProcessAlive(pid: Int32) -> Bool {
        // kill(pid, 0) checks existence without sending a signal
        kill(pid, 0) == 0
    }

    public func waitForExit(pid: Int32, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !isProcessAlive(pid: pid) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !isProcessAlive(pid: pid)
    }
}

// MARK: - NATSServerManager

/// Actor that manages the nats-server process lifecycle.
///
/// Responsibilities:
/// - Check if nats-server binary is installed
/// - Generate config file if missing
/// - Start nats-server as a child process
/// - Stop gracefully (SIGTERM, wait 5s, SIGKILL if needed)
/// - Track process via PID file
/// - Health check integration
///
/// Used by `shi start` and `shi stop`.
public actor NATSServerManager {

    private let processLauncher: NATSProcessLauncher
    private let healthCheck: NATSHealthCheckProtocol
    private let logger: Logger
    private let config: NATSConfig

    private var serverPid: Int32?

    /// Maximum wait time for graceful shutdown.
    private static let shutdownTimeout: Duration = .seconds(5)

    /// Retry count for health check after start.
    private static let healthRetries = 3

    /// Delay between health check retries.
    private static let healthRetryDelay: Duration = .milliseconds(500)

    public init(
        config: NATSConfig = .default,
        processLauncher: NATSProcessLauncher = SystemProcessLauncher(),
        healthCheck: NATSHealthCheckProtocol? = nil,
        logger: Logger = Logger(label: "shikki.nats.server")
    ) {
        self.config = config
        self.processLauncher = processLauncher
        self.healthCheck = healthCheck ?? NATSHealthCheck(
            host: config.host,
            port: config.port
        )
        self.logger = logger
    }

    // MARK: - Public API

    /// Start the nats-server process.
    ///
    /// Sequence:
    /// 1. Check if already running
    /// 2. Locate nats-server binary (custom path or PATH)
    /// 3. Generate config if needed
    /// 4. Spawn process
    /// 5. Write PID file
    /// 6. Health check with retries
    public func start() async throws {
        if await isRunning {
            throw NATSServerError.alreadyRunning
        }

        // 1. Locate binary
        let binaryPath = try await resolveBinaryPath()
        logger.info("Using nats-server at \(binaryPath)")

        // 2. Generate config
        try generateConfig()
        logger.info("Config written to \(NATSConfig.configFilePath)")

        // 3. Ensure log directory exists
        try ensureLogDirectory()

        // 4. Start process
        let pid = try processLauncher.launch(
            executablePath: binaryPath,
            arguments: ["-c", NATSConfig.configFilePath],
            environment: nil
        )
        serverPid = pid
        logger.info("nats-server started with PID \(pid)")

        // 5. Write PID file
        try writePidFile(pid: pid)

        // 6. Health check
        let healthy = await waitForHealthy()
        if !healthy {
            // Cleanup: kill the process we just started
            await stopForce()
            throw NATSServerError.healthCheckFailed(
                "nats-server started but health check failed after \(Self.healthRetries) retries"
            )
        }

        logger.info("nats-server is healthy on \(config.host):\(config.port)")
    }

    /// Stop the nats-server process gracefully.
    ///
    /// Sends SIGTERM, waits up to 5 seconds, then SIGKILL if needed.
    public func stop() async throws {
        guard let pid = resolvedPid else {
            throw NATSServerError.notRunning
        }

        logger.info("Stopping nats-server (PID \(pid))...")

        // Send SIGTERM
        let sent = processLauncher.sendSignal(SIGTERM, to: pid)
        if !sent {
            logger.warning("Failed to send SIGTERM to PID \(pid)")
        }

        // Wait for clean exit
        let exited = await processLauncher.waitForExit(
            pid: pid,
            timeout: Self.shutdownTimeout
        )

        if !exited {
            // Force kill
            logger.warning("nats-server did not exit gracefully, sending SIGKILL")
            _ = processLauncher.sendSignal(SIGKILL, to: pid)
            let killed = await processLauncher.waitForExit(
                pid: pid,
                timeout: .seconds(2)
            )
            if !killed {
                throw NATSServerError.stopFailed("Process \(pid) did not exit after SIGKILL")
            }
        }

        serverPid = nil
        cleanupPidFile()
        logger.info("nats-server stopped")
    }

    /// Restart: stop + start.
    public func restart() async throws {
        if await isRunning {
            try await stop()
        }
        try await start()
    }

    /// Check if the nats-server process is currently running.
    public var isRunning: Bool {
        get async {
            guard let pid = resolvedPid else { return false }
            return processLauncher.isProcessAlive(pid: pid)
        }
    }

    /// Current server PID if known.
    public var currentPid: Int32? {
        resolvedPid
    }

    /// Perform a health check against the running server.
    public func healthCheckResult() async -> NATSHealthResult {
        await healthCheck.ping()
    }

    // MARK: - Binary Resolution

    /// Resolve the nats-server binary path.
    /// First checks the managed path (~/.config/shiki/bin/nats-server),
    /// then falls back to PATH lookup.
    func resolveBinaryPath() async throws -> String {
        // Check managed binary location
        if processLauncher.binaryExists(at: NATSConfig.binaryPath) {
            return NATSConfig.binaryPath
        }

        // Fall back to PATH
        if let pathBinary = await processLauncher.binaryOnPath("nats-server") {
            return pathBinary
        }

        throw NATSServerError.binaryNotFound(
            "nats-server not found at \(NATSConfig.binaryPath) or on PATH. "
            + "Install via: brew install nats-server"
        )
    }

    // MARK: - Config Generation

    /// Generate nats-server.conf if it does not exist.
    func generateConfig() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: NATSConfig.configFilePath) {
            logger.debug("Config already exists at \(NATSConfig.configFilePath)")
            return
        }

        do {
            try config.writeToFile()
        } catch {
            throw NATSServerError.configGenerationFailed(error.localizedDescription)
        }
    }

    /// Force-write config (used for regeneration).
    public func regenerateConfig() throws {
        do {
            try config.writeToFile()
            logger.info("Config regenerated at \(NATSConfig.configFilePath)")
        } catch {
            throw NATSServerError.configGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - PID File

    /// Read PID from the PID file on disk.
    private var resolvedPid: Int32? {
        if let pid = serverPid { return pid }
        return Self.readPidFile(at: config.pidFile)
    }

    /// Read PID from a file.
    static func readPidFile(at path: String) -> Int32? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Write PID to disk.
    private func writePidFile(pid: Int32) throws {
        let dir = (config.pidFile as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        try String(pid).write(
            toFile: config.pidFile,
            atomically: true,
            encoding: .utf8
        )
    }

    /// Remove PID file on shutdown.
    private func cleanupPidFile() {
        try? FileManager.default.removeItem(atPath: config.pidFile)
    }

    // MARK: - Health Check

    /// Wait for nats-server to become healthy with retries.
    private func waitForHealthy() async -> Bool {
        for attempt in 1...Self.healthRetries {
            let result = await healthCheck.ping()
            if result.isHealthy {
                return true
            }
            logger.debug(
                "Health check attempt \(attempt)/\(Self.healthRetries) failed: \(result.message)"
            )
            if attempt < Self.healthRetries {
                try? await Task.sleep(for: Self.healthRetryDelay)
            }
        }
        return false
    }

    // MARK: - Force Stop (cleanup)

    /// Force kill without error propagation.
    private func stopForce() async {
        guard let pid = resolvedPid else { return }
        _ = processLauncher.sendSignal(SIGKILL, to: pid)
        _ = await processLauncher.waitForExit(pid: pid, timeout: .seconds(2))
        serverPid = nil
        cleanupPidFile()
    }

    // MARK: - Log Directory

    /// Ensure the log directory exists.
    private func ensureLogDirectory() throws {
        let dir = (config.logFile as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
    }
}

// MARK: - NATSManagedService

/// Adapter that wraps NATSServerManager as a ManagedService for the ShikkiKernel.
/// The kernel starts nats-server as part of the boot sequence and monitors health.
public actor NATSManagedService: ManagedService {
    public nonisolated let id: ServiceID = .natsServer
    public nonisolated let qos: ServiceQoS = .critical
    public nonisolated let interval: Duration = .seconds(30)
    public nonisolated let restartPolicy: RestartPolicy = .always(
        maxRestarts: 5, backoff: .seconds(10)
    )

    private let manager: NATSServerManager
    private let logger: Logger
    private var hasStarted = false

    public init(
        manager: NATSServerManager,
        logger: Logger = Logger(label: "shikki.nats.managed")
    ) {
        self.manager = manager
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        if !hasStarted {
            // First tick: start nats-server
            try await manager.start()
            hasStarted = true
            return
        }

        // Subsequent ticks: health monitoring
        let running = await manager.isRunning
        if !running {
            logger.warning("nats-server not running, restarting...")
            try await manager.start()
        } else {
            let health = await manager.healthCheckResult()
            if !health.isHealthy {
                logger.warning("nats-server unhealthy: \(health.message), restarting...")
                try await manager.restart()
            }
        }
    }

    /// NATSManagedService always runs — it IS infrastructure.
    public nonisolated func canRun(health: HealthStatus) -> Bool {
        true
    }
}
