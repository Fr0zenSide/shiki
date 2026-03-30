import Foundation
import Testing
@testable import ShikkiKit

@Suite("ContextBuilder")
struct ContextBuilderTests {

    private func sampleCache() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "brainy",
            projectPath: "/Users/test/projects/brainy",
            gitHash: "abc123def456",
            builtAt: Date(),
            packageInfo: PackageInfo(name: "Brainy", platforms: ["macOS 14", "iOS 17"], targets: [
                TargetInfo(name: "BrainyCore", type: .library, path: "Sources/BrainyCore",
                           dependencies: ["Foundation"], sourceFiles: 12),
                TargetInfo(name: "Brainy", type: .executable, path: "Sources/Brainy",
                           dependencies: ["BrainyCore"], sourceFiles: 5),
                TargetInfo(name: "BrainyCoreTests", type: .test, path: "Tests/BrainyCoreTests",
                           dependencies: ["BrainyCore"], sourceFiles: 8),
            ], dependencies: [
                DependencyInfo(name: "swift-argument-parser", isLocal: false,
                               url: "https://github.com/apple/swift-argument-parser.git"),
                DependencyInfo(name: "CoreKit", isLocal: true, path: "../packages/CoreKit"),
            ]),
            protocols: [
                ProtocolDescriptor(name: "TranslationProvider", file: "Protocols/TranslationProvider.swift",
                                   methods: ["func translate(text: String) async throws -> String"],
                                   conformers: ["GoogleTranslator", "DeepLTranslator"], module: "BrainyCore"),
                ProtocolDescriptor(name: "OCRProvider", file: "Protocols/OCRProvider.swift",
                                   methods: ["func recognize(image: Data) async throws -> [TextRegion]"],
                                   conformers: ["AppleVisionOCR"], module: "BrainyCore"),
            ],
            types: [
                TypeDescriptor(name: "TranslationPage", kind: .struct, file: "Models/TranslationPage.swift",
                               module: "BrainyCore", fields: ["id", "regions", "progress"],
                               conformances: ["Codable", "Sendable"], isPublic: true),
                TypeDescriptor(name: "TextRegion", kind: .struct, file: "Models/TextRegion.swift",
                               module: "BrainyCore", fields: ["text", "bounds", "language"],
                               conformances: ["Codable"], isPublic: true),
                TypeDescriptor(name: "OCRError", kind: .enum, file: "Errors/OCRError.swift",
                               module: "BrainyCore", fields: [], conformances: ["Error", "LocalizedError"],
                               isPublic: true),
            ],
            dependencyGraph: [
                "BrainyCore": ["Foundation", "CoreKit"],
                "Brainy": ["BrainyCore", "ArgumentParser"],
            ],
            patterns: [
                CodePattern(name: "error_pattern", description: "Typed error enums",
                            example: "enum OCRError: Error { case noText }", files: ["Errors/OCRError.swift"]),
                CodePattern(name: "mock_pattern", description: "Mock types with call tracking",
                            example: "class MockOCR: OCRProvider { var callCount = 0 }",
                            files: ["Tests/Mocks/MockOCR.swift"]),
            ],
            testInfo: TestInfo(framework: "swift-testing", testFiles: 8, testCount: 42,
                               mockPattern: "Mock* with call tracking + shouldThrow",
                               fixturePattern: "Factory methods (make*) in test files")
        )
    }

    private func emptyCache() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "empty",
            projectPath: "/tmp/empty",
            gitHash: "000000",
            builtAt: Date(),
            packageInfo: PackageInfo(),
            protocols: [],
            types: [],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )
    }

    // MARK: - projectOverview

    @Test("projectOverview produces readable summary")
    func projectOverviewReadable() {
        let cache = sampleCache()
        let overview = ContextBuilder.projectOverview(cache)

        #expect(overview.contains("# Project: Brainy"))
        #expect(overview.contains("macOS 14"))
        #expect(overview.contains("BrainyCore"))
        #expect(overview.contains("TranslationProvider"))
        #expect(overview.contains("TranslationPage"))
        #expect(overview.contains("error_pattern"))
        #expect(overview.contains("swift-testing"))
        #expect(overview.contains("42"))
    }

    @Test("projectOverview handles empty cache")
    func projectOverviewEmpty() {
        let cache = emptyCache()
        let overview = ContextBuilder.projectOverview(cache)

        #expect(overview.contains("# Project: empty"))
        #expect(overview.contains("Tests"))
    }

    // MARK: - protocolContext

    @Test("protocolContext includes methods and conformers")
    func protocolContextDetail() {
        let cache = sampleCache()
        let ctx = ContextBuilder.protocolContext("TranslationProvider", cache: cache)

        #expect(ctx.contains("# Protocol: TranslationProvider"))
        #expect(ctx.contains("BrainyCore"))
        #expect(ctx.contains("translate"))
        #expect(ctx.contains("GoogleTranslator"))
        #expect(ctx.contains("DeepLTranslator"))
    }

    @Test("protocolContext returns not found for unknown protocol")
    func protocolContextNotFound() {
        let cache = sampleCache()
        let ctx = ContextBuilder.protocolContext("NonExistent", cache: cache)

        #expect(ctx.contains("not found"))
    }

    // MARK: - typeContext

    @Test("typeContext includes fields and conformances")
    func typeContextDetail() {
        let cache = sampleCache()
        let ctx = ContextBuilder.typeContext("TranslationPage", cache: cache)

        #expect(ctx.contains("# Struct: TranslationPage"))
        #expect(ctx.contains("BrainyCore"))
        #expect(ctx.contains("id"))
        #expect(ctx.contains("regions"))
        #expect(ctx.contains("Codable"))
        #expect(ctx.contains("Sendable"))
    }

    @Test("typeContext returns not found for unknown type")
    func typeContextNotFound() {
        let cache = sampleCache()
        let ctx = ContextBuilder.typeContext("Ghost", cache: cache)

        #expect(ctx.contains("not found"))
    }

    // MARK: - patternContext

    @Test("patternContext shows all patterns")
    func patternContextShowsAll() {
        let cache = sampleCache()
        let ctx = ContextBuilder.patternContext(for: "add error handling", cache: cache)

        #expect(ctx.contains("error_pattern"))
        #expect(ctx.contains("mock_pattern"))
    }

    @Test("patternContext returns message for empty patterns")
    func patternContextEmpty() {
        let cache = emptyCache()
        let ctx = ContextBuilder.patternContext(for: "anything", cache: cache)

        #expect(ctx.contains("No patterns"))
    }

    // MARK: - agentSummary

    @Test("agentSummary is compact")
    func agentSummaryCompact() {
        let cache = sampleCache()
        let summary = ContextBuilder.agentSummary(cache)

        // Should be under ~500 tokens. A rough proxy: under 2000 characters.
        #expect(summary.count < 2000)
        #expect(summary.contains("Brainy"))
        #expect(summary.contains("BrainyCore"))
        #expect(summary.contains("TranslationProvider"))
        #expect(summary.contains("swift-testing"))
    }

    @Test("agentSummary handles empty cache")
    func agentSummaryEmpty() {
        let cache = emptyCache()
        let summary = ContextBuilder.agentSummary(cache)

        #expect(summary.contains("empty"))
        #expect(summary.count < 500)
    }
}
