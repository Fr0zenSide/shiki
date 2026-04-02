import Foundation
import Testing
@testable import ShikkiKit

@Suite("SpecTrackingFields")
struct SpecTrackingFieldsTests {

    let parser = SpecFrontmatterParser()
    let service = SpecFrontmatterService()
    let migrationService = SpecMigrationService()

    // MARK: - 1. Parse spec with all 3 tracking fields present

    @Test("parses spec with epic-branch, validated-commit, test-run-id")
    func parseAllTrackingFields() throws {
        let spec = """
        ---
        title: "Tracking Fields Feature"
        status: validated
        progress: 5/5
        epic-branch: feature/spec-tracking-fields
        validated-commit: abc123def456
        test-run-id: run-2026-04-02-001
        ---

        ## 1. Problem

        Need tracking fields.

        ## 2. Solution

        Add them.
        """
        let meta = try parser.parse(content: spec)

        #expect(meta.epicBranch == "feature/spec-tracking-fields")
        #expect(meta.validatedCommit == "abc123def456")
        #expect(meta.testRunId == "run-2026-04-02-001")
    }

    // MARK: - 2. Parse spec with NO tracking fields (backward compat)

    @Test("parses spec without tracking fields — all nil")
    func parseNoTrackingFields() throws {
        let spec = """
        ---
        title: "Legacy Spec"
        status: draft
        ---

        ## Overview

        Just a legacy spec with no tracking fields.
        """
        let meta = try parser.parse(content: spec)

        #expect(meta.epicBranch == nil)
        #expect(meta.validatedCommit == nil)
        #expect(meta.testRunId == nil)
    }

    // MARK: - 3. Serialize spec with tracking fields

    @Test("serializes spec with tracking fields into YAML output")
    func serializeWithTrackingFields() {
        let metadata = SpecMetadata(
            title: "Tracked Feature",
            status: .validated,
            progress: "3/3",
            epicBranch: "feature/my-epic",
            validatedCommit: "deadbeef1234",
            testRunId: "run-42"
        )

        let yaml = service.serializeToYAML(metadata)

        #expect(yaml.contains("epic-branch: feature/my-epic"))
        #expect(yaml.contains("validated-commit: deadbeef1234"))
        #expect(yaml.contains("test-run-id: run-42"))
    }

    // MARK: - 4. Serialize spec without tracking fields — omits them

    @Test("serializes spec without tracking fields — YAML omits them")
    func serializeWithoutTrackingFields() {
        let metadata = SpecMetadata(
            title: "No Tracking",
            status: .draft
        )

        let yaml = service.serializeToYAML(metadata)

        #expect(!yaml.contains("epic-branch"))
        #expect(!yaml.contains("validated-commit"))
        #expect(!yaml.contains("test-run-id"))
    }

    // MARK: - 5. Round-trip: parse → serialize → parse → same result

    @Test("round-trip preserves tracking fields through parse-serialize-parse")
    func roundTrip() throws {
        let spec = """
        ---
        title: "Round Trip Test"
        status: implementing
        progress: 2/4
        epic-branch: feature/round-trip
        validated-commit: cafebabe9999
        test-run-id: run-2026-04-02-rt
        ---

        ## 1. First

        Content.

        ## 2. Second

        More content.
        """

        // Parse original
        let meta1 = try parser.parse(content: spec)
        #expect(meta1.epicBranch == "feature/round-trip")
        #expect(meta1.validatedCommit == "cafebabe9999")
        #expect(meta1.testRunId == "run-2026-04-02-rt")

        // Serialize
        let yaml = service.serializeToYAML(meta1)

        // Re-parse via SpecFrontmatterService (wrapping in --- delimiters)
        let rebuiltSpec = "---\n\(yaml)---\n\n## 1. First\n\nContent.\n\n## 2. Second\n\nMore content.\n"
        let meta2 = try parser.parse(content: rebuiltSpec)

        #expect(meta2.epicBranch == meta1.epicBranch)
        #expect(meta2.validatedCommit == meta1.validatedCommit)
        #expect(meta2.testRunId == meta1.testRunId)
    }

    // MARK: - 6. epic-branch preserved through migration

    @Test("migration preserves epic-branch field")
    func migrationPreservesEpicBranch() throws {
        let spec = """
        ---
        title: "Migration Compat"
        status: validated
        progress: 2/2
        epic-branch: feature/important
        validated-commit: 1234abcd
        test-run-id: run-99
        updated: 2026-04-01
        tags: [testing]
        reviewers: []
        flsh:
          summary: "Migration test"
          duration: 1m
          sections: 2
        ---

        ## 1. Section A

        Content.

        ## 2. Section B

        More.
        """

        let tmp = NSTemporaryDirectory() + "spec-tracking-migration-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        try spec.write(toFile: "\(tmp)/migration-compat.md", atomically: true, encoding: .utf8)

        let report = try migrationService.migrateAll(directory: tmp)

        // Should be up-to-date (no fields missing)
        #expect(report.upToDate == 1)
        #expect(report.updated == 0)

        // Verify fields are preserved in file content
        let content = try String(contentsOfFile: "\(tmp)/migration-compat.md", encoding: .utf8)
        #expect(content.contains("epic-branch: feature/important"))
        #expect(content.contains("validated-commit: 1234abcd"))
        #expect(content.contains("test-run-id: run-99"))
    }

    // MARK: - SpecFrontmatterService parser also handles tracking fields

    @Test("SpecFrontmatterService.parse also reads tracking fields")
    func serviceParsesTrackingFields() {
        let spec = """
        ---
        title: "Service Parse Test"
        status: validated
        epic-branch: feature/service-test
        validated-commit: face0ff
        test-run-id: run-svc-1
        ---

        ## Overview

        Content.
        """

        let meta = service.parse(content: spec)

        #expect(meta?.epicBranch == "feature/service-test")
        #expect(meta?.validatedCommit == "face0ff")
        #expect(meta?.testRunId == "run-svc-1")
    }
}
