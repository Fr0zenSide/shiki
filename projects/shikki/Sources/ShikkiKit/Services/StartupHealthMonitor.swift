import Foundation
import Logging

// MARK: - Health Check Result

/// Result of a single startup health check.
public struct StartupCheckResult: Sendable, Equatable {
    public let component: String
    public let healthy: Bool
    public let fixable: Bool
    public let message: String
    public let fixAction: FixAction?

    public init(
        component: String,
        healthy: Bool,
        fixable: Bool = false,
        message: String,
        fixAction: FixAction? = nil
    ) {
        self.component = component
        self.healthy = healthy
        self.fixable = fixable
        self.message = message
        self.fixAction = fixAction
    }

    /// Action the monitor can take to fix the issue.
    public enum FixAction: Sendable, Equatable {
        case brewInstall(String)
        case createDirectory(String)
        case custom(String)
    }
}

/// Overall startup health report.
public struct StartupHealthReport: Sendable, Equatable {
    public let checks: [StartupCheckResult]
    public let timestamp: Date

    public init(checks: [StartupCheckResult], timestamp: Date = Date()) {
        self.checks = checks
        self.timestamp = timestamp
    }

    /// All checks passed.
    public var allHealthy: Bool {
        checks.allSatisfy(\.healthy)
    }

    /// Checks that failed.
    public var unhealthy: [StartupCheckResult] {
        checks.filter { !$0.healthy }
    }

    /// Checks that failed but can be auto-fixed.
    public var fixable: [StartupCheckResult] {
        checks.filter { !$0.healthy && $0.fixable }
    }

    /// Checks that failed and cannot be auto-fixed.
    public var unfixable: [StartupCheckResult] {
        checks.filter { !$0.healthy && !$0.fixable }
    }
}

// MARK: - StartupHealthChecking Protocol

/// Abstraction for health checking, enabling test doubles.
public protocol StartupHealthChecking: Sendable {
    func runChecks() async -> StartupHealthReport
    func applyFix(_ fix: StartupCheckResult.FixAction) async -> Bool
}

// MARK: - StartupHealthMonitor

/// Silent health monitor that runs on every `shikki start`.
/// Checks: tmux available, backend reachable (optional), docker healthy (optional),
/// workspace directories exist. Auto-fixes when possible, toasts when not.
///
/// Design: Never blocks startup on optional services (backend, docker).
/// Only tmux and workspace dirs are required.
public struct StartupHealthMonitor: StartupHealthChecking, Sendable {
    private let environment: any EnvironmentChecking
    private let backendURL: String
    private let workspaceDir: String
    private let logger: Logger

    public init(
        environment: any EnvironmentChecking = EnvironmentDetector(),
        backendURL: String = "http://localhost:3900",
        workspaceDir: String? = nil,
        logger: Logger = Logger(label: "shikki.startup-health")
    ) {
        self.environment = environment
        self.backendURL = backendURL
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.workspaceDir = workspaceDir ?? "\(home)/.shikki"
        self.logger = logger
    }

    // MARK: - Run All Checks

    /// Run all health checks silently. Returns a report of results.
    public func runChecks() async -> StartupHealthReport {
        var checks: [StartupCheckResult] = []

        // 1. tmux available (required)
        checks.append(await checkTmux())

        // 2. Workspace directories exist (required, fixable)
        checks.append(checkWorkspaceDirs())

        // 3. Backend reachable (optional — don't block startup)
        checks.append(await checkBackend())

        // 4. Docker/Colima healthy (optional)
        checks.append(await checkDocker())

        return StartupHealthReport(checks: checks)
    }

    // MARK: - Individual Checks

    /// Check if tmux is running and available.
    func checkTmux() async -> StartupCheckResult {
        let running = await environment.isTmuxSessionRunning(name: "shikki")
        // Even if no session exists, tmux binary must be available
        let binaryAvailable = environment.binaryExists(at: "/usr/bin/env")
        let tmuxCheck = checkBinaryOnPath("tmux")

        if tmuxCheck {
            return StartupCheckResult(
                component: "tmux",
                healthy: true,
                message: "tmux available"
            )
        }

        return StartupCheckResult(
            component: "tmux",
            healthy: false,
            fixable: true,
            message: "tmux not found on PATH",
            fixAction: .brewInstall("tmux")
        )
    }

    /// Check workspace directories exist.
    func checkWorkspaceDirs() -> StartupCheckResult {
        let fm = FileManager.default
        let requiredDirs = [
            workspaceDir,
            "\(workspaceDir)/sessions",
            "\(workspaceDir)/test-logs",
        ]

        let missing = requiredDirs.filter { !fm.fileExists(atPath: $0) }

        if missing.isEmpty {
            return StartupCheckResult(
                component: "workspace",
                healthy: true,
                message: "workspace directories OK"
            )
        }

        return StartupCheckResult(
            component: "workspace",
            healthy: false,
            fixable: true,
            message: "\(missing.count) workspace dir(s) missing",
            fixAction: .createDirectory(workspaceDir)
        )
    }

