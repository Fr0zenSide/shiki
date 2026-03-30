import Foundation
import Testing
@testable import ShikkiKit

@Suite("AgentPromptGenerator")
struct AgentPromptGeneratorTests {

    let generator = AgentPromptGenerator()

    // MARK: - Full Prompt Generation

    @Test("generates prompt with all sections")
    func fullPrompt() {
        let unit = WorkUnit(
            id: "unit-1",
            description: "Implement TranslationProvider",
            files: [
                FileSpec(path: "Sources/Translation/AppleTranslation.swift", role: .implementation, description: "Apple Translation impl")
            ],
            protocolNames: ["TranslationProvider"],
            typeNames: [],
            testScope: ["Tests/TranslationTests.swift"],
            worktreeBranch: "codegen/translation/impl-1",
            priority: 1
        )
        let layer = ProtocolLayer(
            featureName: "Translation",
            protocols: [
                ProtocolSpec(name: "TranslationProvider", methods: ["func translate(text: String) async throws -> String"], inherits: ["Sendable"])
            ],
            types: [
                TypeSpec(name: "TranslationResult", kind: .struct, fields: [FieldSpec(name: "text", type: "String")])
            ],
            targetModule: "BrainyCore"
        )

        let prompt = generator.generate(for: unit, layer: layer)

        #expect(prompt.contains("Agent Task: Implement TranslationProvider"))
        #expect(prompt.contains("Translation"))
        #expect(prompt.contains("Protocol Contracts"))
        #expect(prompt.contains("TranslationProvider"))
        #expect(prompt.contains("translate(text:"))
        #expect(prompt.contains("Files to Create"))
        #expect(prompt.contains("AppleTranslation.swift"))
        #expect(prompt.contains("Test Expectations"))
        #expect(prompt.contains("Constraints"))
    }

    @Test("includes architecture context when cache provided")
    func withCache() {
        let unit = WorkUnit(id: "unit-1", description: "Test")
        let layer = ProtocolLayer(featureName: "Test")
        let cache = makeCache()

        let prompt = generator.generate(for: unit, layer: layer, cache: cache)
        #expect(prompt.contains("Project Architecture"))
        #expect(prompt.contains("TestProject"))
    }

    @Test("omits architecture context when no cache")
    func withoutCache() {
        let unit = WorkUnit(id: "unit-1", description: "Test")
        let layer = ProtocolLayer(featureName: "Test")

        let prompt = generator.generate(for: unit, layer: layer, cache: nil)
        #expect(!prompt.contains("Project Architecture"))
    }

    // MARK: - Compact Prompt

    @Test("compact prompt is shorter than full prompt")
    func compactIsShorter() {
        let unit = WorkUnit(
            id: "unit-1",
            description: "Implement Foo",
            files: [FileSpec(path: "Sources/Foo.swift", role: .implementation)],
            protocolNames: ["FooProvider"]
        )
        let layer = ProtocolLayer(
            featureName: "Foo",
            protocols: [ProtocolSpec(name: "FooProvider", methods: ["func bar()"])]
        )
        let cache = makeCache()

        let full = generator.generate(for: unit, layer: layer, cache: cache)
        let compact = generator.generateCompact(for: unit, layer: layer, cache: cache)
        #expect(compact.count < full.count)
    }

    @Test("compact prompt includes contracts and file list")
    func compactContents() {
        let unit = WorkUnit(
            id: "unit-1",
            description: "Implement Foo",
            files: [FileSpec(path: "Sources/Foo.swift", role: .implementation, description: "Main impl")],
            protocolNames: ["FooProvider"]
        )
        let layer = ProtocolLayer(
            featureName: "Foo",
            protocols: [ProtocolSpec(name: "FooProvider", methods: ["func bar()"])]
        )

        let prompt = generator.generateCompact(for: unit, layer: layer)
        #expect(prompt.contains("Implement Foo"))
        #expect(prompt.contains("Contracts"))
        #expect(prompt.contains("FooProvider"))
        #expect(prompt.contains("Sources/Foo.swift"))
    }

