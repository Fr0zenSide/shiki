import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("AgentPersona tool constraints")
struct AgentPersonaTests {

    @Test("Investigate persona is read-only")
    func investigateReadOnly() {
        let persona = AgentPersona.investigate
        #expect(!persona.canEdit)
        #expect(!persona.canBuild)
        #expect(persona.canRead)
        #expect(persona.canSearch)
    }

    @Test("Implement persona has full access")
    func implementFullAccess() {
        let persona = AgentPersona.implement
        #expect(persona.canEdit)
        #expect(persona.canBuild)
        #expect(persona.canTest)
        #expect(persona.canRead)
    }

    @Test("Verify persona can test but not edit")
    func verifyCanTestNotEdit() {
        let persona = AgentPersona.verify
        #expect(!persona.canEdit)
        #expect(persona.canTest)
        #expect(persona.canRead)
    }

    @Test("Review persona is read-only with PR context")
    func reviewReadOnly() {
        let persona = AgentPersona.review
        #expect(!persona.canEdit)
        #expect(!persona.canBuild)
        #expect(persona.canRead)
    }

    @Test("Fix persona can edit with scoped files")
    func fixCanEditScoped() {
        let persona = AgentPersona.fix
        #expect(persona.canEdit)
        #expect(persona.canTest)
        #expect(persona.canRead)
    }

    @Test("Persona system prompt overlay includes role")
    func personaPromptOverlay() {
        let overlay = AgentPersona.investigate.systemPromptOverlay
        #expect(overlay.contains("read-only"))
        #expect(overlay.contains("investigate"))

        let implOverlay = AgentPersona.implement.systemPromptOverlay
        #expect(implOverlay.contains("implement"))
    }

    @Test("Persona allowed tools list")
    func personaAllowedTools() {
        let investigateTools = AgentPersona.investigate.allowedTools
        #expect(investigateTools.contains("Read"))
        #expect(investigateTools.contains("Grep"))
        #expect(investigateTools.contains("Glob"))
        #expect(!investigateTools.contains("Edit"))
        #expect(!investigateTools.contains("Write"))

        let implementTools = AgentPersona.implement.allowedTools
        #expect(implementTools.contains("Edit"))
        #expect(implementTools.contains("Write"))
        #expect(implementTools.contains("Bash"))
    }

    @Test("All personas are Codable")
    func allCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for persona in AgentPersona.allCases {
            let data = try encoder.encode(persona)
            let decoded = try decoder.decode(AgentPersona.self, from: data)
            #expect(decoded == persona)
        }
    }
}

@Suite("AgentProvider protocol")
struct AgentProviderTests {

    @Test("ClaudeCodeProvider builds command with persona constraints")
    func claudeCodeProviderCommand() {
        let provider = ClaudeCodeProvider(workspacePath: "/tmp/test")
        let config = provider.buildConfig(
            persona: .investigate,
            taskTitle: "Investigate auth flow",
            companySlug: "maya"
        )

        #expect(config.allowedTools.contains("Read"))
        #expect(!config.allowedTools.contains("Edit"))
        #expect(config.systemPrompt.contains("investigate"))
        #expect(config.systemPrompt.contains("maya"))
    }

    @Test("ClaudeCodeProvider implement persona includes all tools")
    func claudeCodeProviderImplement() {
        let provider = ClaudeCodeProvider(workspacePath: "/tmp/test")
        let config = provider.buildConfig(
            persona: .implement,
            taskTitle: "Build feature",
            companySlug: "wabisabi"
        )

        #expect(config.allowedTools.contains("Edit"))
        #expect(config.allowedTools.contains("Write"))
        #expect(config.allowedTools.contains("Bash"))
    }
}
