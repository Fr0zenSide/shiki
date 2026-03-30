import Foundation
import Testing
@testable import ShikkiKit

@Suite("ChangelogGenerator")
struct ChangelogGeneratorTests {

    @Test("Conventional commits group correctly")
    func conventionalCommitsGroupCorrectly() {
        let generator = ChangelogGenerator()
        let commits = [
            "feat: add ship command",
            "feat: add dry-run mode",
            "fix: correct version parsing",
            "fix: handle empty changelog",
            "refactor: extract gate protocol",
            "chore: update dependencies",
        ]

        let changelog = generator.generate(from: commits)

        #expect(changelog.sections.contains { $0.title == "Added" && $0.entries.count == 2 })
        #expect(changelog.sections.contains { $0.title == "Fixed" && $0.entries.count == 2 })
        #expect(changelog.sections.contains { $0.title == "Changed" && $0.entries.count == 1 })
        #expect(changelog.sections.contains { $0.title == "Maintenance" && $0.entries.count == 1 })
    }

    @Test("No conventional prefixes falls back to raw Changes")
    func noConventionalPrefixesFallback() {
        let generator = ChangelogGenerator()
        let commits = [
            "Add ship command",
            "Fix version parsing",
            "Update dependencies",
        ]

        let changelog = generator.generate(from: commits)

        #expect(changelog.sections.count == 1)
        #expect(changelog.sections[0].title == "Changes")
        #expect(changelog.sections[0].entries.count == 3)
    }

    @Test("Mixed conventional and non-conventional puts non-conventional in Other")
    func mixedCommits() {
        let generator = ChangelogGenerator()
        let commits = [
            "feat: add TestFlight support",
            "Update README",
            "fix: handle nil config",
        ]

        let changelog = generator.generate(from: commits)

        #expect(changelog.sections.contains { $0.title == "Added" && $0.entries.count == 1 })
        #expect(changelog.sections.contains { $0.title == "Fixed" && $0.entries.count == 1 })
        #expect(changelog.sections.contains { $0.title == "Other" && $0.entries.count == 1 })
    }

    @Test("Markdown rendering includes headers and bullets")
    func markdownRendering() {
        let generator = ChangelogGenerator()
        let commits = [
            "feat: add ship",
            "fix: correct parsing",
        ]

        let changelog = generator.generate(from: commits)
        let md = changelog.markdown

        #expect(md.contains("### Added"))
        #expect(md.contains("- add ship"))
        #expect(md.contains("### Fixed"))
        #expect(md.contains("- correct parsing"))
    }

    @Test("Scoped conventional commits parsed correctly")
    func scopedCommits() {
        let generator = ChangelogGenerator()
        let commits = [
            "feat(ship): add pipeline-of-gates",
            "fix(tui): correct ANSI rendering",
            "chore(deps): bump swift-argument-parser",
        ]

        let changelog = generator.generate(from: commits)

        #expect(changelog.sections.contains { $0.title == "Added" })
        #expect(changelog.sections.contains { $0.title == "Fixed" })
        #expect(changelog.sections.contains { $0.title == "Maintenance" })
    }

    @Test("Empty commits produce empty changelog")
    func emptyCommits() {
        let generator = ChangelogGenerator()
        let changelog = generator.generate(from: [])

        #expect(changelog.sections.count == 1)
        #expect(changelog.sections[0].entries.isEmpty)
    }
}