    /// Check backend API reachability (optional).
    func checkBackend() async -> StartupCheckResult {
        let healthy = await environment.isBackendHealthy(url: backendURL)

        if healthy {
            return StartupCheckResult(
                component: "backend",
                healthy: true,
                message: "backend reachable"
            )
        }

        return StartupCheckResult(
            component: "backend",
            healthy: false,
            fixable: false,
            message: "backend unreachable at \(backendURL)"
        )
    }

    /// Check Docker/Colima health (optional).
    func checkDocker() async -> StartupCheckResult {
        let dockerRunning = await environment.isDockerRunning()

        if dockerRunning {
            return StartupCheckResult(
                component: "docker",
                healthy: true,
                message: "docker running"
            )
        }

        // Check if Colima is available but not started
        let colimaRunning = await environment.isColimaRunning()
        if !colimaRunning {
            return StartupCheckResult(
                component: "docker",
                healthy: false,
                fixable: true,
                message: "docker not running (colima stopped)",
                fixAction: .custom("colima start")
            )
        }

        return StartupCheckResult(
            component: "docker",
            healthy: false,
            fixable: false,
            message: "docker not running"
        )
    }

    // MARK: - Apply Fixes

    /// Attempt to apply a fix action. Returns true on success.
    public func applyFix(_ fix: StartupCheckResult.FixAction) async -> Bool {
        switch fix {
        case .brewInstall(let formula):
            return await runProcess("/usr/bin/env", arguments: ["brew", "install", formula])
        case .createDirectory(let baseDir):
            return createWorkspaceDirs(baseDir)
        case .custom(let command):
            let parts = command.split(separator: " ").map(String.init)
            guard !parts.isEmpty else { return false }
            return await runProcess("/usr/bin/env", arguments: parts)
        }
    }

    // MARK: - Startup Integration

    /// Run the full startup health check flow:
    /// 1. Run all checks silently
    /// 2. Auto-fix fixable issues
    /// 3. Toast unfixable issues
    /// Returns the list of toast messages for unfixable issues.
    public func runStartupHealthCheck() async -> [String] {
        let report = await runChecks()

        if report.allHealthy {
            logger.debug("All startup health checks passed")
            return []
        }

        // Auto-fix fixable issues
        for check in report.fixable {
            if let fix = check.fixAction {
                logger.info("Auto-fixing: \(check.component) — \(check.message)")
                let success = await applyFix(fix)
                if success {
                    logger.info("Fixed: \(check.component)")
                } else {
                    logger.warning("Auto-fix failed for \(check.component)")
                }
            }
        }

        // Generate toast messages for unfixable issues
        let toasts = report.unfixable.map { check in
            "\u{26A0}\u{FE0F} \(check.component) needs attention \u{2014} run shikki doctor"
        }

        return toasts
    }

    /// Format toast messages for terminal output.
    public static func renderToasts(_ toasts: [String]) -> String {
        guard !toasts.isEmpty else { return "" }
        return toasts.map { "  \u{1B}[33m\($0)\u{1B}[0m" }.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func checkBinaryOnPath(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runProcess(_ path: String, arguments: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func createWorkspaceDirs(_ baseDir: String) -> Bool {
        let fm = FileManager.default
        let dirs = [
            baseDir,
            "\(baseDir)/sessions",
            "\(baseDir)/test-logs",
            "\(baseDir)/plugins",
        ]
        do {
            for dir in dirs {
                if !fm.fileExists(atPath: dir) {
                    try fm.createDirectory(
                        atPath: dir,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                }
            }
            return true
        } catch {
            logger.error("Failed to create workspace dirs: \(error)")
            return false
        }
    }
}

// MARK: - Mock for Tests

/// Test double for StartupHealthMonitor.
public final class MockStartupHealthChecker: StartupHealthChecking, @unchecked Sendable {
    public var stubbedReport: StartupHealthReport
    public var fixResults: [Bool] = [true]
    public private(set) var runChecksCallCount = 0
    public private(set) var applyFixCallCount = 0

    public init(
        stubbedReport: StartupHealthReport = StartupHealthReport(checks: [])
    ) {
        self.stubbedReport = stubbedReport
    }

    public func runChecks() async -> StartupHealthReport {
        runChecksCallCount += 1
        return stubbedReport
    }

    public func applyFix(_ fix: StartupCheckResult.FixAction) async -> Bool {
        let index = min(applyFixCallCount, fixResults.count - 1)
        applyFixCallCount += 1
        return fixResults[index]
    }
}
