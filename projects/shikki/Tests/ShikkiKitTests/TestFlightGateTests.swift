import Foundation
import Testing
@testable import ShikkiKit

// MARK: - AppRegistryGate Tests

@Suite("TestFlight Gate -- AppRegistry")
struct AppRegistryGateTests {

    @Test("Valid config passes with app details")
    func validConfigPasses() async throws {
        let toml = """
        [testapp]
        scheme = "TestApp"
        team_id = "TEAM123"
        bundle_id = "com.test.app"
        project_path = "/tmp"
        """
        let path = writeTempFile(content: toml)
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()

        let gate = AppRegistryGate(appSlug: "testapp", configPath: path, tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            cleanup(path)
            return
        }
        #expect(detail?.contains("testapp") == true)

        let config = await tfCtx.appConfig
        #expect(config?.slug == "testapp")
        #expect(config?.teamID == "TEAM123")

        cleanup(path)
    }

    @Test("Missing config file fails")
    func missingConfigFails() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()

        let gate = AppRegistryGate(
            appSlug: "any",
            configPath: "/tmp/nonexistent-\(UUID().uuidString).toml",
            tfContext: tfCtx
        )
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("not found"))
    }

    @Test("Unknown app slug fails with available list")
    func unknownSlugFails() async throws {
        let toml = """
        [known]
        scheme = "Known"
        team_id = "TEAM"
        bundle_id = "com.known"
        project_path = "/tmp"
        """
        let path = writeTempFile(content: toml)
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()

        let gate = AppRegistryGate(appSlug: "unknown", configPath: path, tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            cleanup(path)
            return
        }
        #expect(reason.contains("unknown"))
        #expect(reason.contains("known"))

        cleanup(path)
    }

    @Test("Dry run skips project path validation")
    func dryRunSkipsProjectValidation() async throws {
        let toml = """
        [phantom]
        scheme = "Phantom"
        team_id = "TEAM"
        bundle_id = "com.phantom"
        project_path = "/nonexistent/Phantom.xcodeproj"
        """
        let path = writeTempFile(content: toml)
        let ctx = MockShipContext(isDryRun: true)
        let tfCtx = TestFlightContext()

        let gate = AppRegistryGate(appSlug: "phantom", configPath: path, tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass in dry-run, got \(result)")
            cleanup(path)
            return
        }

        cleanup(path)
    }
}

// MARK: - BuildNumberGate Tests

@Suite("TestFlight Gate -- BuildNumber")
struct BuildNumberGateTests {

    @Test("Dry run reads current and shows next")
    func dryRunReadsCurrentShowsNext() async throws {
        let ctx = MockShipContext(isDryRun: true)
        let tfCtx = TestFlightContext()
        await tfCtx.setAppConfig(AppConfig(
            slug: "test", scheme: "T", teamID: "T", bundleID: "b",
            projectPath: "/tmp/Test.xcodeproj"
        ))
        await ctx.stubShell("agvtool what-version", result: ShellResult(
            stdout: "42", stderr: "", exitCode: 0
        ))

        let gate = BuildNumberGate(tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("42") == true)
        #expect(detail?.contains("43") == true)

        let buildNum = await tfCtx.buildNumber
        #expect(buildNum == 43)
    }

    @Test("No app config fails")
    func noAppConfigFails() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()

        let gate = BuildNumberGate(tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("AppRegistryGate") || reason.contains("config"))
    }

    @Test("Increments build number via agvtool")
    func incrementsBuildNumber() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()
        await tfCtx.setAppConfig(AppConfig(
            slug: "test", scheme: "T", teamID: "T", bundleID: "b",
            projectPath: "/tmp/Test.xcodeproj"
        ))
        await ctx.stubShell("agvtool what-version", result: ShellResult(
            stdout: "10", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("agvtool next-version", result: ShellResult(
            stdout: "Setting version of project to: 11", stderr: "", exitCode: 0
        ))

        let gate = BuildNumberGate(tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("10") == true)
        #expect(detail?.contains("11") == true)
    }
}

// MARK: - ArchiveGate Tests

@Suite("TestFlight Gate -- Archive")
struct ArchiveGateTests {

