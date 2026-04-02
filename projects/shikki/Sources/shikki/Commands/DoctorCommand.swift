import ArgumentParser
import Foundation
import ShikkiKit

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose the Shiki environment and optionally auto-fix issues"
    )

    @Flag(name: .long, help: "Auto-fix issues where possible")
    var fix: Bool = false

    /// BR-EM-17: Emit shell aliases for all Shikkimoji emoji commands.
    /// Usage: eval "$(shi doctor --emit-aliases)"
    @Flag(name: .long, help: "Emit bash/zsh aliases for all Shikkimoji emoji commands")
    var emitAliases: Bool = false

    func run() async throws {
        if emitAliases {
            print(EmojiRegistry.generateShellAliases())
            return
        }

        print("\u{1B}[1m\u{1B}[36m🥕 Shikki Doctor\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 56))
        print()

        let doctor = ShikkiDoctor()
        let results = await doctor.runAll()

        // Collect fixable items for --fix mode
        var fixableResults: [DiagnosticResult] = []

        let maxName = results.map(\.name.count).max() ?? 10

        for result in results {
            let icon: String
            switch result.status {
            case .ok:      icon = "\u{1B}[32m\u{2713}\u{1B}[0m"
            case .warning: icon = "\u{1B}[33m\u{26A0}\u{1B}[0m"
            case .error:   icon = "\u{1B}[31m\u{2717}\u{1B}[0m"
            }

            let padded = result.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
            print("  \(icon) \(padded)  \(result.message)")

            if result.status != .ok, result.fixCommand != nil {
                fixableResults.append(result)
                if !fix {
                    print("    \u{1B}[2m\u{2192} fix: \(result.fixCommand!)\u{1B}[0m")
                }
            }
        }

        // --fix mode: auto-install missing optional tools via brew
        if fix && !fixableResults.isEmpty {
            print()
            print("\u{1B}[1mAuto-fixing \(fixableResults.count) issue(s)...\u{1B}[0m")
            let version = ShikkiCommand.configuration.version ?? "0.0.0"
            let service = SetupService(currentVersion: version)

            for result in fixableResults {
                guard let cmd = result.fixCommand else { continue }
                // Extract formula from "brew install <formula>"
                let parts = cmd.split(separator: " ")
                guard parts.count >= 3, parts[0] == "brew", parts[1] == "install" else {
                    print("  \u{1B}[33m\u{26A0}\u{1B}[0m \(result.name) — manual fix: \(cmd)")
                    continue
                }
                let formula = String(parts[2])
                print("  Installing \(result.name)... ", terminator: "")
                fflush(stdout)
                let installed = await service.installBrewPackage(formula)
                if installed {
                    print("\u{1B}[32m\u{2713}\u{1B}[0m")
                } else {
                    print("\u{1B}[31mfailed\u{1B}[0m")
                }
            }
        }

        print()
        let errors = results.filter { $0.status == .error }.count
        let warnings = results.filter { $0.status == .warning }.count

        if fix && !fixableResults.isEmpty {
            print("\u{1B}[32mFix pass complete.\u{1B}[0m Re-run \u{1B}[1mshi doctor\u{1B}[0m to verify.")
        } else if errors > 0 {
            print("\u{1B}[31m\(errors) error(s)\u{1B}[0m, \(warnings) warning(s)")
            if !fixableResults.isEmpty {
                print("Run: \u{1B}[1mshi doctor --fix\u{1B}[0m")
            }
        } else if warnings > 0 {
            print("\u{1B}[33m\(warnings) warning(s)\u{1B}[0m — all clear otherwise")
            if !fixableResults.isEmpty {
                print("Run: \u{1B}[1mshi doctor --fix\u{1B}[0m")
            }
        } else {
            print("\u{1B}[32mAll checks passed\u{1B}[0m")
        }
    }
}
