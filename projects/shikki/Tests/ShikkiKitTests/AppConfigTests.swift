import Foundation
import Testing
@testable import ShikkiKit

@Suite("AppConfig -- Registry")
struct AppConfigRegistryTests {

    // MARK: - TOML Parsing

    @Test("Parses valid TOML with single app")
    func parsesValidToml() throws {
        let toml = """
        [wabisabi]
        scheme = "WabiSabi"
        team_id = "L8NRHDDSWG"
        bundle_id = "one.obyw.wabisabi"
        project_path = "/Users/test/WabiSabi.xcodeproj"
        testflight_group = "Beta Testers"
        export_method = "app-store"
        """

        let path = writeTempFile(content: toml)
        let registry = try AppConfigRegistry.load(from: path)

        #expect(registry.count == 1)
        let config = registry.app("wabisabi")
        #expect(config != nil)
        #expect(config?.scheme == "WabiSabi")
        #expect(config?.teamID == "L8NRHDDSWG")
        #expect(config?.bundleID == "one.obyw.wabisabi")

        cleanup(path)
    }

    @Test("Parses multiple apps")
    func parsesMultipleApps() throws {
        let toml = """
        [wabisabi]
        scheme = "WabiSabi"
        team_id = "L8NRHDDSWG"
        bundle_id = "one.obyw.wabisabi"
        project_path = "/Users/test/WabiSabi.xcodeproj"

        [maya]
        scheme = "Maya"
        team_id = "UVC4JM6XD4"
        bundle_id = "fit.maya.app"
        project_path = "/Users/test/Maya.xcodeproj"
        """

        let path = writeTempFile(content: toml)
        let registry = try AppConfigRegistry.load(from: path)

        #expect(registry.count == 2)
        #expect(registry.slugs.contains("wabisabi"))
        #expect(registry.slugs.contains("maya"))

        cleanup(path)
    }

    @Test("Missing required field fails with specific error")
    func missingRequiredFieldFails() throws {
        let toml = """
        [broken]
        scheme = "Broken"
        team_id = "ABC123"
        """

        let path = writeTempFile(content: toml)

        #expect(throws: (any Error).self) {
            try AppConfigRegistry.load(from: path)
        }

        cleanup(path)
    }

    @Test("File not found throws")
    func fileNotFoundThrows() {
        #expect(throws: (any Error).self) {
            try AppConfigRegistry.load(from: "/tmp/nonexistent-\(UUID().uuidString).toml")
        }
    }

    @Test("Parses ASC key config subsection")
    func parsesASCKeyConfig() throws {
        let toml = """
        [wabisabi]
        scheme = "WabiSabi"
        team_id = "L8NRHDDSWG"
        bundle_id = "one.obyw.wabisabi"
        project_path = "/Users/test/WabiSabi.xcodeproj"

        [wabisabi.asc]
        key_id = "ABCDEF1234"
        issuer_id = "11111111-2222-3333-4444-555555555555"
        """

        let path = writeTempFile(content: toml)
        let registry = try AppConfigRegistry.load(from: path)
        let config = registry.app("wabisabi")

        #expect(config?.asc != nil)
        #expect(config?.asc?.keyID == "ABCDEF1234")
        #expect(config?.asc?.issuerID == "11111111-2222-3333-4444-555555555555")

        cleanup(path)
    }

    @Test("Defaults applied for optional fields")
    func defaultsApplied() throws {
        let toml = """
        [myapp]
        scheme = "MyApp"
        team_id = "TEAM123"
        bundle_id = "com.example.myapp"
        project_path = "/Users/test/MyApp.xcodeproj"
        """

        let path = writeTempFile(content: toml)
        let registry = try AppConfigRegistry.load(from: path)
        let config = registry.app("myapp")

        #expect(config?.testflightGroup == "External Testers")
        #expect(config?.exportMethod == "app-store")
        #expect(config?.asc == nil)

        cleanup(path)
    }

    // MARK: - App Selection

    @Test("Single app auto-selects when no slug provided")
    func singleAppAutoSelects() throws {
        let registry = AppConfigRegistry(configs: [
            "solo": AppConfig(
                slug: "solo",
                scheme: "Solo",
                teamID: "TEAM",
                bundleID: "com.solo",
                projectPath: "/tmp/Solo.xcodeproj"
            ),
        ])

        let config = try registry.select(slug: nil)
        #expect(config.slug == "solo")
    }

    @Test("Multiple apps with no slug fails with list")
    func multipleAppsNoSlugFails() throws {
        let registry = AppConfigRegistry(configs: [
            "app1": AppConfig(slug: "app1", scheme: "A", teamID: "T1", bundleID: "b1", projectPath: "/tmp"),
            "app2": AppConfig(slug: "app2", scheme: "B", teamID: "T2", bundleID: "b2", projectPath: "/tmp"),
        ])

        #expect(throws: (any Error).self) {
            try registry.select(slug: nil)
        }
    }

    @Test("Multiple apps with valid slug selects correctly")
    func multipleAppsWithSlugSelects() throws {
        let registry = AppConfigRegistry(configs: [
            "app1": AppConfig(slug: "app1", scheme: "A", teamID: "T1", bundleID: "b1", projectPath: "/tmp"),
            "app2": AppConfig(slug: "app2", scheme: "B", teamID: "T2", bundleID: "b2", projectPath: "/tmp"),
        ])

        let config = try registry.select(slug: "app2")
        #expect(config.slug == "app2")
    }

    @Test("Unknown slug fails with configured list")
    func unknownSlugFailsWithList() throws {
        let registry = AppConfigRegistry(configs: [
            "known": AppConfig(slug: "known", scheme: "K", teamID: "T", bundleID: "b", projectPath: "/tmp"),
        ])

        do {
            _ = try registry.select(slug: "unknown")
            Issue.record("Expected error for unknown slug")
        } catch let error as AppConfigError {
            let desc = error.description
            #expect(desc.contains("unknown") && desc.contains("known"))
        }
    }

    // MARK: - Multi-App Isolation

    @Test("Maya uses own team ID")
    func mayaUsesOwnTeamID() throws {
        let registry = AppConfigRegistry(configs: [
            "wabisabi": AppConfig(slug: "wabisabi", scheme: "W", teamID: "L8NRHDDSWG", bundleID: "w", projectPath: "/tmp"),
            "maya": AppConfig(slug: "maya", scheme: "M", teamID: "UVC4JM6XD4", bundleID: "m", projectPath: "/tmp"),
        ])

        let maya = try registry.select(slug: "maya")
        let wabi = try registry.select(slug: "wabisabi")

        #expect(maya.teamID == "UVC4JM6XD4")
        #expect(wabi.teamID == "L8NRHDDSWG")
        #expect(maya.teamID != wabi.teamID)
    }

    // MARK: - Helpers

    private func writeTempFile(content: String) -> String {
        let path = NSTemporaryDirectory() + "apps-test-\(UUID().uuidString).toml"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