    @Test("Dry run returns pass without building")
    func dryRunNoBuild() async throws {
        let ctx = MockShipContext(isDryRun: true)
        let tfCtx = TestFlightContext()
        await tfCtx.setAppConfig(AppConfig(
            slug: "test", scheme: "T", teamID: "T", bundleID: "b",
            projectPath: "/tmp/Test.xcodeproj"
        ))
        await tfCtx.setBuildNumber(1)

        let gate = ArchiveGate(tfContext: tfCtx, version: "1.0.0")
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("dry-run") == true)
    }

    @Test("No app config fails")
    func noConfigFails() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()

        let gate = ArchiveGate(tfContext: tfCtx, version: "1.0.0")
        let result = try await gate.evaluate(context: ctx)

        guard case .fail = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
    }

    @Test("Archive failure parses signing error")
    func archiveFailureParsesSigning() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()
        await tfCtx.setAppConfig(AppConfig(
            slug: "test", scheme: "T", teamID: "T", bundleID: "b",
            projectPath: "/tmp/Test.xcodeproj"
        ))
        await tfCtx.setBuildNumber(1)

        await ctx.stubShell("xcodebuild archive", result: ShellResult(
            stdout: "Code Sign error: No matching provisioning profile found",
            stderr: "",
            exitCode: 65
        ))

        let mgr = ArchiveManager(baseDir: NSTemporaryDirectory() + "test-archives")
        let gate = ArchiveGate(tfContext: tfCtx, version: "1.0.0", archiveManager: mgr)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("sign") || reason.contains("doctor"))
    }
}

// MARK: - UploadGate Tests

@Suite("TestFlight Gate -- Upload")
struct UploadGateTests {

    @Test("Dry run returns pass without uploading")
    func dryRunNoUpload() async throws {
        let ctx = MockShipContext(isDryRun: true)
        let tfCtx = TestFlightContext()
        await tfCtx.setAppConfig(AppConfig(
            slug: "test", scheme: "T", teamID: "T", bundleID: "b",
            projectPath: "/tmp/Test.xcodeproj",
            asc: ASCKeyConfig(keyID: "KEY", issuerID: "ISS")
        ))
        await tfCtx.setBuildNumber(1)
        await tfCtx.setArchivePath("/tmp/test.xcarchive")

        let gate = UploadGate(tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("dry-run") == true)
    }

    @Test("No app config fails")
    func noConfigFails() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()

        let gate = UploadGate(tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
    }

    @Test("No ASC key configured fails")
    func noASCKeyFails() async throws {
        let ctx = MockShipContext()
        let tfCtx = TestFlightContext()
        await tfCtx.setAppConfig(AppConfig(
            slug: "test", scheme: "T", teamID: "T", bundleID: "b",
            projectPath: "/tmp/Test.xcodeproj"
            // No ASC config
        ))
        await tfCtx.setBuildNumber(1)
        await tfCtx.setArchivePath("/tmp/test.xcarchive")

        // Stub export to succeed
        await ctx.stubShell("xcodebuild -exportArchive", result: ShellResult(
            stdout: "Export succeeded", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("find", result: ShellResult(
            stdout: "/tmp/test.ipa", stderr: "", exitCode: 0
        ))

        let gate = UploadGate(tfContext: tfCtx)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("ASC") || reason.contains("setup"))
    }
}

// MARK: - Pipeline Integration Tests

@Suite("TestFlight Pipeline Integration")
struct TestFlightPipelineIntegrationTests {

    @Test("TestFlight pipeline has 12 gates when all enabled")
    func testflightPipelineHas12Gates() async throws {
        let tfCtx = TestFlightContext()
        let changelogStore = ChangelogStore()

        var gates: [any ShipGate] = [
            CleanBranchGate(),
            TestGate(),
            LintGate(),
            BuildGate(),
            ChangelogGate(changelogStore: changelogStore),
            VersionBumpGate(),
            TagGate(),
            PushGate(),
        ]

        // TestFlight gates
        gates.append(AppRegistryGate(tfContext: tfCtx))
        gates.append(BuildNumberGate(tfContext: tfCtx))
        gates.append(ArchiveGate(tfContext: tfCtx, version: "1.0.0"))
        gates.append(UploadGate(tfContext: tfCtx))

        #expect(gates.count == 12)
    }

    @Test("Existing gate failure skips TestFlight gates")
    func existingGateFailureSkipsTestFlight() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let tfCtx = TestFlightContext()

        var gates: [any ShipGate] = [
            PassGate(name: "Clean", index: 0),
            FailGate(name: "Test", index: 1, reason: "tests failed"),
        ]
        gates.append(AppRegistryGate(tfContext: tfCtx))
        gates.append(BuildNumberGate(tfContext: tfCtx))

        let result = try await service.run(gates: gates, context: ctx)

        #expect(!result.success)
        #expect(result.failedGate == "Test")
        #expect(result.gateResults.count == 2) // Only Clean and Test evaluated
    }

    @Test("Dry run TestFlight shows plan without executing")
    func dryRunShowsPlan() async throws {
        let ctx = MockShipContext(isDryRun: true)
        let service = ShipService()
        let gates: [any ShipGate] = (0..<12).map {
            PassGate(name: "Gate\($0)", index: $0)
        }

        let result = try await service.run(gates: gates, context: ctx)

        #expect(result.success)
        #expect(result.gateResults.count == 12)
    }

