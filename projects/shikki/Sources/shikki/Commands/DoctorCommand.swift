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
    /// Usage: eval "$(shikki doctor --emit-aliases)"
    @Flag(name: .long, help: "Emit bash/zsh aliases for all Shikkimoji emoji commands")
    var emitAliases: Bool = false

    /// Also accessible as `shikki doctor --context`.
    @Flag(name: .long, help: "Run context recovery diagnostic (alias for `shikki diagnostic`)")
    var context: Bool = false

    func run() async throws {
        if emitAliases {
            print(EmojiRegistry.generateShellAliases())
            return
        }

        if context {
            let diagnostic = try DiagnosticCommand.parse([])
            try await diagnostic.run()
            return
        }

        print("\u{1B}[1m\u{1B}[36m🥕 Shikki Doctor\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 56))
        print()

        let doctor = ShikkiDoctor()
        let results = await doctor.runAll()

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

            if fix, let cmd = result.fixCommand, result.status != .ok {
                print("    \u{1B}[2m\u{2192} fix: \(cmd)\u{1B}[0m")
            }
        }

        print()
        let errors = results.filter { $0.status == .error }.count
        let warnings = results.filter { $0.status == .warning }.count

        if errors > 0 {
            print("\u{1B}[31m\(errors) error(s)\u{1B}[0m, \(warnings) warning(s)")
        } else if warnings > 0 {
            print("\u{1B}[33m\(warnings) warning(s)\u{1B}[0m — all clear otherwise")
        } else {
            print("\u{1B}[32mAll checks passed\u{1B}[0m")
        }
    }
}
