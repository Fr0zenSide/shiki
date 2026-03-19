import Foundation

// MARK: - ShellResult

/// Result of a shell command execution.
public struct ShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

// MARK: - ShipContext Protocol

/// Injected context for ship pipeline — real or dry-run.
/// Gates call shell() for subprocess execution and emit() for event bus integration.
public protocol ShipContext: Sendable {
    var isDryRun: Bool { get }
    var branch: String { get }
    var target: String { get }
    var projectRoot: URL { get }
    func shell(_ command: String) async throws -> ShellResult
    func emit(_ event: ShikiEvent) async
}

// MARK: - GateResult

/// Outcome of a single gate evaluation.
public enum GateResult: Sendable {
    case pass(detail: String?)
    case warn(reason: String)
    case fail(reason: String)
}

// MARK: - ShipResult

/// Overall result of the ship pipeline.
public struct ShipResult: Sendable {
    public let success: Bool
    public let failedGate: String?
    public let failureReason: String?
    public let warnings: [String]
    public let gateResults: [(gate: String, result: GateResult)]

    public init(
        success: Bool,
        failedGate: String? = nil,
        failureReason: String? = nil,
        warnings: [String] = [],
        gateResults: [(gate: String, result: GateResult)] = []
    ) {
        self.success = success
        self.failedGate = failedGate
        self.failureReason = failureReason
        self.warnings = warnings
        self.gateResults = gateResults
    }
}

// MARK: - RealShipContext

/// Real context that executes shell commands and emits events to the bus.
public final class RealShipContext: ShipContext, @unchecked Sendable {
    public let isDryRun = false
    public let branch: String
    public let target: String
    public let projectRoot: URL
    private let eventBus: InProcessEventBus?

    public init(branch: String, target: String, projectRoot: URL, eventBus: InProcessEventBus? = nil) {
        self.branch = branch
        self.target = target
        self.projectRoot = projectRoot
        self.eventBus = eventBus
    }

    public func shell(_ command: String) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = projectRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read pipes BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ShellResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    public func emit(_ event: ShikiEvent) async {
        await eventBus?.publish(event)
    }
}

// MARK: - DryRunShipContext

/// Dry-run context: captures shell calls without executing. Still emits events.
public actor DryRunShipContext: ShipContext {
    public let isDryRun = true
    public let branch: String
    public let target: String
    public let projectRoot: URL
    private let eventBus: InProcessEventBus?
    private var _capturedCommands: [String] = []

    public var capturedCommands: [String] {
        _capturedCommands
    }

    public init(branch: String, target: String, projectRoot: URL, eventBus: InProcessEventBus? = nil) {
        self.branch = branch
        self.target = target
        self.projectRoot = projectRoot
        self.eventBus = eventBus
    }

    public func shell(_ command: String) async throws -> ShellResult {
        _capturedCommands.append(command)
        // Return successful no-op for dry-run
        return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }

    public func emit(_ event: ShikiEvent) async {
        await eventBus?.publish(event)
    }
}
