import ArgumentParser
import Foundation
import ShikkiKit

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a project for Shikki — detect language, generate .moto, scaffold settings"
    )

    @Option(name: .long, help: "Project directory (defaults to current)")
    var path: String?

    @Flag(name: .long, help: "Overwrite existing .moto file")
    var force: Bool = false

    @Option(name: .long, help: "Apply a built-in template (ios, spm, web, api, cli)")
    var template: String?

    @Flag(name: .long, help: "Detect only — show what would be generated without writing files")
    var dryRun: Bool = false

    func run() async throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let wizard = ProjectInitWizard()

        if dryRun {
            runDryRun(wizard: wizard, at: projectPath)
            return
        }

        do {
            let result = try wizard.initialize(
                at: projectPath,
                force: force,
                template: template
            )
            renderSuccess(result: result, at: projectPath)
        } catch InitError.motoFileAlreadyExists {
            print(styled("Error:", .red, .bold) + " .moto file already exists.")
            print(styled("  Use --force to overwrite, or edit the existing file.", .dim))
            throw ExitCode(1)
        } catch InitError.directoryNotFound(let dir) {
            print(styled("Error:", .red, .bold) + " directory not found: \(dir)")
            throw ExitCode(1)
        } catch InitError.writeError(let msg) {
            print(styled("Error:", .red, .bold) + " \(msg)")
            throw ExitCode(1)
        }
    }

    // MARK: - Dry Run

    private func runDryRun(wizard: ProjectInitWizard, at path: String) {
        let detected = wizard.detect(at: path)
        let moto = wizard.generateMotoFile(for: detected)

        print(styled("Shikki Init — Dry Run", .bold, .cyan))
        print(String(repeating: "\u{2500}", count: 40))
        print()

        print(styled("Detected:", .bold))
        print("  Language:     \(detected.language.displayName)")
        if let fw = detected.framework {
            print("  Framework:    \(fw.displayName)")
        }
        if let bs = detected.buildSystem {
            print("  Build System: \(bs.displayName)")
        }
        print("  Git:          \(detected.hasGit ? styled("yes", .green) : styled("no", .yellow))")
        print("  Tests:        \(detected.hasTests ? styled("yes", .green) : styled("no", .yellow))")
        print()

        print(styled("Would generate .moto:", .bold))
        print(styled("---", .dim))
        for line in moto.serialize().split(separator: "\n") {
            print(styled("  \(line)", .dim))
        }
        print(styled("---", .dim))
        print()
        print(styled("Run without --dry-run to create files.", .dim))
    }

    // MARK: - Success Output

    private func renderSuccess(result: InitResult, at path: String) {
        print()
        print(styled("Shikki initialized!", .bold, .green))
        print()

        print(styled("Project:", .bold) + " \(result.motoFile.name)")
        print(styled("Language:", .bold) + " \(result.motoFile.language)")
        if let fw = result.motoFile.framework {
            print(styled("Framework:", .bold) + " \(fw)")
        }
        print()

        if !result.filesCreated.isEmpty {
            print(styled("Files created:", .bold))
            for file in result.filesCreated {
                print("  \(styled("+", .green)) \(file)")
            }
            print()
        }

        if !result.warnings.isEmpty {
            print(styled("Warnings:", .yellow, .bold))
            for warning in result.warnings {
                print("  \(styled("!", .yellow)) \(warning)")
            }
            print()
        }

        print(styled("Next steps:", .bold))
        print("  1. Review the generated .moto file")
        print("  2. Run \(styled("shikki doctor", .cyan)) to check your environment")
        print("  3. Run \(styled("shikki", .cyan)) to start orchestrating")
        print()
    }
}
