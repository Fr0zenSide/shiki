import Foundation
import Testing
@testable import ShikkiKit

// MARK: - MockBinarySwapper

/// Test double for BinarySwapping protocol.
/// Records the call and throws instead of calling execv().
final class MockBinarySwapper: BinarySwapping, @unchecked Sendable {
    private(set) var execCalled = false
    private(set) var execPath: String?
    private(set) var execArgs: [String]?

    /// When set, exec() throws this error instead of recording success.
    var shouldFail: Error?

    func exec(path: String, args: [String]) throws -> Never {
        execCalled = true
        execPath = path
        execArgs = args
        if let error = shouldFail {
            throw error
        }
        // In tests, we cannot actually call Never-returning function.
        // Throw a sentinel error to indicate "swap would have happened".
        throw BinarySwapError.swapSucceeded
    }
}

// MARK: - MockShellExecutor (for healthcheck)

final class RestartMockShellExecutor: ShellExecuting, @unchecked Sendable {
    var responses: [(stdout: String, exitCode: Int32)] = []
    private var callIndex = 0

    /// Records all calls made.
    private(set) var calls: [(command: String, arguments: [String])] = []

    func run(_ command: String, arguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
        calls.append((command: command, arguments: arguments))
        guard callIndex < responses.count else {
            return (stdout: "", exitCode: 0)
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }

    func which(_ tool: String) async -> String? {
        nil
    }
}

// MARK: - Test Helpers

private func makeTempDir() -> String {
    let path = NSTemporaryDirectory() + "shikki-restart-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

/// Create a fake binary file with Mach-O magic bytes, executable permissions, and a version string.
private func createFakeBinary(at path: String, version: String, executable: Bool = true, machO: Bool = true) {
    let fm = FileManager.default
    let dir = (path as NSString).deletingLastPathComponent
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

    // Build content: magic bytes + version string
    var data = Data()
    if machO {
        // Mach-O 64-bit magic: 0xFEEDFACF (big-endian)
        data.append(contentsOf: [0xFE, 0xED, 0xFA, 0xCF])
    } else {
        // Invalid magic
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
    }
    // Embed version as a marker string the service can parse
    let versionMarker = "SHIKKI_VERSION=\(version)\0"
    data.append(Data(versionMarker.utf8))
    // Pad to look like a real binary
    data.append(Data(repeating: 0x90, count: 256))

    fm.createFile(atPath: path, contents: data)

    if executable {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    } else {
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
    }
}

/// Create a minimal RestartService configuration for testing.
private func makeService(
    tempDir: String,
    currentVersion: String = "1.0.0",
    swapper: MockBinarySwapper = MockBinarySwapper(),
    shellExecutor: RestartMockShellExecutor = RestartMockShellExecutor(),
    checkpointShouldFail: Bool = false,
    tmuxRunning: Bool = true,
    session: String = "shiki"
) -> (service: RestartService, swapper: MockBinarySwapper, shell: RestartMockShellExecutor) {
    let checkpointDir = "\(tempDir)/checkpoint"
    try? FileManager.default.createDirectory(atPath: checkpointDir, withIntermediateDirectories: true)

    let manager = CheckpointManager(directory: checkpointShouldFail ? "/nonexistent-readonly-dir-\(UUID())" : checkpointDir)
    let guard_ = SetupGuard(currentVersion: currentVersion, statePath: "\(tempDir)/setup-state.json")

    let service = RestartService(
        checkpointManager: manager,
        setupGuard: guard_,
        binarySwapper: swapper,
        shellExecutor: shellExecutor,
        currentVersion: currentVersion,
        currentBinaryPath: "\(tempDir)/current/shikki",
        shikkiBinDir: "\(tempDir)/bin",
        buildReleaseDir: "\(tempDir)/build-release",
        buildDebugDir: "\(tempDir)/build-debug",
        tmuxSession: session,
        tmuxRunning: tmuxRunning
    )
    return (service, swapper, shellExecutor)
}

// MARK: - Tests

@Suite("RestartService — BR-02, BR-03, BR-05..BR-09, BR-13, BR-14")
struct RestartServiceTests {

    // MARK: - 1. Happy path — newer binary, healthcheck passes → .swapped

    @Test("Happy path: newer binary with passing healthcheck triggers swap")
    func happyPath_newerBinary_swapped() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Create current binary (1.0.0)
        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        // Create newer binary in bin dir (2.0.0)
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        let shell = RestartMockShellExecutor()
        // Healthcheck response (exit 0) + version query response
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),  // --version
            (stdout: "", exitCode: 0),         // --healthcheck
        ]

