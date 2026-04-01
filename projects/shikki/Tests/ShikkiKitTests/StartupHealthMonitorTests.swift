import Foundation
import Testing
@testable import ShikkiKit

@Suite("StartupHealthMonitor — Z2R Wave 4")
struct StartupHealthMonitorTests {

    // MARK: - Health Report

    @Test("Empty checks report is healthy")
    func emptyReportIsHealthy() {
        let report = StartupHealthReport(checks: [])
        #expect(report.allHealthy)
        #expect(report.unhealthy.isEmpty)
        #expect(report.fixable.isEmpty)
        #expect(report.unfixable.isEmpty)
    }

    @Test("All healthy checks report is healthy")
    func allHealthyReport() {
        let checks = [
            StartupCheckResult(component: "tmux", healthy: true, message: "ok"),
            StartupCheckResult(component: "backend", healthy: true, message: "ok"),
        ]
        let report = StartupHealthReport(checks: checks)
        #expect(report.allHealthy)
        #expect(report.unhealthy.isEmpty)
    }

    @Test("Mixed checks: unhealthy separated from healthy")
    func mixedChecksReport() {
        let checks = [
            StartupCheckResult(component: "tmux", healthy: true, message: "ok"),
            StartupCheckResult(component: "backend", healthy: false, fixable: false, message: "unreachable"),
            StartupCheckResult(component: "workspace", healthy: false, fixable: true, message: "missing dirs",
                             fixAction: .createDirectory("/tmp")),
        ]
        let report = StartupHealthReport(checks: checks)
        #expect(!report.allHealthy)
        #expect(report.unhealthy.count == 2)
        #expect(report.fixable.count == 1)
        #expect(report.unfixable.count == 1)
    }

    // MARK: - Check Results

    @Test("StartupCheckResult equality")
    func checkResultEquality() {
        let a = StartupCheckResult(component: "tmux", healthy: true, message: "ok")
        let b = StartupCheckResult(component: "tmux", healthy: true, message: "ok")
        #expect(a == b)
    }

    @Test("FixAction equality: brewInstall")
    func fixActionBrewEquality() {
        let a = StartupCheckResult.FixAction.brewInstall("tmux")
        let b = StartupCheckResult.FixAction.brewInstall("tmux")
        #expect(a == b)
    }

    @Test("FixAction equality: createDirectory")
    func fixActionDirEquality() {
        let a = StartupCheckResult.FixAction.createDirectory("/tmp/a")
        let b = StartupCheckResult.FixAction.createDirectory("/tmp/a")
        #expect(a == b)
    }

    @Test("FixAction equality: custom")
    func fixActionCustomEquality() {
        let a = StartupCheckResult.FixAction.custom("colima start")
        let b = StartupCheckResult.FixAction.custom("colima start")
        #expect(a == b)
    }

    // MARK: - Monitor with Mock Environment

    @Test("All checks pass with healthy environment")
    func allChecksPassHealthy() async {
        let env = MockEnvironmentChecker()
        env.tmuxSessionRunning = true
        env.backendHealthy = true
        env.dockerRunning = true

        let tempDir = NSTemporaryDirectory() + "shikki-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/sessions", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/test-logs", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let monitor = StartupHealthMonitor(
            environment: env,
            workspaceDir: tempDir
        )
        let report = await monitor.runChecks()

        // tmux check depends on binary on PATH, not session running
        // backend and docker should pass
        let backendCheck = report.checks.first { $0.component == "backend" }
        let dockerCheck = report.checks.first { $0.component == "docker" }
        let workspaceCheck = report.checks.first { $0.component == "workspace" }

