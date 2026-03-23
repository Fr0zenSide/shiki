import Foundation
import Testing

@testable import ShikiCtlKit

@Suite("PromptTemplateLoader")
struct PromptTemplateLoaderTests {

    // MARK: - Variable Substitution

    @Test("render replaces all known variables")
    func renderReplacesAllVariables() {
        let loader = PromptTemplateLoader()
        let template = "Hello {{name}}, your ID is {{id}}."
        let result = loader.render(template: template, variables: ["name": "Alice", "id": "42"])
        #expect(result == "Hello Alice, your ID is 42.")
    }

    @Test("render leaves unknown placeholders untouched")
    func renderLeavesUnknownPlaceholders() {
        let loader = PromptTemplateLoader()
        let template = "{{known}} and {{unknown}}"
        let result = loader.render(template: template, variables: ["known": "YES"])
        #expect(result == "YES and {{unknown}}")
    }

    @Test("render with empty variables returns template as-is")
    func renderEmptyVariablesReturnsOriginal() {
        let loader = PromptTemplateLoader()
        let template = "No {{variables}} replaced"
        let result = loader.render(template: template, variables: [:])
        #expect(result == "No {{variables}} replaced")
    }

    @Test("render replaces multiple occurrences of the same variable")
    func renderReplacesMultipleOccurrences() {
        let loader = PromptTemplateLoader()
        let template = "{{x}} + {{x}} = 2{{x}}"
        let result = loader.render(template: template, variables: ["x": "1"])
        #expect(result == "1 + 1 = 21")
    }

    @Test("render handles all six spec variables")
    func renderAllSpecVariables() {
        let loader = PromptTemplateLoader()
        let template = """
        Company: {{companySlug}} ({{companyId}})
        Task: {{taskTitle}} ({{taskId}})
        API: {{apiBaseURL}}
        {{claimInstruction}}
        """
        let variables: [String: String] = [
            "companyId": "abc-123",
            "companySlug": "acme",
            "taskId": "task-456",
            "taskTitle": "Fix the widget",
            "apiBaseURL": "http://localhost:3900",
            "claimInstruction": "1. Claim your task",
        ]
        let result = loader.render(template: template, variables: variables)
        #expect(result.contains("acme (abc-123)"))
        #expect(result.contains("Fix the widget (task-456)"))
        #expect(result.contains("http://localhost:3900"))
        #expect(result.contains("1. Claim your task"))
    }

    // MARK: - Template Loading Fallback Chain

    @Test("loadTemplate falls back to bundled when no custom files exist")
    func loadTemplateFallsToBundled() {
        // Use a non-existent workspace path to skip workspace override
        let loader = PromptTemplateLoader(workspacePath: "/tmp/shiki-test-nonexistent-\(UUID().uuidString)")
        let (template, source) = loader.loadTemplate()
        // Should resolve to bundled or hardcoded (depending on test environment)
        #expect(source == .bundled || source == .hardcoded)
        #expect(template.contains("{{companySlug}}"))
        #expect(template.contains("{{apiBaseURL}}"))
    }

    @Test("loadTemplate prefers workspace file over user and bundled")
    func loadTemplateWorkspaceOverride() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-ws-\(UUID().uuidString)")
        let shikiDir = tmpDir.appendingPathComponent(".shiki")
        try FileManager.default.createDirectory(at: shikiDir, withIntermediateDirectories: true)
        let templateFile = shikiDir.appendingPathComponent("autopilot-prompt.md")
        let customContent = "Custom workspace template for {{companySlug}}"
        try customContent.write(to: templateFile, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let loader = PromptTemplateLoader(workspacePath: tmpDir.path)
        let (template, source) = loader.loadTemplate()
        #expect(source == .workspace(templateFile.path))
        #expect(template == customContent)
    }

    @Test("loadTemplate hot-reloads when file changes")
    func loadTemplateHotReload() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-reload-\(UUID().uuidString)")
        let shikiDir = tmpDir.appendingPathComponent(".shiki")
        try FileManager.default.createDirectory(at: shikiDir, withIntermediateDirectories: true)
        let templateFile = shikiDir.appendingPathComponent("autopilot-prompt.md")

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write initial content
        try "Version 1".write(to: templateFile, atomically: true, encoding: .utf8)

        let loader = PromptTemplateLoader(workspacePath: tmpDir.path)
        let (template1, _) = loader.loadTemplate()
        #expect(template1 == "Version 1")

        // Modify the file — need to change mtime
        // Sleep briefly so mtime actually differs (filesystem granularity)
        Thread.sleep(forTimeInterval: 0.1)
        try "Version 2".write(to: templateFile, atomically: true, encoding: .utf8)

        let (template2, _) = loader.loadTemplate()
        #expect(template2 == "Version 2")
    }

    @Test("hardcoded template contains all expected placeholders")
    func hardcodedTemplateContainsPlaceholders() {
        let template = PromptTemplateLoader.hardcodedTemplate
        #expect(template.contains("{{companySlug}}"))
        #expect(template.contains("{{companyId}}"))
        #expect(template.contains("{{apiBaseURL}}"))
        #expect(template.contains("{{claimInstruction}}"))
    }

    // MARK: - Integration with CompanyLauncher

    @Test("buildAutopilotPrompt renders with template loader")
    func buildAutopilotPromptUsesTemplate() {
        let loader = PromptTemplateLoader(workspacePath: "/tmp/nonexistent-\(UUID().uuidString)")
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "company-123",
            companySlug: "acme",
            taskId: "task-456",
            title: "Build feature X",
            templateLoader: loader
        )
        #expect(prompt.contains("acme"))
        #expect(prompt.contains("company-123"))
        #expect(prompt.contains("Build feature X"))
        #expect(prompt.contains("task-456"))
        #expect(prompt.contains("http://localhost:3900"))
        // Verify the claim instruction was rendered (not raw placeholder)
        #expect(!prompt.contains("{{claimInstruction}}"))
        #expect(prompt.contains("Your assigned task"))
    }

    @Test("buildAutopilotPrompt with empty taskId generates claim-next instruction")
    func buildAutopilotPromptEmptyTaskId() {
        let loader = PromptTemplateLoader(workspacePath: "/tmp/nonexistent-\(UUID().uuidString)")
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "company-123",
            companySlug: "acme",
            taskId: "",
            title: "",
            templateLoader: loader
        )
        #expect(prompt.contains("Claim your next task"))
        #expect(!prompt.contains("Your assigned task"))
    }
}
