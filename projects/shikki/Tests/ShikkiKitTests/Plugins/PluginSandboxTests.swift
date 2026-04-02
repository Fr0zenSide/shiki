import Foundation
import Testing
@testable import ShikkiKit

@Suite("PluginSandbox — filesystem isolation and security enforcement")
struct PluginSandboxTests {

    // MARK: - Test Fixtures

    private static let testPluginID = PluginID("shikki/test-plugin")
    private static let scopeDir = "/Users/test/.shikki/plugins/shikki/test-plugin/data"

    private static func makeSandbox(
        pluginId: PluginID = testPluginID,
        scopeDirectory: String = scopeDir,
        declaredPaths: [String] = [],
        certification: CertificationLevel = .uncertified
    ) -> PluginSandbox {
        PluginSandbox(
            pluginId: pluginId,
            scopeDirectory: scopeDirectory,
            declaredPaths: declaredPaths,
            certification: certification
        )
    }

    // MARK: - BR-01 / BR-02: Scoped directory access

    @Test("BR-01: Plugin reads within scoped directory — allowed")
    func readWithinScope_allowed() {
        let sandbox = Self.makeSandbox()
        let path = "\(Self.scopeDir)/config.json"
        let decision = sandbox.validateAccess(path: path, operation: .read)
        #expect(decision.isAllowed)
    }

    @Test("BR-02: Plugin path traversal blocked — denied with reason")
    func pathTraversal_denied() {
        let sandbox = Self.makeSandbox()
        let path = "\(Self.scopeDir)/../../other-plugin/data/secrets.json"
        let decision = sandbox.validateAccess(path: path, operation: .read)
        #expect(!decision.isAllowed)
        if case .denied(let reason) = decision {
            #expect(reason.contains("outside"))
        }
    }

    // MARK: - BR-03: Secrets protection

    @Test("BR-03: Secret file access always blocked (.env, .aws)")
    func secretFileAccess_blocked() {
        // Even if somehow a path resolves inside scope, secret patterns are blocked
        let sandbox = Self.makeSandbox(
            declaredPaths: ["/Users/test/.env", "/Users/test/.aws/credentials"]
        )

        let envDecision = sandbox.validateAccess(path: "/Users/test/.env", operation: .read)
        #expect(!envDecision.isAllowed)

        let awsDecision = sandbox.validateAccess(path: "/Users/test/.aws/credentials", operation: .read)
        #expect(!awsDecision.isAllowed)

        let keychainDecision = sandbox.validateAccess(path: "/Users/test/Library/Keychains/login.keychain-db", operation: .read)
        #expect(!keychainDecision.isAllowed)
    }

    // MARK: - BR-04: ShikkiKit source/binary protection

    @Test("BR-04: ShikkiKit source and binary paths are protected")
    func shikkiKitProtection() {
        let sandbox = Self.makeSandbox(
            declaredPaths: ["/Users/test/Projects/shikki/Sources/ShikkiKit/something.swift"]
        )

        let sourceDecision = sandbox.validateAccess(
            path: "/Users/test/Projects/shikki/Sources/ShikkiKit/something.swift",
            operation: .read
        )
        #expect(!sourceDecision.isAllowed)

        let binaryDecision = sandbox.validateAccess(
            path: "/usr/local/bin/shikki",
            operation: .overwrite
        )
        #expect(!binaryDecision.isAllowed)
    }

    // MARK: - BR-05: Additive-only (no deletion of user project files)

    @Test("BR-05: Additive-only — create allowed in scope, delete denied outside scope")
    func additiveOnly_createAllowed_deleteBlocked() {
        let sandbox = Self.makeSandbox()

        // Create inside scope is allowed
        let createDecision = sandbox.validateAccess(
            path: "\(Self.scopeDir)/output.txt",
            operation: .create
        )
        #expect(createDecision.isAllowed)

        // Delete inside scope is allowed (plugin's own data)
        let deleteScopeDecision = sandbox.validateAccess(
            path: "\(Self.scopeDir)/temp.txt",
            operation: .delete
        )
        #expect(deleteScopeDecision.isAllowed)

        // Delete outside scope is always denied
        let deleteOutsideDecision = sandbox.validateAccess(
            path: "/Users/test/Documents/important.txt",
            operation: .delete
        )
        #expect(!deleteOutsideDecision.isAllowed)
    }

    // MARK: - BR-06: Declared paths respected

    @Test("BR-06/BR-08: Manifest declared paths respected with proper certification")
    func declaredPaths_respected() {
        // Enterprise certified plugin with declared paths can read outside scope
        let sandbox = Self.makeSandbox(
            declaredPaths: ["/Users/test/Projects/myapp/src"],
            certification: .enterpriseSafe
        )

        let readDecision = sandbox.validateAccess(
            path: "/Users/test/Projects/myapp/src/main.swift",
            operation: .read
        )
        #expect(readDecision.isAllowed)

        // But undeclared path is still denied
        let undeclaredDecision = sandbox.validateAccess(
            path: "/Users/test/Projects/myapp/config/secrets.json",
            operation: .read
        )
        #expect(!undeclaredDecision.isAllowed)
    }

    // MARK: - BR-07: Subprocess isolation

