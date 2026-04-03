import Foundation
import Testing
@testable import ShikkiKit

@Suite("ProjectAnalyzer Integration", .tags(.integration))
struct ProjectAnalyzerIntegrationTests {

    /// Run the analyzer on the shikki project itself and verify it finds real artifacts.
    @Test("Analyze shikki project finds known protocols and types")
    func analyzeShikkiProject() async throws {
        // Resolve the shikki project path (this test runs from the project root)
        let projectPath = resolveShikkiProjectPath()
        guard FileManager.default.fileExists(atPath: "\(projectPath)/Package.swift") else {
            // Skip if we can't find the project (CI environments, etc.)
            return
        }

        let analyzer = ProjectAnalyzer()
        let cache = try await analyzer.analyze(projectPath: projectPath)

        // Package info should be populated
        #expect(cache.packageInfo.name == "shikki")
        #expect(!cache.packageInfo.targets.isEmpty)
        #expect(cache.packageInfo.targets.contains(where: { $0.name == "ShikkiKit" }))
        #expect(cache.packageInfo.targets.contains(where: { $0.name == "shi" }))
        #expect(cache.packageInfo.targets.contains(where: { $0.name == "ShikkiKitTests" }))

        // Should find known protocols
        let protocolNames = cache.protocols.map(\.name)
        #expect(protocolNames.contains("BackendClientProtocol"))
        #expect(protocolNames.contains("ProcessLauncher"))

        // Should find known types
        let typeNames = cache.types.map(\.name)
        #expect(typeNames.contains("Company"))
        #expect(typeNames.contains("Decision"))
        #expect(typeNames.contains("ArchitectureCache"))

        // Dependency graph should have entries
        #expect(!cache.dependencyGraph.isEmpty)

        // Should detect test info
        #expect(cache.testInfo.testFiles > 0)
        #expect(cache.testInfo.testCount > 0)
        #expect(cache.testInfo.framework == "swift-testing" || cache.testInfo.framework == "mixed")

        // Should have a valid git hash
        #expect(cache.gitHash != "unknown")
        #expect(cache.gitHash.count >= 7)

        // Should have mock pattern (the project uses MockBackendClient)
        #expect(cache.patterns.contains(where: { $0.name == "mock_pattern" }))
    }

    @Test("Analyze shikki project completes quickly")
    func analyzePerformance() async throws {
        let projectPath = resolveShikkiProjectPath()
        guard FileManager.default.fileExists(atPath: "\(projectPath)/Package.swift") else {
            return
        }

        let analyzer = ProjectAnalyzer()
        let start = CFAbsoluteTimeGetCurrent()
        _ = try await analyzer.analyze(projectPath: projectPath)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Should complete in under 5 seconds (relaxed for CI + parallel test load)
        #expect(elapsed < 5.0, "Analysis took \(elapsed)s, expected < 5s")
    }

    // MARK: - Helpers

    /// Walk up from the current directory to find the shikki project root.
    private func resolveShikkiProjectPath() -> String {
        // The test binary runs from a derived data path, but we can use
        // the known project structure to find it
        var candidate = FileManager.default.currentDirectoryPath
        // Try walking up to find Package.swift
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: "\(candidate)/Package.swift") {
                // Check it's the shikki project
                if let content = try? String(contentsOfFile: "\(candidate)/Package.swift", encoding: .utf8),
                   content.contains("\"shikki\"") {
                    return candidate
                }
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        // Fallback to known path
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CodeGen/
            .deletingLastPathComponent() // ShikkiKitTests/
            .deletingLastPathComponent() // Tests/
            .path
    }
}

// Tag for integration tests
extension Tag {
    @Tag static var integration: Self
}
