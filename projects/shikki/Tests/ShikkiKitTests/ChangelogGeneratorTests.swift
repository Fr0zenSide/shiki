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
}
