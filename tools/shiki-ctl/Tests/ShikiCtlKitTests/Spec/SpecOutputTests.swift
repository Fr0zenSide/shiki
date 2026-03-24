import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("SpecOutput — BR-SP-02 file creation, DB record, inbox item")
struct SpecOutputTests {

    // Helper: generate valid spec markdown
    private func makeValidSpec(title: String = "Output Test Feature", lineCount: Int = 60) -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("## Summary")
        lines.append("Test spec for output validation.")
        lines.append("")
        lines.append("## Requirements")
        for i in 1...5 {
            lines.append("\(i). Requirement \(i)")
        }
        lines.append("")
        lines.append("## Wave 1")
        while lines.count < lineCount {
            lines.append("- Implementation detail \(lines.count)")
        }
        return lines.joined(separator: "\n")
    }

    // BR-SP-02: Spec file is created at features/*.md
    @Test("Spec file created on disk with correct content")
    func specFileCreated() async throws {
        let agent = MockAgentProvider()
        let specContent = makeValidSpec(title: "File Creation Test")
        agent.response = specContent

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-output-\(UUID().uuidString)"
        let featuresDir = "\(tmpDir)/features"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: featuresDir
        )

        let result = try await pipeline.run(input: .freeText("File creation test"), companySlug: nil)

        // Verify file exists on disk
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: result.specPath))

        // Verify content matches agent output
        let content = try String(contentsOfFile: result.specPath, encoding: .utf8)
        #expect(content == specContent)

        // Verify path structure
        #expect(result.specPath.hasPrefix(featuresDir))
        #expect(result.specPath.hasSuffix(".md"))

        try? fm.removeItem(atPath: tmpDir)
    }

    // BR-SP-02: DB record created with correct metadata
    @Test("DB record saved with title, path, line count, and company")
    func dbRecordCreated() async throws {
        let agent = MockAgentProvider()
        agent.response = makeValidSpec(title: "DB Record Test", lineCount: 75)

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-db-\(UUID().uuidString)"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: "\(tmpDir)/features"
        )

        let result = try await pipeline.run(input: .freeText("DB test"), companySlug: "brainy")

        #expect(persister.saveCallCount == 1)
        #expect(persister.savedTitle == "DB Record Test")
        #expect(persister.savedSpecPath == result.specPath)
        #expect(persister.savedCompanySlug == "brainy")

        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    // BR-SP-04: Inbox item created automatically
    @Test("Inbox item created on spec completion — no manual step")
    func inboxItemCreated() async throws {
        let agent = MockAgentProvider()
        agent.response = makeValidSpec(title: "Inbox Test")

        let persister = MockSpecPersister()
        let tmpDir = NSTemporaryDirectory() + "shiki-spec-inbox-out-\(UUID().uuidString)"

        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: "\(tmpDir)/features"
        )

        _ = try await pipeline.run(input: .freeText("Inbox output test"), companySlug: "maya")

        // BR-SP-04: Inbox item created automatically, no manual step
        #expect(persister.inboxCallCount == 1)

        // Even if DB save fails, inbox should still attempt
        let failPersister = MockSpecPersister()
        failPersister.shouldThrow = true
        let agent2 = MockAgentProvider()
        agent2.response = makeValidSpec(title: "Resilience Test")

        let pipeline2 = SpecPipeline(
            agent: agent2,
            persister: failPersister,
            featuresDirectory: "\(tmpDir)/features2"
        )

        // Pipeline should succeed even with persister failures (soft-fail)
        let result = try await pipeline2.run(input: .freeText("Resilience test"), companySlug: nil)
        #expect(result.lineCount >= 50)

        try? FileManager.default.removeItem(atPath: tmpDir)
    }
}

// MARK: - Slugify Tests

@Suite("SpecPipeline.slugify")
struct SpecSlugifyTests {

    @Test("Slugify produces valid filenames")
    func slugify_producesValidFilenames() {
        #expect(SpecPipeline.slugify("Add Dark Mode") == "add-dark-mode")
        #expect(SpecPipeline.slugify("WabiSabi SPM Migration") == "wabisabi-spm-migration")
        #expect(SpecPipeline.slugify("Feature with  extra   spaces") == "feature-with-extra-spaces")
        #expect(SpecPipeline.slugify("Special chars! @#$ removed") == "special-chars-removed")
        #expect(SpecPipeline.slugify("") == "untitled-spec")
        #expect(SpecPipeline.slugify("   ") == "untitled-spec")
    }

    @Test("Slugify truncates long titles")
    func slugify_truncatesLongTitles() {
        let longTitle = String(repeating: "a very long title ", count: 10)
        let slug = SpecPipeline.slugify(longTitle)
        #expect(slug.count <= 60)
    }
}

// MARK: - PromptBuilder Tests

@Suite("SpecPromptBuilder")
struct SpecPromptBuilderTests {

    @Test("Prompt includes feature name and company")
    func promptIncludesContext() {
        let prompt = SpecPromptBuilder.build(
            featureName: "Dark mode",
            companySlug: "wabisabi",
            existingSpecPaths: ["features/spm-migration.md"]
        )

        #expect(prompt.contains("Dark mode"))
        #expect(prompt.contains("wabisabi"))
        #expect(prompt.contains("spm-migration.md"))
        #expect(prompt.contains("50 lines"))
    }

    @Test("Prompt works without optional fields")
    func promptWorksWithoutOptionals() {
        let prompt = SpecPromptBuilder.build(
            featureName: "Simple feature",
            companySlug: nil,
            existingSpecPaths: []
        )

        #expect(prompt.contains("Simple feature"))
        #expect(!prompt.contains("Target Company"))
        #expect(!prompt.contains("Existing Specs"))
    }
}
