import Foundation
import Testing
@testable import ShikiCtlKit

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
}
