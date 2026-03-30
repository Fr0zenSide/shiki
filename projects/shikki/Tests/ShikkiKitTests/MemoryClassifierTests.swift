import Foundation
import Testing
@testable import ShikkiKit

@Suite("MemoryClassifier — BR-27 deterministic classification")
struct MemoryClassifierTests {

    let classifier = MemoryClassifier()

    // MARK: - MEMORY.md skip

    @Test("MEMORY.md returns nil (skipped)")
    func memoryMdSkipped() {
        let result = classifier.classify("MEMORY.md")
        #expect(result == nil)
    }

    // MARK: - User identity files

    @Test("user_* files classify as personal/identity")
    func userFiles() {
        let result = classifier.classify("user_identity.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .identity)
    }

    @Test("email-signature.md classifies as personal/identity")
    func emailSignature() {
        let result = classifier.classify("email-signature.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .identity)
    }

    @Test("user_profile-extended.md classifies as personal/identity")
    func userProfileExtended() {
        let result = classifier.classify("user_profile-extended.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .identity)
    }

    // MARK: - Feedback files (BR-05)

    @Test("feedback_* files classify as personal/preference")
    func feedbackFiles() {
        let examples = [
            "feedback_stop-asking-just-do.md",
            "feedback_no-print-in-tests.md",
            "feedback_emacs-keybindings.md",
            "feedback_testing-strategy.md",
        ]
        for file in examples {
            let result = classifier.classify(file)
            #expect(result?.scope == .personal, "Expected personal scope for \(file)")
            #expect(result?.category == .preference, "Expected preference category for \(file)")
        }
    }

    // MARK: - Reference files

    @Test("reference_*-radar.md classifies as personal/radar")
    func radarReferences() {
        let result = classifier.classify("reference_gh-trending-radar-2026-03-25.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .radar)
    }

    @Test("reference_* (non-radar) classifies as company/reference")
    func companyReferences() {
        let result = classifier.classify("reference_qmd-search-engine.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .reference)
    }

    @Test("reference_openfang-ideas.md classifies as company/reference")
    func openfangReference() {
        let result = classifier.classify("reference_openfang-ideas.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .reference)
    }

    // MARK: - Special non-project files

    @Test("maya-backlog.md classifies as project/backlog")
    func mayaBacklog() {
        let result = classifier.classify("maya-backlog.md")
        #expect(result?.scope == .project)
        #expect(result?.category == .backlog)
        #expect(result?.projectId == MemoryClassifier.projectMaya)
    }

    @Test("media-strategy.md classifies as company/strategy")
    func mediaStrategy() {
        let result = classifier.classify("media-strategy.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .strategy)
    }

    @Test("object-storage.md classifies as company/infrastructure")
    func objectStorage() {
        let result = classifier.classify("object-storage.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .infrastructure)
    }

    // MARK: - Project files — personal strategy

    @Test("project_ial-* classifies as personal/strategy")
    func ialFiles() {
        let result = classifier.classify("project_ial-maya-fundraising.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .strategy)
        #expect(result?.projectId == MemoryClassifier.projectMaya)
    }

    @Test("project_*-fundraising classifies as personal/strategy")
    func fundraisingFiles() {
        let result = classifier.classify("project_some-fundraising.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .strategy)
    }

    @Test("project_*-prelaunch classifies as personal/strategy")
    func prelaunchFiles() {
        let result = classifier.classify("project_maya-prelaunch-strategy.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .strategy)
        #expect(result?.projectId == MemoryClassifier.projectMaya)
    }

    @Test("project_haiku-conversion-strategy.md classifies as personal/strategy")
    func haikuConversion() {
        let result = classifier.classify("project_haiku-conversion-strategy.md")
        #expect(result?.scope == .personal)
        #expect(result?.category == .strategy)
    }

    // MARK: - Project files — company

    @Test("project_ownership-structure.md classifies as company/infrastructure")
    func ownershipStructure() {
        let result = classifier.classify("project_ownership-structure.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .infrastructure)
    }

    @Test("project_*-vision classifies as company/vision")
    func visionFiles() {
        let result = classifier.classify("project_shiki-vision-full-topology.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .vision)
        #expect(result?.projectId == MemoryClassifier.projectShiki)
    }

    @Test("project_branding-domain.md classifies as company/vision")
    func brandingDomain() {
        let result = classifier.classify("project_branding-domain.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .vision)
    }

    @Test("project_local-llm-cluster-vision.md classifies as company/vision")
    func localLlmVision() {
        let result = classifier.classify("project_local-llm-cluster-vision.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .vision)
    }

    @Test("project_agent-skills-audit classifies as company/reference")
    func agentSkillsAudit() {
        let result = classifier.classify("project_agent-skills-audit-2026-03.md")
        #expect(result?.scope == .company)
        #expect(result?.category == .reference)
    }

    // MARK: - Project files — project scope

    @Test("project_*-backlog classifies as project/backlog")
    func backlogFiles() {
        let result = classifier.classify("project_brainy-backlog.md")
        #expect(result?.scope == .project)
        #expect(result?.category == .backlog)
        #expect(result?.projectId == MemoryClassifier.projectBrainy)
    }

    @Test("project_*-decision classifies as project/decision")
    func decisionFiles() {
        let result = classifier.classify("project_autopilot-reactor-decision.md")
        #expect(result?.scope == .project)
        #expect(result?.category == .decision)
    }

    @Test("project_*-plan classifies as project/plan")
    func planFiles() {
        let result = classifier.classify("project_maya-spm-public-api-plan.md")
        #expect(result?.scope == .project)
        #expect(result?.category == .plan)
        #expect(result?.projectId == MemoryClassifier.projectMaya)
    }

    @Test("project_*-roadmap classifies as project/plan")
    func roadmapFiles() {
        let result = classifier.classify("project_shiki-full-roadmap-v1.md")
        #expect(result?.scope == .project)
        #expect(result?.category == .plan)
        #expect(result?.projectId == MemoryClassifier.projectShiki)
    }

    @Test("Remaining project_ files default to project/plan")
    func defaultProjectFiles() {
        let result = classifier.classify("project_some-random-topic.md")
        #expect(result?.scope == .project)
        #expect(result?.category == .plan)
    }

    // MARK: - Project ID resolution (BR-08)

    @Test("Maya files resolve to Maya project ID")
    func mayaProjectId() {
        let result = classifier.classify("project_maya-philosophy.md")
        #expect(result?.projectId == MemoryClassifier.projectMaya)
    }

    @Test("WabiSabi files resolve to WabiSabi project ID")
    func wabiSabiProjectId() {
        let result = classifier.classify("project_wabisabi-backlog.md")
        #expect(result?.projectId == MemoryClassifier.projectWabiSabi)
    }

    @Test("Brainy files resolve to Brainy project ID")
    func brainyProjectId() {
        let result = classifier.classify("project_brainy-core-dna.md")
        #expect(result?.projectId == MemoryClassifier.projectBrainy)
    }

    @Test("Flsh files resolve to Flsh project ID")
    func flshProjectId() {
        let result = classifier.classify("project_flsh-revival.md")
        #expect(result?.projectId == MemoryClassifier.projectFlsh)
    }

    @Test("Shikki files resolve to Shiki project ID")
    func shikkiProjectId() {
        let result = classifier.classify("feedback_shikki-project-structure.md")
        #expect(result?.projectId == MemoryClassifier.projectShiki)
    }

    @Test("Generic files have nil project ID")
    func genericFileNoProjectId() {
        let result = classifier.classify("media-strategy.md")
        #expect(result?.projectId == nil)
    }

    // MARK: - Directory classification

    @Test("classifyDirectory throws for missing directory")
    func classifyMissingDirectory() throws {
        let classifier = MemoryClassifier()
        #expect(throws: MemoryClassifierError.self) {
            try classifier.classifyDirectory(at: "/nonexistent/path/\(UUID().uuidString)")
        }
    }

    @Test("classifyDirectory processes all .md files")
    func classifyDirectory() throws {
        let tmpDir = NSTemporaryDirectory() + "shiki-classify-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        // Create test files
        try "test".write(toFile: "\(tmpDir)/feedback_test.md", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/user_test.md", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/MEMORY.md", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/not-markdown.txt", atomically: true, encoding: .utf8)

        let results = try classifier.classifyDirectory(at: tmpDir)
        // MEMORY.md skipped, .txt skipped = 2 results
        #expect(results.count == 2)
        #expect(results.contains { $0.filename == "feedback_test.md" })
        #expect(results.contains { $0.filename == "user_test.md" })
    }

    // MARK: - Scope enum

    @Test("MemoryScope has exactly 4 cases (BR-17)")
    func scopeCount() {
        #expect(MemoryScope.allCases.count == 4)
    }

    @Test("MemoryCategory has 10 cases")
    func categoryCount() {
        #expect(MemoryCategory.allCases.count == 10)
    }

    @Test("MemoryClassification is Equatable")
    func classificationEquatable() {
        let a = MemoryClassification(filename: "test.md", scope: .personal, category: .identity)
        let b = MemoryClassification(filename: "test.md", scope: .personal, category: .identity)
        #expect(a == b)
    }
}
