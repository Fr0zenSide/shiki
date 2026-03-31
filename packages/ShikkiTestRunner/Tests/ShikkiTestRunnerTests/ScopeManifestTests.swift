import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("ScopeManifest")
struct ScopeManifestTests {

    // MARK: - Default Scopes

    @Test("Default manifest contains all expected Shikki scopes")
    func defaultManifestHasAllScopes() {
        let manifest = ScopeManifest.shikkiDefaults
        let names = manifest.scopes.map(\.name)

        #expect(names.contains("nats"))
        #expect(names.contains("flywheel"))
        #expect(names.contains("tui"))
        #expect(names.contains("safety"))
        #expect(names.contains("codegen"))
        #expect(names.contains("observatory"))
        #expect(names.contains("ship"))
        #expect(names.contains("kernel"))
        #expect(names.contains("answer-engine"))
        #expect(names.contains("s3-parser"))
        #expect(names.contains("blue-flame"))
        #expect(names.contains("moto"))
        #expect(names.contains("memory"))
        #expect(manifest.scopes.count == 13)
    }

    @Test("Default manifest source is defaultFallback")
    func defaultManifestSource() {
        let manifest = ScopeManifest.shikkiDefaults
        #expect(manifest.source == .defaultFallback)
    }

    @Test("Default manifest passes validation")
    func defaultManifestIsValid() {
        let manifest = ScopeManifest.shikkiDefaults
        #expect(manifest.isValid)
        #expect(manifest.validate().isEmpty)
    }

    @Test("Each default scope has at least one module or type pattern")
    func defaultScopesAreNotEmpty() {
        for scope in ScopeManifest.shikkiDefaults.scopes {
            let hasPatterns = !scope.modulePatterns.isEmpty
                || !scope.typePatterns.isEmpty
                || !scope.testFilePatterns.isEmpty
            #expect(hasPatterns, "Scope '\(scope.name)' has no patterns")
        }
    }

    // MARK: - Validation

    @Test("Duplicate scope names detected")
    func duplicateScopeNamesDetected() {
        let manifest = ScopeManifest(
            scopes: [
                ScopeDefinition(name: "nats", modulePatterns: ["NATSClient"]),
                ScopeDefinition(name: "nats", modulePatterns: ["NATSProtocol"]),
            ],
            source: .defaultFallback
        )

        let errors = manifest.validate()
        #expect(errors.contains(.duplicateScopeName("nats")))
        #expect(!manifest.isValid)
    }

    @Test("Empty scope definition detected")
    func emptyScopeDetected() {
        let manifest = ScopeManifest(
            scopes: [
                ScopeDefinition(name: "empty")
            ],
            source: .defaultFallback
        )

        let errors = manifest.validate()
        #expect(errors.contains(.emptyScopeDefinition("empty")))
    }

    @Test("Reserved scope name 'unscoped' detected")
    func reservedScopeNameDetected() {
        let manifest = ScopeManifest(
            scopes: [
                ScopeDefinition(name: "unscoped", modulePatterns: ["Something"])
            ],
            source: .defaultFallback
        )

        let errors = manifest.validate()
        #expect(errors.contains(.reservedScopeName("unscoped")))
    }

    @Test("Valid custom manifest passes validation")
    func validCustomManifest() {
        let manifest = ScopeManifest(
            scopes: [
                ScopeDefinition(name: "core", modulePatterns: ["CoreKit"]),
                ScopeDefinition(name: "ui", typePatterns: ["ViewController"]),
            ],
            source: .jsonConfig(path: "/tmp/test.json")
        )

        #expect(manifest.isValid)
    }

    // MARK: - JSON Serialization

    @Test("Manifest round-trips through JSON")
    func jsonRoundTrip() throws {
        let original = ScopeManifest(
            scopes: [
                ScopeDefinition(
                    name: "nats",
                    modulePatterns: ["NATSClient"],
                    typePatterns: ["EventBus"],
                    testFilePatterns: ["**/NATS*Tests.swift"]
                )
            ],
            source: .defaultFallback
        )

        let data = try original.toJSON()
        let decoded = try JSONDecoder().decode(ScopeManifest.self, from: data)

        #expect(decoded.scopes.count == 1)
        #expect(decoded.scopes[0].name == "nats")
        #expect(decoded.scopes[0].modulePatterns == ["NATSClient"])
        #expect(decoded.scopes[0].typePatterns == ["EventBus"])
        #expect(decoded.scopes[0].testFilePatterns == ["**/NATS*Tests.swift"])
    }

    @Test("Load from nonexistent file throws")
    func loadNonexistentFile() {
        #expect(throws: (any Error).self) {
            _ = try ScopeManifest.load(from: "/nonexistent/path.json")
        }
    }

    @Test("Load from valid JSON file succeeds")
    func loadFromJSONFile() throws {
        let manifest = ScopeManifest(
            scopes: [
                ScopeDefinition(name: "test", modulePatterns: ["TestKit"])
            ],
            source: .defaultFallback
        )

        let data = try manifest.toJSON()
        let tmpPath = NSTemporaryDirectory() + "shikki-test-manifest-\(UUID().uuidString).json"
        try data.write(to: URL(fileURLWithPath: tmpPath))

        let loaded = try ScopeManifest.load(from: tmpPath)
        #expect(loaded.scopes.count == 1)
        #expect(loaded.scopes[0].name == "test")
        #expect(loaded.source == .jsonConfig(path: tmpPath))

        try? FileManager.default.removeItem(atPath: tmpPath)
    }
}
