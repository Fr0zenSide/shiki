import Foundation
import Testing
@testable import ShikkiKit

@Suite("VersionBumper")
struct VersionBumperTests {

    @Test("Breaking change triggers major bump")
    func breakingChangeMajorBump() {
        let bumper = VersionBumper()
        let commits = [
            "feat: add new API",
            "BREAKING CHANGE: remove old endpoint",
            "fix: typo in docs",
        ]
        let result = bumper.bump(from: "1.2.3", commits: commits)
        #expect(result == "2.0.0")
    }

    @Test("Breaking change with bang suffix triggers major bump")
    func breakingChangeBangSuffix() {
        let bumper = VersionBumper()
        let commits = [
            "feat!: redesign auth flow",
            "fix: typo",
        ]
        let result = bumper.bump(from: "1.2.3", commits: commits)
        #expect(result == "2.0.0")
    }

    @Test("feat commit triggers minor bump")
    func featMinorBump() {
        let bumper = VersionBumper()
        let commits = [
            "feat: add ship command",
            "fix: correct version parsing",
        ]
        let result = bumper.bump(from: "1.2.3", commits: commits)
        #expect(result == "1.3.0")
    }

    @Test("fix only triggers patch bump")
    func fixOnlyPatchBump() {
        let bumper = VersionBumper()
        let commits = [
            "fix: correct version parsing",
            "chore: update deps",
            "refactor: clean up imports",
        ]
        let result = bumper.bump(from: "1.2.3", commits: commits)
        #expect(result == "1.2.4")
    }

    @Test("Manual override uses provided version")
    func manualOverrideUsesProvided() {
        let bumper = VersionBumper()
        let commits = [
            "feat: add ship command",
        ]
        let result = bumper.bump(from: "1.2.3", commits: commits, override: "5.0.0")
        #expect(result == "5.0.0")
    }

    @Test("Version string with v prefix parsed correctly")
    func vPrefixParsed() {
        let bumper = VersionBumper()
        let commits = ["fix: typo"]
        let result = bumper.bump(from: "v2.1.0", commits: commits)
        #expect(result == "2.1.1")
    }

    @Test("Empty commits triggers patch bump")
    func emptyCommitsPatch() {
        let bumper = VersionBumper()
        let result = bumper.bump(from: "1.0.0", commits: [])
        #expect(result == "1.0.1")
    }

    @Test("Zero version bumps correctly")
    func zeroVersionBumps() {
        let bumper = VersionBumper()
        let commits = ["feat: initial"]
        let result = bumper.bump(from: "0.0.0", commits: commits)
        #expect(result == "0.1.0")
    }
}
