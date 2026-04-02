import Foundation

// MARK: - PluginExecutionResult

/// The result of executing a plugin subprocess.
public struct PluginExecutionResult: Sendable {
    /// Standard output from the plugin process.
    public let stdout: String

    /// Standard error from the plugin process.
    public let stderr: String

    /// The process exit code.
    public let exitCode: Int32

    /// Whether the plugin executed successfully (exit code 0).
    public var succeeded: Bool { exitCode == 0 }

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

// MARK: - PluginRunnerError

/// Errors from plugin subprocess execution.
public enum PluginRunnerError: Error, CustomStringConvertible, Sendable {
    case timeout(pluginId: PluginID, duration: Duration)
    case launchFailed(pluginId: PluginID, underlying: String)
    case sandboxViolation(pluginId: PluginID, reason: String)

    public var description: String {
        switch self {
        case .timeout(let id, let duration):
            return "Plugin '\(id)' timed out after \(duration)"
        case .launchFailed(let id, let underlying):
            return "Plugin '\(id)' failed to launch: \(underlying)"
        case .sandboxViolation(let id, let reason):
            return "Plugin '\(id)' sandbox violation: \(reason)"
        }
    }
}

// MARK: - PluginRunner

/// Subprocess isolation for plugin execution.
///
/// Business Rules:
/// - BR-07: Subprocess execution with sanitized env (no inherited secrets)
/// - BR-10: Plugin crash does not crash ShikkiKit (subprocess isolation)
public actor PluginRunner {

    /// Environment variables allowed to pass through to plugin subprocesses.
    public static let allowedEnvVars: Set<String> = [
        "PATH",
        "HOME",
        "LANG",
        "TERM",
        "TMPDIR",
        "USER",
        "SHELL",
        "LC_ALL",
        "LC_CTYPE",
    ]

    /// The plugin this runner manages.
    public let pluginId: PluginID

    /// The scoped directory for this plugin's data.
    public let scopeDirectory: String

    /// The sandbox for access validation.
    private let sandbox: PluginSandbox

    /// Security violations recorded during execution.
    private(set) var violations: [SecurityViolation] = []

    /// Whether this plugin has been marked as crashed.
    private(set) var hasCrashed: Bool = false

    public init(
        pluginId: PluginID,
        scopeDirectory: String,
        declaredPaths: [String] = [],
        certification: CertificationLevel = .uncertified
    ) {
        self.pluginId = pluginId
        self.scopeDirectory = scopeDirectory
        self.sandbox = PluginSandbox(
            pluginId: pluginId,
            scopeDirectory: scopeDirectory,
            declaredPaths: declaredPaths,
            certification: certification
        )
    }

    // MARK: - Environment Sanitization

    /// Build a sanitized environment dictionary for plugin subprocess.
    /// Only allowed variables from the current environment are included.
    /// Secret-bearing variables are stripped.
    public func sanitizedEnvironment() -> [String: String] {
        let currentEnv = ProcessInfo.processInfo.environment
        var sanitized: [String: String] = [:]

        for key in Self.allowedEnvVars {
            if let value = currentEnv[key] {
                sanitized[key] = value
            }
        }

        return sanitized
    }

    // MARK: - Execution

    /// Execute a plugin command as a subprocess with full isolation.
    ///
    /// - Parameters:
    ///   - arguments: The command and arguments to execute (e.g., `["/usr/bin/python3", "plugin.py"]`)
    ///   - timeout: Maximum time the plugin may run before being terminated.
    /// - Returns: The execution result including stdout, stderr, and exit code.
    public func execute(
        arguments: [String],
        timeout: Duration = .seconds(30)
    ) async -> PluginExecutionResult {
        guard !arguments.isEmpty else {
            return PluginExecutionResult(
                stdout: "",
                stderr: "No arguments provided",
                exitCode: 1
            )
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: arguments[0])
        if arguments.count > 1 {
            process.arguments = Array(arguments.dropFirst())
        }

        // BR-07: Sanitized environment
        process.environment = sanitizedEnvironment()

        // Set working directory to the plugin's scoped directory
        process.currentDirectoryURL = URL(fileURLWithPath: scopeDirectory)

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // BR-10: Catch any launch failure without crashing
        do {
            try process.run()
        } catch {
            hasCrashed = true
            return PluginExecutionResult(
                stdout: "",
                stderr: "Failed to launch: \(error.localizedDescription)",
                exitCode: 127
            )
        }

        // Wait with timeout
        let timeoutNanos = UInt64(timeout.components.seconds) * 1_000_000_000
            + UInt64(timeout.components.attoseconds / 1_000_000_000)

        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return false
            }

            guard let first = await group.next() else { return false }

            if !first {
                // Timeout hit first — terminate the process
                process.terminate()
            }

            group.cancelAll()
            return first
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        if !completed {
            hasCrashed = true
            return PluginExecutionResult(
                stdout: stdoutStr,
                stderr: stderrStr + "\nPlugin timed out",
                exitCode: -1
            )
        }

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            hasCrashed = true
        }

        return PluginExecutionResult(
            stdout: stdoutStr,
            stderr: stderrStr,
            exitCode: exitCode
        )
    }

    // MARK: - Violation Recording

    /// Record a security violation for this plugin.
    public func recordViolation(_ violation: SecurityViolation) {
        violations.append(violation)
    }

    /// Mark this plugin as crashed (used by PluginRegistry).
    public func markAsCrashed() {
        hasCrashed = true
    }
}
