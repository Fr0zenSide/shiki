import Foundation
import Testing
@testable import ShikiCtlKit

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

@Suite("PRFixAgent")
struct PRFixAgentTests {

    @Test("Build fix context from review state")
    func buildFixContext() {
        let state = PRReviewState(sectionCount: 3)
        let agent = PRFixAgent(
            prNumber: 6,
            workspacePath: "/tmp/test",
            provider: ClaudeCodeProvider(workspacePath: "/tmp/test")
        )
        let context = agent.buildContext(
            state: state,
            filePath: "Sources/Foo.swift",
            issue: "Missing error handling on line 42"
        )

        #expect(context.contains("PR #6"))
        #expect(context.contains("Sources/Foo.swift"))
        #expect(context.contains("Missing error handling"))
    }

    @Test("Fix agent uses fix persona")
    func fixAgentPersona() {
        let agent = PRFixAgent(
            prNumber: 6,
            workspacePath: "/tmp/test",
            provider: ClaudeCodeProvider(workspacePath: "/tmp/test")
        )
        let config = agent.agentConfig(
            filePath: "Sources/Bar.swift",
            issue: "Thread safety"
        )

        #expect(config.persona == .fix)
        #expect(config.allowedTools.contains("Edit"))
        #expect(config.allowedTools.contains("Bash"))
    }
}

@Suite("PR Review Events")
struct PRReviewEventTests {

    @Test("Verdict event has correct type and scope")
    func verdictEvent() {
        let event = PRReviewEvents.verdict(
            prNumber: 6,
            sectionIndex: 2,
            verdict: .approved
        )
        #expect(event.type == .prVerdictSet)
        #expect(event.scope == .pr(number: 6))
        #expect(event.payload["sectionIndex"] == .int(2))
        #expect(event.payload["verdict"] == .string("approved"))
    }

    @Test("Cache built event")
    func cacheBuiltEvent() {
        let event = PRReviewEvents.cacheBuilt(prNumber: 6, fileCount: 10)
        #expect(event.type == .prCacheBuilt)
        #expect(event.payload["fileCount"] == .int(10))
    }

    @Test("Risk assessed event")
    func riskAssessedEvent() {
        let event = PRReviewEvents.riskAssessed(prNumber: 6, highRiskCount: 3, totalFiles: 10)
        #expect(event.type == .prRiskAssessed)
        #expect(event.payload["highRiskCount"] == .int(3))
    }

    @Test("Fix spawned event")
    func fixSpawnedEvent() {
        let event = PRReviewEvents.fixSpawned(prNumber: 6, filePath: "Foo.swift", issue: "Bug")
        #expect(event.type == .prFixSpawned)
        #expect(event.payload["filePath"] == .string("Foo.swift"))
    }
}