    @Test("BR-07: Subprocess execution with sanitized env — no inherited secrets")
    func subprocessSanitizedEnv() async throws {
        let runner = PluginRunner(
            pluginId: Self.testPluginID,
            scopeDirectory: Self.scopeDir
        )

        let sanitized = await runner.sanitizedEnvironment()

        // Only allowed env vars survive
        let allowedKeys = PluginRunner.allowedEnvVars
        for key in sanitized.keys {
            #expect(allowedKeys.contains(key), "Unexpected env var: \(key)")
        }

        // Secret env vars must not be present
        #expect(sanitized["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(sanitized["DATABASE_URL"] == nil)
        #expect(sanitized["API_KEY"] == nil)
    }

    // MARK: - BR-08: Enterprise certification gate

    @Test("BR-08: Enterprise certification required for project file access")
    func enterpriseCertificationGate() {
        // Uncertified plugin cannot access declared project paths
        let uncertified = Self.makeSandbox(
            declaredPaths: ["/Users/test/Projects/myapp/src"],
            certification: .uncertified
        )
        let decision = uncertified.validateAccess(
            path: "/Users/test/Projects/myapp/src/main.swift",
            operation: .read
        )
        #expect(!decision.isAllowed)

        // Community reviewed also cannot
        let community = Self.makeSandbox(
            declaredPaths: ["/Users/test/Projects/myapp/src"],
            certification: .communityReviewed
        )
        let communityDecision = community.validateAccess(
            path: "/Users/test/Projects/myapp/src/main.swift",
            operation: .read
        )
        #expect(!communityDecision.isAllowed)
    }

    // MARK: - BR-09: Plugin uninstall cleanup

    @Test("BR-09: Plugin uninstall removes ONLY the plugin's scoped directory")
    func uninstallCleanup() async throws {
        let fm = FileManager.default
        let tmpBase = fm.temporaryDirectory.appendingPathComponent("shikki-sandbox-test-\(UUID().uuidString)").path
        let pluginDataDir = (tmpBase as NSString).appendingPathComponent("shikki/test-plugin/data")
        let otherPluginDir = (tmpBase as NSString).appendingPathComponent("shikki/other-plugin/data")

        defer { try? fm.removeItem(atPath: tmpBase) }

        // Setup: create both plugin directories with files
        try fm.createDirectory(atPath: pluginDataDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: otherPluginDir, withIntermediateDirectories: true)
        fm.createFile(atPath: (pluginDataDir as NSString).appendingPathComponent("config.json"), contents: Data("{}".utf8))
        fm.createFile(atPath: (otherPluginDir as NSString).appendingPathComponent("config.json"), contents: Data("{}".utf8))

        let registry = PluginRegistry()
        let manifest = PluginManifest(
            id: Self.testPluginID,
            displayName: "Test Plugin",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            source: .builtin,
            commands: [PluginCommand(name: "test-cmd")],
            capabilities: [],
            dependencies: PluginDependencies(),
            minimumShikkiVersion: SemanticVersion(major: 0, minor: 3, patch: 0),
            entryPoint: "TestPlugin",
            author: "test",
            license: "MIT",
            description: "Test",
            checksum: "sha256-test"
        )
        try await registry.register(manifest: manifest)

        // Uninstall should remove the plugin's scoped directory
        try await registry.uninstall(id: Self.testPluginID, pluginsBaseDirectory: tmpBase)

        // Plugin's data directory should be gone
        #expect(!fm.fileExists(atPath: pluginDataDir))

        // Other plugin's directory must still exist
        #expect(fm.fileExists(atPath: otherPluginDir))
    }

    // MARK: - BR-10: Write outside scope without declared paths — denied

    @Test("BR-10: Plugin write outside scope without declared paths — denied")
    func writeOutsideScope_denied() {
        let sandbox = Self.makeSandbox(declaredPaths: [])

        let decision = sandbox.validateAccess(
            path: "/Users/test/Documents/output.txt",
            operation: .create
        )
        #expect(!decision.isAllowed)

        let overwriteDecision = sandbox.validateAccess(
            path: "/tmp/something.txt",
            operation: .overwrite
        )
        #expect(!overwriteDecision.isAllowed)
    }
}

// MARK: - PluginRunner Tests

@Suite("PluginRunner — subprocess isolation")
struct PluginRunnerTests {

    @Test("BR-10: Plugin crash does not crash ShikkiKit — subprocess isolation")
    func pluginCrashIsolation() async throws {
        let runner = PluginRunner(
            pluginId: PluginID("shikki/crashy"),
            scopeDirectory: "/tmp/shikki-test-crashy"
        )

        // Execute a command that will fail (non-existent binary)
        let result = await runner.execute(
            arguments: ["/usr/bin/env", "nonexistent-binary-that-does-not-exist-xyz"],
            timeout: .seconds(5)
        )

        // The runner should capture the failure, not crash
        #expect(!result.succeeded)
        #expect(result.exitCode != 0)
    }

    @Test("PluginRunner sanitizes environment variables")
    func sanitizedEnv_noSecrets() async {
        let runner = PluginRunner(
            pluginId: PluginID("shikki/test"),
            scopeDirectory: "/tmp/shikki-test"
        )

        let env = await runner.sanitizedEnvironment()

        // These must never leak to plugins
        let forbidden = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "DATABASE_URL",
                         "API_KEY", "GITHUB_TOKEN", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"]
        for key in forbidden {
            #expect(env[key] == nil, "Forbidden env var leaked: \(key)")
        }
    }
}
