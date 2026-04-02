import Foundation
import Testing
@testable import ShikkiKit

// MARK: - TmuxProcessLauncher Window Naming Tests

@Suite("TmuxProcessLauncher -- Window Naming")
struct WindowNamingCompanyTests {

    @Test("Window name combines slug and truncated title")
    func windowNameFormat() {
        // prefix(15) of "Fix onboarding flow" = "Fix onboarding " (trailing space -> trailing hyphen)
        let name = TmuxProcessLauncher.windowName(companySlug: "wabisabi", title: "Fix onboarding flow")
        #expect(name == "wabisabi:fix-onboarding-")
    }

    @Test("Window name lowercases title")
    func windowNameLowercase() {
        let name = TmuxProcessLauncher.windowName(companySlug: "brainy", title: "Add RSS Parser")
        #expect(name == "brainy:add-rss-parser")
    }

    @Test("Window name replaces spaces with hyphens")
    func windowNameHyphens() {
        let name = TmuxProcessLauncher.windowName(companySlug: "maya", title: "New Feature Test")
        #expect(name.contains("-"))
        #expect(!name.contains(" "))
    }

    @Test("Window name truncates title to 15 chars")
    func windowNameTruncates() {
        let name = TmuxProcessLauncher.windowName(
            companySlug: "shikki",
            title: "This is a very long task title that should be truncated"
        )
        let titlePart = name.split(separator: ":").last.map(String.init) ?? ""
        #expect(titlePart.count <= 15)
    }

    @Test("Window name with short title")
    func windowNameShortTitle() {
        let name = TmuxProcessLauncher.windowName(companySlug: "maya", title: "Fix")
        #expect(name == "maya:fix")
    }

    @Test("Window name with empty title")
    func windowNameEmptyTitle() {
        let name = TmuxProcessLauncher.windowName(companySlug: "test", title: "")
        #expect(name == "test:")
    }
}

// MARK: - Autopilot Prompt Building Tests

@Suite("TmuxProcessLauncher -- Autopilot Prompt")
struct AutopilotPromptTests {

    private func makeLoader() -> PromptTemplateLoader {
        // Use hardcoded template (no workspace/user files)
        PromptTemplateLoader(workspacePath: nil)
    }

    @Test("Prompt includes company slug")
    func promptIncludesCompanySlug() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid-123", companySlug: "wabisabi",
            taskId: "task-1", title: "Fix login",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("wabisabi"))
    }

    @Test("Prompt includes task ID when provided")
    func promptIncludesTaskId() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid-123", companySlug: "test",
            taskId: "task-abc", title: "Build feature",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("task-abc"))
        #expect(prompt.contains("Build feature"))
    }

    @Test("Prompt uses claim instruction for empty taskId")
    func promptClaimForEmptyTask() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid-123", companySlug: "test",
            taskId: "", title: "",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("Claim your next task"))
    }

    @Test("Prompt uses assigned instruction for non-empty taskId")
    func promptAssignedForTask() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid-123", companySlug: "test",
            taskId: "task-42", title: "Deploy v2",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("Your assigned task"))
        #expect(prompt.contains("Deploy v2"))
    }

    @Test("Prompt includes API base URL")
    func promptIncludesApiBaseURL() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid-123", companySlug: "test",
            taskId: "task-1", title: "Test",
            apiBaseURL: "http://custom:9999",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("http://custom:9999"))
    }

    @Test("Prompt includes company ID")
    func promptIncludesCompanyId() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "company-uuid-abc", companySlug: "test",
            taskId: "task-1", title: "Test",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("company-uuid-abc"))
    }

    @Test("Prompt includes TDD and heartbeat rules from hardcoded template")
    func promptIncludesRules() {
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid", companySlug: "test",
            taskId: "t", title: "T",
            templateLoader: makeLoader()
        )
        #expect(prompt.contains("TDD"))
        #expect(prompt.contains("heartbeat") || prompt.contains("HEARTBEAT"))
    }

    @Test("Custom template loader renders variables")
    func customTemplateVariables() {
        // Create a temp workspace with a custom template
        let tempDir = NSTemporaryDirectory() + "launcher-test-\(UUID().uuidString)"
        let shikkiDir = "\(tempDir)/.shiki"
        try? FileManager.default.createDirectory(atPath: shikkiDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let customTemplate = "Agent: {{companySlug}} | Task: {{taskTitle}} | API: {{apiBaseURL}}"
        try? customTemplate.write(
            toFile: "\(shikkiDir)/autopilot-prompt.md",
            atomically: true, encoding: .utf8
        )

        let loader = PromptTemplateLoader(workspacePath: tempDir)
        let prompt = TmuxProcessLauncher.buildAutopilotPrompt(
            companyId: "uuid", companySlug: "maya",
            taskId: "t1", title: "Add maps",
            templateLoader: loader
        )
        #expect(prompt.contains("Agent: maya"))
        #expect(prompt.contains("Task: Add maps"))
        #expect(prompt.contains("API: http://localhost:3900"))
    }
}

// MARK: - TmuxProcessLauncher Initialization Tests

@Suite("TmuxProcessLauncher -- Initialization")
struct LauncherInitTests {

    @Test("Default session is shiki")
    func defaultSession() {
        let launcher = TmuxProcessLauncher(workspacePath: "/tmp/test")
        #expect(launcher.session == "shiki")
    }

    @Test("Custom session name")
    func customSession() {
        let launcher = TmuxProcessLauncher(session: "custom", workspacePath: "/tmp/test")
        #expect(launcher.session == "custom")
    }

    @Test("Workspace path is stored")
    func workspacePathStored() {
        let launcher = TmuxProcessLauncher(workspacePath: "/Users/dev/workspace")
        #expect(launcher.workspacePath == "/Users/dev/workspace")
    }
}