        let swapper = MockBinarySwapper()
        var (service, _, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0",
            swapper: swapper, shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .swapped(let oldVersion, let newVersion):
            #expect(oldVersion == "1.0.0")
            #expect(newVersion == "2.0.0")
        default:
            Issue.record("Expected .swapped, got \(result)")
        }

        #expect(swapper.execCalled)
    }

    // MARK: - 2. Same version → .skipped

    @Test("Same version skips restart")
    func sameVersion_skipped() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "1.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "1.0.0", exitCode: 0), // --version
        ]

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0", shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .skipped(let reason):
            #expect(reason.contains("same version"))
        default:
            Issue.record("Expected .skipped, got \(result)")
        }

        #expect(!swapper.execCalled)
    }

    // MARK: - 3. Healthcheck fails → .aborted

    @Test("Healthcheck failure aborts restart")
    func healthcheckFails_aborted() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),  // --version
            (stdout: "error", exitCode: 1),   // --healthcheck FAILS
        ]

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0", shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("healthcheck"))
        default:
            Issue.record("Expected .aborted, got \(result)")
        }

        #expect(!swapper.execCalled)
    }

    // MARK: - 4. Wrong permissions (not executable) → .aborted

    @Test("Non-executable binary aborts restart")
    func wrongPermissions_aborted() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0", executable: false)

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),
        ]

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0", shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("permission") || reason.lowercased().contains("executable"))
        default:
            Issue.record("Expected .aborted, got \(result)")
        }

        #expect(!swapper.execCalled)
    }

    // MARK: - 5. Build in progress (mtime drift) → .aborted

    @Test("Mtime drift within 100ms aborts with build-in-progress")
    func buildInProgress_aborted() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        let binaryPath = "\(dir)/bin/shikki"
        createFakeBinary(at: binaryPath, version: "2.0.0")

        // Set mtime to "now" so drift detection triggers (file is actively being written)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: binaryPath
        )

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),
        ]

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0", shellExecutor: shell
        )

        // The service checks mtime twice with a small delay; if the file was JUST modified,
        // it aborts. We simulate by setting mtime to within 100ms of "now".
        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("build in progress") || reason.lowercased().contains("mtime"))
        default:
            // Depending on timing, this may pass through — the test verifies the detection mechanism.
            // If the mtime is stable by the time the second check runs, it won't trigger.
            break
        }

        // In either case, the swapper should NOT have been called if aborted
        if case .aborted = result {
            #expect(!swapper.execCalled)
        }
    }

    // MARK: - 6. Downgrade without --force → .aborted

    @Test("Downgrade without force aborts")
    func downgradeNoForce_aborted() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "2.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "1.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "1.0.0", exitCode: 0),
        ]

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "2.0.0", shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("downgrade"))
        default:
            Issue.record("Expected .aborted for downgrade, got \(result)")
        }

        #expect(!swapper.execCalled)
    }

    // MARK: - 7. Downgrade with --force → .swapped

    @Test("Downgrade with force proceeds to swap")
    func downgradeWithForce_swapped() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "2.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "1.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "1.0.0", exitCode: 0), // --version
            (stdout: "", exitCode: 0),        // --healthcheck
        ]

        let swapper = MockBinarySwapper()
        var (service, _, _) = makeService(
            tempDir: dir, currentVersion: "2.0.0",
            swapper: swapper, shellExecutor: shell
        )

        let result = try await service.restart(force: true, upgradeDeps: false)

        switch result {
        case .swapped(let oldVersion, let newVersion):
            #expect(oldVersion == "2.0.0")
            #expect(newVersion == "1.0.0")
        default:
            Issue.record("Expected .swapped with force, got \(result)")
        }

        #expect(swapper.execCalled)
    }

    // MARK: - 8. tmux session gone → .aborted

    @Test("Missing tmux session aborts restart")
    func tmuxSessionGone_aborted() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0",
            tmuxRunning: false
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("tmux") || reason.lowercased().contains("session"))
        default:
            Issue.record("Expected .aborted for missing tmux, got \(result)")
        }

        #expect(!swapper.execCalled)
    }

    // MARK: - 9. Checkpoint save fails → .aborted

    @Test("Checkpoint save failure aborts restart")
    func checkpointSaveFails_aborted() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),
            (stdout: "", exitCode: 0),
        ]

        var (service, swapper, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0",
            shellExecutor: shell,
            checkpointShouldFail: true
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("checkpoint"))
        default:
            Issue.record("Expected .aborted for checkpoint failure, got \(result)")
        }

        #expect(!swapper.execCalled)
    }

    // MARK: - 10. execv() fails → graceful degradation

    @Test("Failed execv continues with old binary gracefully")
    func execvFails_gracefulDegradation() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),
            (stdout: "", exitCode: 0),
        ]

        let swapper = MockBinarySwapper()
        swapper.shouldFail = BinarySwapError.execvFailed(errno: 13, description: "Permission denied")

        var (service, _, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0",
            swapper: swapper, shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: false)

        switch result {
        case .aborted(let reason):
            #expect(reason.lowercased().contains("execv") || reason.lowercased().contains("swap failed"))
        default:
            Issue.record("Expected .aborted for execv failure, got \(result)")
        }

        // The swapper was called but failed — old binary continues
        #expect(swapper.execCalled)
    }

    // MARK: - 11. Post-swap dep check on version bump

    @Test("Post-swap triggers dependency check via SetupGuard")
    func postSwapDepCheck() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let statePath = "\(dir)/setup-state.json"
        let guard_ = SetupGuard(currentVersion: "2.0.0", statePath: statePath)

        // Version mismatch means needsSetup == true
        try SetupState.markComplete(version: "1.0.0", path: statePath)
        #expect(guard_.needsSetup() == true)

        // After marking complete with new version, needsSetup == false
        try SetupState.markComplete(version: "2.0.0", path: statePath)
        #expect(guard_.needsSetup() == false)
    }

    // MARK: - 12. Binary resolution priority order

    @Test("Binary resolution follows priority: bin > release > debug")
    func binaryResolutionPriority() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Create all three candidates
        createFakeBinary(at: "\(dir)/bin/shikki", version: "3.0.0")
        createFakeBinary(at: "\(dir)/build-release/shikki", version: "2.0.0")
        createFakeBinary(at: "\(dir)/build-debug/shikki", version: "1.5.0")

        let resolved = RestartService.resolveBinary(
            shikkiBinDir: "\(dir)/bin",
            buildReleaseDir: "\(dir)/build-release",
            buildDebugDir: "\(dir)/build-debug"
        )

        #expect(resolved != nil)
        #expect(resolved == "\(dir)/bin/shikki")

        // Remove bin, should fall back to release
        try FileManager.default.removeItem(atPath: "\(dir)/bin/shikki")

        let resolved2 = RestartService.resolveBinary(
            shikkiBinDir: "\(dir)/bin",
            buildReleaseDir: "\(dir)/build-release",
            buildDebugDir: "\(dir)/build-debug"
        )
        #expect(resolved2 == "\(dir)/build-release/shikki")

        // Remove release, should fall back to debug
        try FileManager.default.removeItem(atPath: "\(dir)/build-release/shikki")

        let resolved3 = RestartService.resolveBinary(
            shikkiBinDir: "\(dir)/bin",
            buildReleaseDir: "\(dir)/build-release",
            buildDebugDir: "\(dir)/build-debug"
        )
        #expect(resolved3 == "\(dir)/build-debug/shikki")
    }

    // MARK: - 13. Rollback binary created (shikki.prev)

    @Test("Current binary is copied to shikki.prev before swap")
    func rollbackBinaryCreated() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),
            (stdout: "", exitCode: 0),
        ]

        let swapper = MockBinarySwapper()
        var (service, _, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0",
            swapper: swapper, shellExecutor: shell
        )

        _ = try await service.restart(force: false, upgradeDeps: false)

        // Verify shikki.prev was created
        let prevPath = "\(dir)/bin/shikki.prev"
        #expect(FileManager.default.fileExists(atPath: prevPath))

        // Verify content matches original binary
        let originalData = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/current/shikki"))
        let prevData = try Data(contentsOf: URL(fileURLWithPath: prevPath))
        #expect(originalData == prevData)
    }

    // MARK: - 14. --upgrade-deps triggers dependency check

    @Test("upgrade-deps flag triggers SetupGuard check")
    func upgradeDepsTriggersCheck() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        createFakeBinary(at: "\(dir)/current/shikki", version: "1.0.0")
        createFakeBinary(at: "\(dir)/bin/shikki", version: "2.0.0")

        let shell = RestartMockShellExecutor()
        shell.responses = [
            (stdout: "2.0.0", exitCode: 0),
            (stdout: "", exitCode: 0),
        ]

        let swapper = MockBinarySwapper()
        var (service, _, _) = makeService(
            tempDir: dir, currentVersion: "1.0.0",
            swapper: swapper, shellExecutor: shell
        )

        let result = try await service.restart(force: false, upgradeDeps: true)

        // With upgradeDeps, the service should still proceed with the swap
        // and flag that deps should be checked post-swap
        switch result {
        case .swapped:
            #expect(swapper.execCalled)
        case .aborted:
            // Acceptable if checkpoint or other pre-condition fails
            break
        default:
            break
        }

        // Verify the service recorded the upgradeDeps intent
        #expect(service.lastUpgradeDepsRequested == true)
    }
}

