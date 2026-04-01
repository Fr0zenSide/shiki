import Foundation
import Testing
@testable import ShikkiKit

@Suite("SpecMigrationService")
struct SpecMigrationServiceTests {

    let service = SpecMigrationService()

    // MARK: - Test Helpers

    /// Create a temporary directory with spec files for testing.
    private func withTempDir(
        files: [String: String],
        body: (String) throws -> Void
    ) throws {
        let tmp = NSTemporaryDirectory() + "spec-migration-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        for (name, content) in files {
            try content.write(toFile: "\(tmp)/\(name)", atomically: true, encoding: .utf8)
        }

        try body(tmp)
    }

    // MARK: - 1. Migration Adds Missing Fields

    @Test("migration adds missing progress, updated, tags, reviewers, flsh to YAML frontmatter")
    func addsMissingFieldsToYAML() throws {
        let spec = """
        ---
        title: "Test Feature"
        status: draft
        priority: P1
        created: 2026-03-31
        ---

        ## 1. Problem

        The system lacks testing support.

        ## 2. Solution

        Add comprehensive test infrastructure with Swift testing framework.

        ## 3. Implementation

        Build it step by step.
        """

        try withTempDir(files: ["test-feature.md": spec]) { dir in
            let report = try service.migrateAll(directory: dir)

            #expect(report.scanned == 1)
            #expect(report.updated == 1)
            #expect(report.upToDate == 0)

            let fileReport = report.files[0]
            #expect(fileReport.fieldsAdded.contains("progress"))
            #expect(fileReport.fieldsAdded.contains("updated"))
            #expect(fileReport.fieldsAdded.contains("reviewers"))
            #expect(fileReport.fieldsAdded.contains("flsh"))

            // Verify the written content
            let content = try String(contentsOfFile: "\(dir)/test-feature.md", encoding: .utf8)
            #expect(content.contains("progress: 0/3"))
            #expect(content.contains("updated:"))
            #expect(content.contains("reviewers: []"))
            #expect(content.contains("flsh:"))
            #expect(content.contains("duration:"))
            #expect(content.contains("sections: 3"))
        }
    }

    // MARK: - 2. Migration Preserves Existing Fields

    @Test("migration preserves all existing YAML fields untouched")
    func preservesExistingFields() throws {
        let spec = """
        ---
        title: "Already Good"
        status: validated
        progress: 5/5
        priority: P0
        project: shikki
        created: 2026-03-30
        updated: 2026-03-31
        authors: "@shi team"
        reviewers:
          - who: "@Daimyo"
            verdict: validated
        depends-on:
          - other-spec.md
        relates-to:
          - related-spec.md
        tags: [testing, swift]
        flsh:
          summary: "Already has a summary"
          duration: 3m
          sections: 5
        ---

        ## 1. Section One

        Content.

        ## 2. Section Two

        More content.
        """

        try withTempDir(files: ["good-spec.md": spec]) { dir in
            let report = try service.migrateAll(directory: dir)

            #expect(report.scanned == 1)
            #expect(report.upToDate == 1)
            #expect(report.updated == 0)

            let fileReport = report.files[0]
            #expect(fileReport.alreadyUpToDate)
            #expect(fileReport.fieldsAdded.isEmpty)

            // Verify file was NOT modified
            let content = try String(contentsOfFile: "\(dir)/good-spec.md", encoding: .utf8)
            #expect(content.contains("title: \"Already Good\""))
            #expect(content.contains("status: validated"))
            #expect(content.contains("progress: 5/5"))
            #expect(content.contains("authors: \"@shi team\""))
            #expect(content.contains("summary: \"Already has a summary\""))
        }
    }

    // MARK: - 3. Dry-Run Does Not Modify Files

    @Test("dry-run computes changes but does not write files")
    func dryRunDoesNotModify() throws {
        let spec = """
        ---
        title: "Needs Migration"
        status: draft
        ---

        ## 1. Problem

        Something broken.

        ## 2. Fix

        Fix it.
        """

        try withTempDir(files: ["needs-migration.md": spec]) { dir in
            let originalContent = try String(contentsOfFile: "\(dir)/needs-migration.md", encoding: .utf8)

            let report = try service.migrateAll(directory: dir, dryRun: true)

            #expect(report.scanned == 1)
            #expect(report.updated == 1)

            let fileReport = report.files[0]
            #expect(!fileReport.alreadyUpToDate)
            #expect(fileReport.fieldsAdded.contains("progress"))

            // Verify file was NOT changed
            let afterContent = try String(contentsOfFile: "\(dir)/needs-migration.md", encoding: .utf8)
            #expect(afterContent == originalContent)
        }
    }

    // MARK: - 4. Section Count Accuracy

    @Test("section count accurately counts ## headings, ignoring ### and #")
    func sectionCountAccuracy() {
        let body = """
        # Title (not counted)

        ## 1. First Section

        Text.

        ### 1.1 Sub-section (not counted)

        More text.

        ## 2. Second Section

        ## 3. Third Section

        #### Deep heading (not counted)

        ## 4. Fourth Section
        """

        let count = service.countSections(body)
        #expect(count == 4)
    }

    @Test("section count returns 0 for body with no ## headings")
    func sectionCountZero() {
        let body = """
        # Only a Title

        Some content without level-2 headings.

        ### A level-3 heading

        More content.
        """

        let count = service.countSections(body)
        #expect(count == 0)
    }

    // MARK: - 5. Duration Estimation

    @Test("duration estimation from word count at 150 WPM")
    func durationEstimation() {
        // 150 words = 1 minute
        #expect(service.estimateDuration(wordCount: 150) == "1m")
        // 300 words = 2 minutes
        #expect(service.estimateDuration(wordCount: 300) == "2m")
        // 750 words = 5 minutes
        #expect(service.estimateDuration(wordCount: 750) == "5m")
        // 75 words = rounds to 1m (minimum)
        #expect(service.estimateDuration(wordCount: 75) == "1m")
        // 0 words = 1m (minimum)
        #expect(service.estimateDuration(wordCount: 0) == "1m")
        // 225 words = rounds to 2m
        #expect(service.estimateDuration(wordCount: 225) == "2m")
    }

    // MARK: - 6. Status Normalization

    @Test("normalizes common status aliases to valid lifecycle values")
    func statusNormalization() {
        // Direct matches
        #expect(service.normalizeStatus("draft") == "draft")
        #expect(service.normalizeStatus("validated") == "validated")
        #expect(service.normalizeStatus("implementing") == "implementing")

        // Aliases
        #expect(service.normalizeStatus("spec") == "draft")
        #expect(service.normalizeStatus("plan") == "draft")
        #expect(service.normalizeStatus("wip") == "implementing")
        #expect(service.normalizeStatus("done") == "shipped")
        #expect(service.normalizeStatus("deprecated") == "outdated")
        #expect(service.normalizeStatus("approved") == "validated")
        #expect(service.normalizeStatus("cancelled") == "rejected")

        // Case insensitive
        #expect(service.normalizeStatus("DRAFT") == "draft")
        #expect(service.normalizeStatus("Validated") == "validated")

        // Compound strings like "PLAN — tests first"
        #expect(service.normalizeStatus("PLAN — tests first, implementation by /autopilot") == "draft")

        // Unknown defaults to draft
        #expect(service.normalizeStatus("banana") == "draft")
    }

    @Test("migration normalizes status in-place for YAML frontmatter")
    func statusNormalizationInFile() throws {
        let spec = """
        ---
        title: "Spec Status"
        status: spec
        progress: 0/2
        updated: 2026-03-31
        tags: [test]
        reviewers: []
        flsh:
          duration: 1m
          sections: 2
        ---

        ## 1. Problem

        Text.

        ## 2. Solution

        Fix.
        """

        try withTempDir(files: ["normalize.md": spec]) { dir in
            let report = try service.migrateAll(directory: dir)

            let fileReport = report.files[0]
            #expect(fileReport.statusNormalized)

            let content = try String(contentsOfFile: "\(dir)/normalize.md", encoding: .utf8)
            #expect(content.contains("status: draft"))
            #expect(!content.contains("status: spec"))
        }
    }

    // MARK: - 7. Markdown-Style Migration (FIX 2: strips old metadata)

    @Test("migrates markdown-style metadata to YAML frontmatter and strips old blockquotes")
    func markdownStyleMigration() throws {
        let spec = """
        # BrainyTube iPad Support

        > **Status**: Draft
        > **Date**: 2026-03-28
        > **Scope**: Multi-platform expansion

        ---

        ## Phase 1 — Architecture Brainstorm

        Some analysis of the options.

        ## Phase 2 — Implementation

        Build the thing.
        """

        try withTempDir(files: ["brainytube-ipad.md": spec]) { dir in
            let report = try service.migrateAll(directory: dir)

            #expect(report.updated == 1)

            let content = try String(contentsOfFile: "\(dir)/brainytube-ipad.md", encoding: .utf8)
            // Should start with YAML frontmatter
            #expect(content.hasPrefix("---\n"))
            #expect(content.contains("title: \"BrainyTube iPad Support\""))
            #expect(content.contains("status: draft"))
            #expect(content.contains("progress: 0/2"))
            #expect(content.contains("reviewers: []"))
            #expect(content.contains("flsh:"))
            // Original body should still be present
            #expect(content.contains("# BrainyTube iPad Support"))
            #expect(content.contains("## Phase 1"))

            // FIX 2: Old blockquote metadata lines should be STRIPPED
            #expect(!content.contains("> **Status**: Draft"))
            #expect(!content.contains("> **Date**: 2026-03-28"))
            #expect(!content.contains("> **Scope**: Multi-platform expansion"))
        }
    }

    // MARK: - 8. Tag Generation

    @Test("generates relevant tags from body keywords")
    func tagGeneration() {
        let body = """
        ## Problem

        The Swift testing framework needs better TUI integration.
        We need to run tests in parallel using the CLI.
        The agent orchestration should dispatch test runs.

        ## Solution

        Build a Swift-based test runner with terminal output.
        """

        let tags = service.generateTags(body)

        #expect(tags.contains("swift"))
        #expect(tags.contains("testing"))
        #expect(tags.contains("tui"))
    }

    // MARK: - BONUS FIX: Tag word boundary check

    @Test("tag generation does not false-positive match 'ai' inside 'maintain'")
    func tagWordBoundary() {
        let body = """
        ## Problem

        We need to maintain the system and make certain changes.
        The main concern is container orchestration.

        ## Solution

        Build a better maintenance pipeline.
        """

        let tags = service.generateTags(body)

        // "ai" should NOT match inside "maintain", "certain", "main", "container"
        #expect(!tags.contains("ai"))
    }

    // MARK: - 9. Single File Migration

    @Test("single file migration works independently of directory scan")
    func singleFileMigration() throws {
        let spec = """
        ---
        title: "Single File"
        status: draft
        ---

        ## 1. Overview

        Content here.
        """

        try withTempDir(files: ["single.md": spec]) { dir in
            let report = try service.migrateFile(at: "\(dir)/single.md")

            #expect(!report.alreadyUpToDate)
            #expect(report.fieldsAdded.contains("progress"))
            #expect(report.fieldsAdded.contains("flsh"))
            #expect(report.filename == "single.md")

            let content = try String(contentsOfFile: "\(dir)/single.md", encoding: .utf8)
            #expect(content.contains("progress: 0/1"))
            #expect(content.contains("sections: 1"))
        }
    }

    // MARK: - 10. Multi-File Batch Migration

    @Test("batch migration processes multiple files with mixed formats")
    func batchMigration() throws {
        let yamlSpec = """
        ---
        title: "YAML Spec"
        status: draft
        ---

        ## Section A

        Content.
        """

        let markdownSpec = """
        # Markdown Spec

        > **Status**: implementing

        ## Step 1

        Do the thing.

        ## Step 2

        Do more.
        """

        let upToDateSpec = """
        ---
        title: "Up To Date"
        status: validated
        progress: 2/2
        updated: 2026-03-31
        tags: [testing]
        reviewers: []
        flsh:
          summary: "Already done"
          duration: 1m
          sections: 2
        ---

        ## A

        Text.

        ## B

        More.
        """

        try withTempDir(files: [
            "yaml-spec.md": yamlSpec,
            "markdown-spec.md": markdownSpec,
            "up-to-date.md": upToDateSpec,
        ]) { dir in
            let report = try service.migrateAll(directory: dir)

            #expect(report.scanned == 3)
            #expect(report.updated == 2)
            #expect(report.upToDate == 1)
        }
    }

    // MARK: - 11. FIX 2: Verify body is clean after markdown-style migration

    @Test("markdown migration strips all known metadata blockquote patterns")
    func markdownMigrationStripsAllPatterns() throws {
        let spec = """
        # My Feature

        > **Status**: Draft
        > **Priority**: P1
        > **Created**: 2026-03-20
        > **Project**: shikki
        > **Authors**: @Daimyo

        Regular blockquote below should be preserved:
        > This is a normal blockquote, not metadata.

        ## 1. Overview

        Content here.
        """

        try withTempDir(files: ["feature.md": spec]) { dir in
            let report = try service.migrateAll(directory: dir)
            #expect(report.updated == 1)

            let content = try String(contentsOfFile: "\(dir)/feature.md", encoding: .utf8)
            // Metadata blockquotes stripped
            #expect(!content.contains("> **Status**: Draft"))
            #expect(!content.contains("> **Priority**: P1"))
            #expect(!content.contains("> **Created**: 2026-03-20"))
            #expect(!content.contains("> **Project**: shikki"))
            #expect(!content.contains("> **Authors**: @Daimyo"))

            // Normal blockquote preserved
            #expect(content.contains("> This is a normal blockquote, not metadata."))

            // YAML frontmatter has the data
            #expect(content.contains("title: \"My Feature\""))
            #expect(content.contains("status: draft"))
        }
    }
}
