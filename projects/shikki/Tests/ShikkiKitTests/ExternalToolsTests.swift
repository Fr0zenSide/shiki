import Foundation
import Testing
@testable import ShikkiKit

@Suite("ExternalTools detection and fallback")
struct ExternalToolsTests {

    @Test("Detect available tools")
    func detectTools() {
        let tools = ExternalTools()
        // git should always be available on dev machines
        #expect(tools.isAvailable("git"))
    }

    @Test("Unavailable tool returns false")
    func unavailableTool() {
        let tools = ExternalTools()
        #expect(!tools.isAvailable("nonexistent-tool-xyz-12345"))
    }

    @Test("Tool registry has known tools")
    func toolRegistry() {
        let registry = ExternalTools.knownTools
        #expect(registry.contains(where: { $0.name == "delta" }))
        #expect(registry.contains(where: { $0.name == "fzf" }))
        #expect(registry.contains(where: { $0.name == "rg" }))
        #expect(registry.contains(where: { $0.name == "qmd" }))
    }

    @Test("Tool info includes shortcut and description")
    func toolInfo() {
        let delta = ExternalTools.knownTools.first { $0.name == "delta" }!
        #expect(delta.shortcut == "d")
        #expect(!delta.description.isEmpty)
    }

    @Test("Graceful degradation returns fallback")
    func gracefulDegradation() {
        let tools = ExternalTools()
        // delta may or may not be installed, but fallback should always work
        let diffCmd = tools.diffCommand(for: "test.swift")
        #expect(!diffCmd.isEmpty)
        // viewCommand returns args array (safe, no shell interpolation)
        let viewArgs = tools.viewCommand(for: "test.swift")
        #expect(viewArgs.count >= 2)
        #expect(viewArgs.last == "test.swift")
    }
}

