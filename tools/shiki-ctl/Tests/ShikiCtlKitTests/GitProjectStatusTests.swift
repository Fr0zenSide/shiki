import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Git and Project status formatters")
struct GitProjectStatusTests {

    // MARK: - Git Status Formatter

    @Test("Git format shows branch name")
    func gitFormatBranch() {
        let info = GitStatusFormatter.GitInfo(branch: "feature/shiki-ship")
        let output = GitStatusFormatter.format(info)
        #expect(output.contains("feature/shiki-ship"))
    }

    @Test("Git format truncates long branch names")
    func gitFormatLongBranch() {
        let info = GitStatusFormatter.GitInfo(branch: "feature/this-is-a-very-long-branch-name-that-should-be-truncated")
        let output = GitStatusFormatter.format(info)
        #expect(output.contains("..."))
    }

    @Test("Git format shows staged and modified counts")
    func gitFormatStatus() {
        let info = GitStatusFormatter.GitInfo(branch: "main", staged: 3, modified: 2)
        let output = GitStatusFormatter.format(info)
        #expect(output.contains("+3"))
        #expect(output.contains("!2"))
    }

    @Test("Git format shows ahead/behind")
    func gitFormatAheadBehind() {
        let info = GitStatusFormatter.GitInfo(branch: "develop", ahead: 5, behind: 2)
        let output = GitStatusFormatter.format(info)
        #expect(output.contains("⇡5"))
        #expect(output.contains("⇣2"))
    }

    @Test("Git format shows worktree indicator")
    func gitFormatWorktree() {
        let info = GitStatusFormatter.GitInfo(branch: "feature/x", isWorktree: true)
        let output = GitStatusFormatter.format(info)
        #expect(output.contains("⛓"))
    }

    @Test("Git format clean repo shows only branch")
    func gitFormatClean() {
        let info = GitStatusFormatter.GitInfo(branch: "main")
        let output = GitStatusFormatter.format(info)
        #expect(output.contains("main"))
        #expect(!output.contains("+"))
        #expect(!output.contains("!"))
        #expect(!output.contains("⇡"))
    }

    @Test("Git format with arrows wraps correctly")
    func gitFormatWithArrows() {
        let info = GitStatusFormatter.GitInfo(branch: "main")
        let output = GitStatusFormatter.format(info, arrowStyle: .both)
        #expect(output.hasPrefix("\u{E0B2}"))
        #expect(output.hasSuffix("\u{E0B0}"))
    }

    @Test("Git no repo format")
    func gitNoRepo() {
        let output = GitStatusFormatter.formatNoRepo()
        #expect(output.contains("no repo"))
    }

    @Test("Git remote icon shows for github")
    func gitRemoteIcon() {
        let github = GitStatusFormatter.GitInfo(branch: "main", remote: "https://github.com/org/repo")
        let noRemote = GitStatusFormatter.GitInfo(branch: "main")
        let withRemote = GitStatusFormatter.format(github)
        let withoutRemote = GitStatusFormatter.format(noRemote)
        // Remote version should have more content (the icon)
        #expect(withRemote.count > withoutRemote.count)
    }

    // MARK: - Project Status Formatter

    @Test("Project format with Swift language")
    func projectFormatSwift() {
        let project = ProjectStatusFormatter.ProjectInfo(language: .swift, version: "6.0")
        let output = ProjectStatusFormatter.format(project: project, tests: nil)
        #expect(output.contains("6.0"))
        // Icon is a Nerd Font glyph — verify it's present by checking output is longer than just "6.0"
        #expect(output.count > 10)
    }

    @Test("Project format with test status passing")
    func projectFormatTestsPassing() {
        let project = ProjectStatusFormatter.ProjectInfo(language: .swift)
        let tests = ProjectStatusFormatter.TestStatus(passed: 310, total: 310, failed: 0)
        let output = ProjectStatusFormatter.format(project: project, tests: tests)
        #expect(output.contains("✓310/310"))
    }

    @Test("Project format with test failures")
    func projectFormatTestsFailing() {
        let project = ProjectStatusFormatter.ProjectInfo(language: .go, version: "1.22")
        let tests = ProjectStatusFormatter.TestStatus(passed: 45, total: 50, failed: 5)
        let output = ProjectStatusFormatter.format(project: project, tests: tests)
        #expect(output.contains("✗45/50"))
    }

    @Test("Project format no project detected")
    func projectFormatNoProject() {
        let output = ProjectStatusFormatter.format(project: nil, tests: nil)
        #expect(output.contains("no project"))
    }

    @Test("Project format with arrows")
    func projectFormatWithArrows() {
        let project = ProjectStatusFormatter.ProjectInfo(language: .rust, version: "1.77")
        let output = ProjectStatusFormatter.format(project: project, tests: nil, arrowStyle: .left)
        #expect(output.hasPrefix("\u{E0B2}"))
    }

    @Test("Test cache write and read")
    func testCacheRoundtrip() throws {
        let tmpDir = NSTemporaryDirectory() + "shiki-test-cache-\(UUID().uuidString)"
        let status = ProjectStatusFormatter.TestStatus(passed: 42, total: 50, failed: 8)
        ProjectStatusFormatter.cacheTestResults(status, at: tmpDir)
        let loaded = ProjectStatusFormatter.readCachedTests(at: tmpDir)
        #expect(loaded?.passed == 42)
        #expect(loaded?.total == 50)
        #expect(loaded?.failed == 8)
    }

    // MARK: - Language Icons

    @Test("All languages produce formatted output")
    func allLanguagesFormat() {
        let languages: [ProjectStatusFormatter.Language] = [.swift, .go, .rust, .node, .python, .kotlin, .java, .deno]
        for lang in languages {
            let project = ProjectStatusFormatter.ProjectInfo(language: lang, version: "1.0")
            let output = ProjectStatusFormatter.format(project: project, tests: nil)
            #expect(output.contains("1.0"), "Missing version for \(lang.rawValue)")
        }
    }
}
