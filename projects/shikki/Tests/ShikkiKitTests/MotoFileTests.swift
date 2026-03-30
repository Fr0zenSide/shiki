import Foundation
import Testing
@testable import ShikkiKit

@Suite("MotoFile")
struct MotoFileTests {

    // MARK: - Factory

    @Test("creates MotoFile from detected Swift project")
    func fromDetectedSwift() {
        let detected = DetectedProject(
            language: .swift,
            framework: .swiftUI,
            buildSystem: .spm,
            hasGit: true,
            hasTests: true,
            name: "MyApp"
        )

        let moto = MotoFile.from(detected: detected)

        #expect(moto.name == "MyApp")
        #expect(moto.language == "swift")
        #expect(moto.framework == "swiftUI")
        #expect(moto.buildSystem == "spm")
        #expect(moto.testCommand == "swift test")
        #expect(moto.buildCommand == "swift build")
        #expect(moto.lintCommand == "swiftlint")
        #expect(moto.agents?.maxConcurrency == 3)
        #expect(moto.agents?.budgetDailyUSD == 10.0)
    }

    @Test("creates MotoFile from detected TypeScript project")
    func fromDetectedTS() {
        let detected = DetectedProject(
            language: .typescript,
            framework: .nextjs,
            buildSystem: .npm,
            hasGit: true,
            hasTests: false,
            name: "web-app"
        )

        let moto = MotoFile.from(detected: detected)

        #expect(moto.language == "typescript")
        #expect(moto.framework == "nextjs")
        #expect(moto.testCommand == "npm test")
        #expect(moto.buildCommand == "npm run build")
        #expect(moto.lintCommand == "npx eslint .")
    }

    @Test("creates MotoFile from detected Rust project")
    func fromDetectedRust() {
        let detected = DetectedProject(
            language: .rust,
            buildSystem: .cargo,
            name: "my-crate"
        )

        let moto = MotoFile.from(detected: detected)

        #expect(moto.testCommand == "cargo test")
        #expect(moto.buildCommand == "cargo build")
        #expect(moto.lintCommand == "cargo clippy")
    }

    @Test("creates MotoFile from detected Python project")
    func fromDetectedPython() {
        let detected = DetectedProject(
            language: .python,
            framework: .fastAPI,
            buildSystem: .poetry,
            name: "api-server"
        )

        let moto = MotoFile.from(detected: detected)

        #expect(moto.testCommand == "pytest")
        #expect(moto.lintCommand == "ruff check .")
    }

    @Test("creates MotoFile with architecture defaults")
    func architectureDefaults() {
        let detected = DetectedProject(
            language: .swift,
            buildSystem: .spm,
            name: "lib"
        )

        let moto = MotoFile.from(detected: detected)

        #expect(moto.architecture?.sourceRoot == "Sources")
        #expect(moto.architecture?.testRoot == "Tests")
    }

    // MARK: - Serialization

    @Test("serialize produces valid TOML-like output")
    func serialize() {
        let moto = MotoFile(
            name: "TestProject",
            language: "swift",
            framework: "swiftUI",
            buildSystem: "spm",
            testCommand: "swift test",
            buildCommand: "swift build",
            lintCommand: "swiftlint",
            architecture: MotoFile.Architecture(
                pattern: "MVVM",
                sourceRoot: "Sources",
                testRoot: "Tests",
                modules: ["Core", "UI"]
            ),
            agents: MotoFile.AgentSettings(
                maxConcurrency: 3,
                budgetDailyUSD: 10.0,
                preferredModel: "claude-opus"
            )
        )

        let output = moto.serialize()

        #expect(output.contains("[project]"))
        #expect(output.contains("name = \"TestProject\""))
        #expect(output.contains("language = \"swift\""))
        #expect(output.contains("framework = \"swiftUI\""))
        #expect(output.contains("[commands]"))
        #expect(output.contains("test = \"swift test\""))
        #expect(output.contains("build = \"swift build\""))
        #expect(output.contains("lint = \"swiftlint\""))
        #expect(output.contains("[architecture]"))
        #expect(output.contains("pattern = \"MVVM\""))
        #expect(output.contains("modules = [\"Core\", \"UI\"]"))
        #expect(output.contains("[agents]"))
        #expect(output.contains("max_concurrency = 3"))
        #expect(output.contains("budget_daily_usd = 10.00"))
        #expect(output.contains("preferred_model = \"claude-opus\""))
    }

    // MARK: - Parse

    @Test("parse round-trips with serialize")
    func parseRoundTrip() {
        let original = MotoFile(
            name: "RoundTrip",
            language: "rust",
            framework: "actixWeb",
            buildSystem: "cargo",
            testCommand: "cargo test",
            buildCommand: "cargo build",
            lintCommand: "cargo clippy",
            architecture: MotoFile.Architecture(
                pattern: "Hexagonal",
                sourceRoot: "src",
                testRoot: "tests",
                modules: ["domain", "infra"]
            ),
            agents: MotoFile.AgentSettings(
                maxConcurrency: 5,
                budgetDailyUSD: 25.0,
                preferredModel: "claude-sonnet"
            )
        )

        let serialized = original.serialize()
        let parsed = MotoFile.parse(from: serialized)

        #expect(parsed != nil)
        #expect(parsed?.name == "RoundTrip")
        #expect(parsed?.language == "rust")
        #expect(parsed?.framework == "actixWeb")
        #expect(parsed?.buildSystem == "cargo")
        #expect(parsed?.testCommand == "cargo test")
        #expect(parsed?.buildCommand == "cargo build")
        #expect(parsed?.lintCommand == "cargo clippy")
        #expect(parsed?.architecture?.pattern == "Hexagonal")
        #expect(parsed?.architecture?.sourceRoot == "src")
        #expect(parsed?.architecture?.testRoot == "tests")
        #expect(parsed?.architecture?.modules == ["domain", "infra"])
        #expect(parsed?.agents?.maxConcurrency == 5)
        #expect(parsed?.agents?.budgetDailyUSD == 25.0)
        #expect(parsed?.agents?.preferredModel == "claude-sonnet")
    }

    @Test("parse returns nil for invalid content")
    func parseInvalid() {
        let result = MotoFile.parse(from: "not a moto file")
        #expect(result == nil)
    }

    @Test("parse returns nil for empty content")
    func parseEmpty() {
        let result = MotoFile.parse(from: "")
        #expect(result == nil)
    }

    @Test("parse handles minimal content")
    func parseMinimal() {
        let content = """
        [project]
        name = "minimal"
        language = "go"
        """
        let result = MotoFile.parse(from: content)
        #expect(result?.name == "minimal")
        #expect(result?.language == "go")
        #expect(result?.framework == nil)
    }

    @Test("parse skips comments and blank lines")
    func parseWithComments() {
        let content = """
        # This is a comment
        [project]
        name = "commented"
        language = "python"

        # Another comment
        [commands]
        test = "pytest"
        """
        let result = MotoFile.parse(from: content)
        #expect(result?.name == "commented")
        #expect(result?.testCommand == "pytest")
    }
}
