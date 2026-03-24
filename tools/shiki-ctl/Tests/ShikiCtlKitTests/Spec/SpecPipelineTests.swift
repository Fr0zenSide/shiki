import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Mocks

/// Mock agent that returns a configurable response.
final class MockAgentProvider: AgentProviding, @unchecked Sendable {
    var response: String = ""
    var shouldThrow: Bool = false
    var runCallCount: Int = 0
    var lastPrompt: String?
    var lastTimeout: TimeInterval?

    func run(prompt: String, timeout: TimeInterval) async throws -> String {
        runCallCount += 1
        lastPrompt = prompt
        lastTimeout = timeout
        if shouldThrow {
            throw SpecPipelineError.agentFailed("Mock agent failure")
        }
        return response
    }
}

/// Mock persister that tracks calls.
final class MockSpecPersister: SpecPersisting, @unchecked Sendable {
    var saveCallCount: Int = 0
    var inboxCallCount: Int = 0
    var savedTitle: String?
    var savedSpecPath: String?
    var savedCompanySlug: String?
    var shouldThrow: Bool = false

    func saveSpecRecord(title: String, specPath: String, lineCount: Int, companySlug: String?) async throws {
        saveCallCount += 1
        savedTitle = title
        savedSpecPath = specPath
        savedCompanySlug = companySlug
        if shouldThrow {
            throw SpecPipelineError.backendError("Mock DB failure")
        }
    }

    func createInboxItem(title: String, specPath: String, companySlug: String?) async throws {
        inboxCallCount += 1
        if shouldThrow {
            throw SpecPipelineError.backendError("Mock inbox failure")
        }
    }
}

// MARK: - Test Helpers

/// Generate a valid spec output with the given number of lines.
private func makeSpecOutput(title: String = "Test Feature", lineCount: Int = 60) -> String {
    var lines: [String] = []
    lines.append("# \(title)")
    lines.append("")
    lines.append("## Summary")
    lines.append("A test feature specification for validation.")
    lines.append("")
    lines.append("## Requirements")
    for i in 1...5 {
        lines.append("\(i). Requirement \(i)")
    }
    lines.append("")
    lines.append("## Wave 1")
    lines.append("Parallel group A")
    // Pad to desired line count
    while lines.count < lineCount {
        lines.append("- Detail line \(lines.count)")
    }
    return lines.joined(separator: "\n")
}

@Suite("SpecPipeline — BR-SP-01 through BR-SP-05")
struct SpecPipelineTests {

    // BR-SP-01: shikki spec is the #1 priority component — pipeline runs end-to-end
    @Test("BR-SP-01: Full pipeline produces spec from free text")
    func fullPipeline_freeText_producesSpec() async throws {
        let agent = MockAgentProvider()
        agent.response = makeSpecOutput(title: "Dark Mode for WabiSabi")

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-test-\(UUID().uuidString)"
        let featuresDir = "\(tmpDir)/features"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: featuresDir
        )

        let result = try await pipeline.run(
            input: .freeText("Add dark mode to WabiSabi"),
            companySlug: "wabisabi"
        )

        #expect(result.specPath.contains("features/"))
        #expect(result.specPath.hasSuffix(".md"))
        #expect(result.lineCount >= 50)
        #expect(result.title == "Dark Mode for WabiSabi")
        #expect(result.companySlug == "wabisabi")
        #expect(agent.runCallCount == 1)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    // BR-SP-03: Spec accepts backlog item ID, #N shorthand, or free text
    @Test("BR-SP-03: Input resolution — free text, UUID, shorthand")
    func inputResolution_allFormats() throws {
        let agent = MockAgentProvider()
        let persister = MockSpecPersister()
        let pipeline = SpecPipeline(agent: agent, persister: persister)

        // Free text
        let freeText = try pipeline.resolveInput(.freeText("Add dark mode"))
        #expect(freeText == "Add dark mode")

        // UUID
        let uuid = UUID().uuidString
        let backlog = try pipeline.resolveInput(.backlogItem(uuid))
        #expect(backlog.contains(uuid))

        // Shorthand
        let shorthand = try pipeline.resolveInput(.shorthand(3))
        #expect(shorthand.contains("#3"))

        // Invalid cases
        #expect(throws: SpecPipelineError.self) {
            try pipeline.resolveInput(.freeText(""))
        }
        #expect(throws: SpecPipelineError.self) {
            try pipeline.resolveInput(.freeText("   "))
        }
        #expect(throws: SpecPipelineError.self) {
            try pipeline.resolveInput(.backlogItem("not-a-uuid"))
        }
        #expect(throws: SpecPipelineError.self) {
            try pipeline.resolveInput(.shorthand(0))
        }
    }

    // BR-SP-02: SpecGate — spec must be >= 50 lines
    @Test("BR-SP-02: SpecGate rejects specs under 50 lines")
    func specGate_tooShort_throws() async {
        let agent = MockAgentProvider()
        agent.response = "# Short\nToo short."  // Only 2 lines

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-gate-\(UUID().uuidString)"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: "\(tmpDir)/features"
        )

        do {
            _ = try await pipeline.run(input: .freeText("Short feature"), companySlug: nil)
            Issue.record("Expected specGateFailed error")
        } catch let error as SpecPipelineError {
            if case .specGateFailed(let lines) = error {
                #expect(lines == 2)
            } else {
                Issue.record("Expected specGateFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        // Persister should NOT have been called (gate failed before persistence)
        #expect(persister.saveCallCount == 0)
        #expect(persister.inboxCallCount == 0)

        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    // BR-SP-04: Spec completion triggers inbox item automatically
    @Test("BR-SP-04: Completion triggers DB save + inbox item")
    func completion_triggersDBAndInbox() async throws {
        let agent = MockAgentProvider()
        agent.response = makeSpecOutput(title: "Inbox Trigger Test")

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-inbox-\(UUID().uuidString)"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: "\(tmpDir)/features"
        )

        _ = try await pipeline.run(input: .freeText("Test inbox trigger"), companySlug: "maya")

        #expect(persister.saveCallCount == 1)
        #expect(persister.inboxCallCount == 1)
        #expect(persister.savedTitle == "Inbox Trigger Test")
        #expect(persister.savedCompanySlug == "maya")

        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    // BR-SP-05: Multi-project targeting via --company
    @Test("BR-SP-05: Company slug flows through pipeline to output and DB")
    func companySlug_flowsThrough() async throws {
        let agent = MockAgentProvider()
        agent.response = makeSpecOutput(title: "Maya Feature")

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-company-\(UUID().uuidString)"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: "\(tmpDir)/features"
        )

        let result = try await pipeline.run(input: .freeText("Geo-discovery"), companySlug: "maya")

        // Company flows into result
        #expect(result.companySlug == "maya")
        // Company flows into persister
        #expect(persister.savedCompanySlug == "maya")
        // Company included in prompt
        #expect(agent.lastPrompt?.contains("maya") == true)

        try? FileManager.default.removeItem(atPath: tmpDir)
    }
}