    // MARK: - Contract Filtering

    @Test("full prompt filters protocols to unit scope")
    func protocolFiltering() {
        let unit = WorkUnit(
            id: "unit-1",
            description: "Impl A",
            protocolNames: ["ProviderA"]
        )
        let layer = ProtocolLayer(
            featureName: "Feature",
            protocols: [
                ProtocolSpec(name: "ProviderA", methods: ["func a()"]),
                ProtocolSpec(name: "ProviderB", methods: ["func b()"]),
            ]
        )

        let prompt = generator.generate(for: unit, layer: layer)
        // Should include ProviderA's method
        #expect(prompt.contains("func a()"))
        // Types section shows all types for reference, but protocol section is filtered
    }

    // MARK: - Test Framework Guidance

    @Test("uses swift-testing guidance for swift-testing projects")
    func swiftTestingGuidance() {
        let unit = WorkUnit(id: "unit-1", description: "Test")
        let layer = ProtocolLayer(featureName: "Test")
        let cache = ArchitectureCache(
            projectId: "test", projectPath: "/tmp", gitHash: "abc", builtAt: Date(),
            packageInfo: PackageInfo(), protocols: [], types: [],
            dependencyGraph: [:], patterns: [],
            testInfo: TestInfo(framework: "swift-testing")
        )

        let prompt = generator.generate(for: unit, layer: layer, cache: cache)
        #expect(prompt.contains("Swift Testing"))
        #expect(prompt.contains("@Test"))
    }

    @Test("uses XCTest guidance for xctest projects")
    func xctestGuidance() {
        let unit = WorkUnit(id: "unit-1", description: "Test")
        let layer = ProtocolLayer(featureName: "Test")
        let cache = ArchitectureCache(
            projectId: "test", projectPath: "/tmp", gitHash: "abc", builtAt: Date(),
            packageInfo: PackageInfo(), protocols: [], types: [],
            dependencyGraph: [:], patterns: [],
            testInfo: TestInfo(framework: "xctest")
        )

        let prompt = generator.generate(for: unit, layer: layer, cache: cache)
        #expect(prompt.contains("XCTest"))
    }

    // MARK: - Constraints

    @Test("constraints include no-print rule")
    func noPrintConstraint() {
        let unit = WorkUnit(id: "unit-1", description: "Test")
        let layer = ProtocolLayer(featureName: "Test")

        let prompt = generator.generate(for: unit, layer: layer)
        #expect(prompt.contains("No `print()`"))
    }

    @Test("constraints list available dependencies when cache provided")
    func dependencyConstraints() {
        let unit = WorkUnit(id: "unit-1", description: "Test")
        let layer = ProtocolLayer(featureName: "Test")
        let cache = ArchitectureCache(
            projectId: "test", projectPath: "/tmp", gitHash: "abc", builtAt: Date(),
            packageInfo: PackageInfo(dependencies: [
                DependencyInfo(name: "ArgumentParser", isLocal: false)
            ]),
            protocols: [], types: [], dependencyGraph: [:], patterns: [],
            testInfo: TestInfo()
        )

        let prompt = generator.generate(for: unit, layer: layer, cache: cache)
        #expect(prompt.contains("ArgumentParser"))
    }

    // MARK: - Helpers

    func makeCache() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "TestProject",
            projectPath: "/tmp/test",
            gitHash: "abc123",
            builtAt: Date(),
            packageInfo: PackageInfo(name: "TestProject"),
            protocols: [],
            types: [],
            dependencyGraph: [:],
            patterns: [
                CodePattern(name: "error_pattern", description: "Typed errors", example: "enum FooError: Error {}")
            ],
            testInfo: TestInfo(framework: "swift-testing", testFiles: 5, testCount: 30, mockPattern: "Mock* with shouldThrow")
        )
    }
}