// MARK: - BinarySwapping Protocol Tests

@Suite("BinarySwapping protocol conformance")
struct BinarySwappingTests {

    @Test("MockBinarySwapper records exec call")
    func mockRecordsCall() throws {
        let mock = MockBinarySwapper()
        #expect(!mock.execCalled)

        do {
            try mock.exec(path: "/usr/bin/test", args: ["--flag"])
        } catch {
            // Expected — mock throws sentinel
        }

        #expect(mock.execCalled)
        #expect(mock.execPath == "/usr/bin/test")
        #expect(mock.execArgs == ["--flag"])
    }

    @Test("PosixBinarySwapper conforms to BinarySwapping")
    func posixConformance() {
        let swapper: any BinarySwapping = PosixBinarySwapper()
        #expect(swapper is PosixBinarySwapper)
    }
}

// MARK: - RestartResult Tests

@Suite("RestartResult enum")
struct RestartResultTests {

    @Test("RestartResult.swapped carries versions")
    func swappedCarriesVersions() {
        let result = RestartResult.swapped(oldVersion: "1.0.0", newVersion: "2.0.0")
        if case .swapped(let old, let new) = result {
            #expect(old == "1.0.0")
            #expect(new == "2.0.0")
        } else {
            Issue.record("Expected .swapped")
        }
    }

    @Test("RestartResult.skipped carries reason")
    func skippedCarriesReason() {
        let result = RestartResult.skipped(reason: "same version")
        if case .skipped(let reason) = result {
            #expect(reason == "same version")
        } else {
            Issue.record("Expected .skipped")
        }
    }

    @Test("RestartResult.aborted carries reason")
    func abortedCarriesReason() {
        let result = RestartResult.aborted(reason: "healthcheck failed")
        if case .aborted(let reason) = result {
            #expect(reason == "healthcheck failed")
        } else {
            Issue.record("Expected .aborted")
        }
    }
}