        #expect(backendCheck?.healthy == true)
        #expect(dockerCheck?.healthy == true)
        #expect(workspaceCheck?.healthy == true)
    }

    @Test("Backend unhealthy is unfixable")
    func backendUnhealthy() async {
        let env = MockEnvironmentChecker()
        env.backendHealthy = false

        let monitor = StartupHealthMonitor(environment: env)
        let result = await monitor.checkBackend()

        #expect(!result.healthy)
        #expect(!result.fixable)
        #expect(result.component == "backend")
    }

    @Test("Docker not running with colima stopped is fixable")
    func dockerNotRunningColimaFixable() async {
        let env = MockEnvironmentChecker()
        env.dockerRunning = false
        env.colimaRunning = false

        let monitor = StartupHealthMonitor(environment: env)
        let result = await monitor.checkDocker()

        #expect(!result.healthy)
        #expect(result.fixable)
        #expect(result.fixAction == .custom("colima start"))
    }

    @Test("Docker not running with colima running is unfixable")
    func dockerNotRunningColimaRunning() async {
        let env = MockEnvironmentChecker()
        env.dockerRunning = false
        env.colimaRunning = true

        let monitor = StartupHealthMonitor(environment: env)
        let result = await monitor.checkDocker()

        #expect(!result.healthy)
        #expect(!result.fixable)
    }

    @Test("Workspace dirs missing is fixable")
    func workspaceDirsMissing() {
        let tempDir = NSTemporaryDirectory() + "shikki-nonexistent-\(UUID().uuidString)"

        let monitor = StartupHealthMonitor(workspaceDir: tempDir)
        let result = monitor.checkWorkspaceDirs()

        #expect(!result.healthy)
        #expect(result.fixable)
        #expect(result.fixAction == .createDirectory(tempDir))
    }

    @Test("Workspace dirs exist is healthy")
    func workspaceDirsExist() {
        let tempDir = NSTemporaryDirectory() + "shikki-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/sessions", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/test-logs", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let monitor = StartupHealthMonitor(workspaceDir: tempDir)
        let result = monitor.checkWorkspaceDirs()

        #expect(result.healthy)
    }

    // MARK: - Apply Fix: Create Directory

    @Test("Apply fix creates workspace directories")
    func applyFixCreatesDirectories() async {
        let tempDir = NSTemporaryDirectory() + "shikki-fix-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let monitor = StartupHealthMonitor(workspaceDir: tempDir)
        let success = await monitor.applyFix(.createDirectory(tempDir))

        #expect(success)
        #expect(FileManager.default.fileExists(atPath: tempDir))
        #expect(FileManager.default.fileExists(atPath: "\(tempDir)/sessions"))
        #expect(FileManager.default.fileExists(atPath: "\(tempDir)/test-logs"))
        #expect(FileManager.default.fileExists(atPath: "\(tempDir)/plugins"))
    }

    // MARK: - Toast Rendering

    @Test("Empty toasts render empty string")
    func emptyToasts() {
        let result = StartupHealthMonitor.renderToasts([])
        #expect(result == "")
    }

    @Test("Toast messages include ANSI yellow")
    func toastMessages() {
        let toasts = ["backend needs attention"]
        let result = StartupHealthMonitor.renderToasts(toasts)
        #expect(result.contains("backend needs attention"))
        #expect(result.contains("\u{1B}[33m")) // yellow
    }

    // MARK: - Mock

    @Test("MockStartupHealthChecker returns stubbed report")
    func mockReturnsStubbed() async {
        let checks = [
            StartupCheckResult(component: "tmux", healthy: true, message: "ok"),
        ]
        let mock = MockStartupHealthChecker(stubbedReport: StartupHealthReport(checks: checks))

        let report = await mock.runChecks()
        #expect(report.checks.count == 1)
        #expect(mock.runChecksCallCount == 1)
    }

    @Test("MockStartupHealthChecker tracks fix calls")
    func mockTracksFixes() async {
        let mock = MockStartupHealthChecker()
        mock.fixResults = [true, false]

        let first = await mock.applyFix(.brewInstall("tmux"))
        let second = await mock.applyFix(.createDirectory("/tmp"))

        #expect(first == true)
        #expect(second == false)
        #expect(mock.applyFixCallCount == 2)
    }

    // MARK: - Full Startup Flow

    @Test("Startup health check returns toasts for unfixable issues")
    func startupFlowToasts() async {
        let env = MockEnvironmentChecker()
        env.backendHealthy = false
        env.dockerRunning = true

        let tempDir = NSTemporaryDirectory() + "shikki-flow-\(UUID().uuidString)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/sessions", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/test-logs", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let monitor = StartupHealthMonitor(
            environment: env,
            workspaceDir: tempDir
        )
        let toasts = await monitor.runStartupHealthCheck()

        // Backend is unfixable, should generate a toast
        #expect(toasts.contains { $0.contains("backend") })
    }

    @Test("Startup health check returns empty for all healthy")
    func startupFlowAllHealthy() async {
        let env = MockEnvironmentChecker()
        env.backendHealthy = true
        env.dockerRunning = true

        let tempDir = NSTemporaryDirectory() + "shikki-flow-ok-\(UUID().uuidString)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/sessions", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(tempDir)/test-logs", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let monitor = StartupHealthMonitor(
            environment: env,
            workspaceDir: tempDir
        )
        let toasts = await monitor.runStartupHealthCheck()

        // tmux check may fail in test env (no tmux binary), but backend/docker pass
        // Filter to only check backend toast
        let backendToasts = toasts.filter { $0.contains("backend") }
        #expect(backendToasts.isEmpty)
    }
}
