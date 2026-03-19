import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("SpecDocument living specs")
struct SpecDocumentTests {

    @Test("Generate spec from task context")
    func generateFromContext() {
        let spec = SpecDocument(
            taskId: "t-42",
            title: "SPM wave 3 migration",
            companySlug: "wabisabi",
            branch: "feature/spm-wave3"
        )
        let markdown = spec.render()

        #expect(markdown.contains("# SPM wave 3 migration"))
        #expect(markdown.contains("Task: t-42"))
        #expect(markdown.contains("Company: wabisabi"))
        #expect(markdown.contains("Branch: feature/spm-wave3"))
        #expect(markdown.contains("## Requirements"))
        #expect(markdown.contains("## Implementation Plan"))
        #expect(markdown.contains("## Decisions"))
    }

    @Test("Add requirement checkbox")
    func addRequirement() {
        var spec = SpecDocument(
            taskId: "t-1", title: "Test", companySlug: "test", branch: "test"
        )
        spec.addRequirement("Write failing test first")
        spec.addRequirement("Implement production code")

        let markdown = spec.render()
        #expect(markdown.contains("- [ ] Write failing test first"))
        #expect(markdown.contains("- [ ] Implement production code"))
    }

    @Test("Complete requirement toggles checkbox")
    func completeRequirement() {
        var spec = SpecDocument(
            taskId: "t-1", title: "Test", companySlug: "test", branch: "test"
        )
        spec.addRequirement("Write tests")
        spec.completeRequirement(at: 0)

        let markdown = spec.render()
        #expect(markdown.contains("- [x] Write tests"))
    }

    @Test("Add decision with rationale")
    func addDecision() {
        var spec = SpecDocument(
            taskId: "t-1", title: "Test", companySlug: "test", branch: "test"
        )
        spec.addDecision(
            question: "Actor or class for the registry?",
            answer: "Actor — thread-safe by default",
            rationale: "Avoids manual locking, aligns with Swift 6"
        )

        let markdown = spec.render()
        #expect(markdown.contains("**Q:** Actor or class for the registry?"))
        #expect(markdown.contains("**A:** Actor — thread-safe by default"))
        #expect(markdown.contains("_Rationale:_ Avoids manual locking"))
    }

    @Test("Add implementation phase")
    func addPhase() {
        var spec = SpecDocument(
            taskId: "t-1", title: "Test", companySlug: "test", branch: "test"
        )
        spec.addPhase(name: "Phase 1: Models", status: .inProgress)
        spec.addPhase(name: "Phase 2: Tests", status: .pending)

        let markdown = spec.render()
        #expect(markdown.contains("Phase 1: Models"))
        #expect(markdown.contains("[IN PROGRESS]"))
        #expect(markdown.contains("[PENDING]"))
    }

    @Test("Update phase status")
    func updatePhaseStatus() {
        var spec = SpecDocument(
            taskId: "t-1", title: "Test", companySlug: "test", branch: "test"
        )
        spec.addPhase(name: "Phase 1", status: .pending)
        spec.updatePhase(at: 0, status: .completed)

        let markdown = spec.render()
        #expect(markdown.contains("[COMPLETED]"))
    }

    @Test("Spec is Codable for persistence")
    func specIsCodable() throws {
        var spec = SpecDocument(
            taskId: "t-1", title: "Codable test",
            companySlug: "maya", branch: "feature/test"
        )
        spec.addRequirement("First requirement")
        spec.addDecision(question: "Q?", answer: "A", rationale: "R")
        spec.addPhase(name: "P1", status: .completed)

        let encoder = JSONEncoder()
        let data = try encoder.encode(spec)
        let decoded = try JSONDecoder().decode(SpecDocument.self, from: data)

        #expect(decoded.taskId == "t-1")
        #expect(decoded.requirements.count == 1)
        #expect(decoded.decisions.count == 1)
        #expect(decoded.phases.count == 1)
        #expect(decoded.phases[0].status == .completed)
    }

    @Test("Write and read spec from file")
    func writeAndReadFile() throws {
        let basePath = NSTemporaryDirectory() + "shiki-spec-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        var spec = SpecDocument(
            taskId: "t-99", title: "File test",
            companySlug: "flsh", branch: "feature/mlx"
        )
        spec.addRequirement("Test file I/O")
        spec.completeRequirement(at: 0)

        let filePath = "\(basePath)/t-99.md"
        try spec.write(to: filePath)

        #expect(fm.fileExists(atPath: filePath))
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(content.contains("# File test"))
        #expect(content.contains("- [x] Test file I/O"))

        try? fm.removeItem(atPath: basePath)
    }
}