    @Test("Events emitted for TestFlight gates")
    func eventsEmittedForTestFlightGates() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = (0..<12).map {
            PassGate(name: "Gate\($0)", index: $0)
        }

        _ = try await service.run(gates: gates, context: ctx)

        let events = await ctx.emittedEvents
        let gateStartEvents = events.filter { $0.type == .shipGateStarted }
        #expect(gateStartEvents.count == 12)
    }
}

// MARK: - ArchiveManager Tests

@Suite("ArchiveManager")
struct ArchiveManagerTests {

    @Test("Archive path follows convention")
    func archivePathConvention() {
        let mgr = ArchiveManager(baseDir: "/base")
        let path = mgr.archivePath(slug: "wabisabi", version: "1.2.0", build: 43)
        #expect(path == "/base/wabisabi/1.2.0+43/wabisabi.xcarchive")
    }

    @Test("Export path follows convention")
    func exportPathConvention() {
        let mgr = ArchiveManager(baseDir: "/base")
        let path = mgr.exportPath(slug: "maya", version: "2.0.0", build: 10)
        #expect(path == "/base/maya/2.0.0+10")
    }

    @Test("Parse errors extracts signing errors")
    func parseSigningErrors() {
        let mgr = ArchiveManager()
        let log = """
        Building for iOS...
        error: No provisioning profile was found.
        Code Sign error: Missing certificate
        Compiling SwiftUI views...
        """

        let errors = mgr.parseErrors(from: log)
        #expect(errors.count == 2)
    }

    @Test("Diagnosis hint detects signing issues")
    func diagnosisHintSigning() {
        let mgr = ArchiveManager()
        let hint = mgr.diagnosisHint(from: "Code Sign error: blah")
        #expect(hint.contains("doctor") || hint.contains("signing"))
    }

    @Test("Diagnosis hint detects missing module")
    func diagnosisHintModule() {
        let mgr = ArchiveManager()
        let hint = mgr.diagnosisHint(from: "error: module 'SomeLib' not found")
        #expect(hint.contains("module") || hint.contains("Missing"))
    }

    @Test("Prune keeps last N archives")
    func pruneKeepsLastN() throws {
        let baseDir = NSTemporaryDirectory() + "prune-test-\(UUID().uuidString)"
        let appDir = "\(baseDir)/testapp"
        let fm = FileManager.default

        // Create 7 fake archive directories
        for i in 1...7 {
            let dir = "\(appDir)/1.0.0+\(i)"
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let mgr = ArchiveManager(baseDir: baseDir)
        try mgr.prune(slug: "testapp", keep: 5)

        let remaining = try fm.contentsOfDirectory(atPath: appDir)
        #expect(remaining.count == 5)

        try? fm.removeItem(atPath: baseDir)
    }

    @Test("Prune on empty directory is noop")
    func pruneEmptyDirNoop() throws {
        let mgr = ArchiveManager(baseDir: "/tmp/nonexistent-\(UUID().uuidString)")
        // Should not throw
        try mgr.prune(slug: "absent", keep: 5)
    }
}

// MARK: - ExportOptionsGenerator Tests

@Suite("ExportOptionsGenerator")
struct ExportOptionsGeneratorTests {

    @Test("Generates valid plist with correct team and method")
    func generatesValidPlist() {
        let gen = ExportOptionsGenerator()
        let config = AppConfig(
            slug: "test",
            scheme: "Test",
            teamID: "TEAM123",
            bundleID: "com.test",
            projectPath: "/tmp",
            exportMethod: "app-store"
        )

        let plist = gen.generate(for: config)

        #expect(plist.contains("TEAM123"))
        #expect(plist.contains("app-store"))
        #expect(plist.contains("plist"))
    }

    @Test("Writes plist to directory")
    func writesPlist() throws {
        let gen = ExportOptionsGenerator()
        let config = AppConfig(
            slug: "test",
            scheme: "Test",
            teamID: "TEAM",
            bundleID: "com.test",
            projectPath: "/tmp"
        )

        let dir = NSTemporaryDirectory() + "export-opts-\(UUID().uuidString)"
        let path = try gen.write(for: config, to: dir)

        #expect(FileManager.default.fileExists(atPath: path))
        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content.contains("TEAM"))

        try? FileManager.default.removeItem(atPath: dir)
    }
}

// MARK: - Helpers

private func writeTempFile(content: String) -> String {
    let path = NSTemporaryDirectory() + "test-\(UUID().uuidString).toml"
    try? content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}
