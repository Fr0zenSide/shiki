import ArgumentParser
import Foundation
import ShikkiKit

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Bootstrap the Shikki environment (install deps, create dirs, verify)"
    )

    @Flag(name: .long, help: "Force re-run all setup steps")
    var force: Bool = false

    func run() async throws {
        let version = ShikkiCommand.configuration.version ?? "0.0.0"

        if force {
            // Delete existing state to force re-run
            let path = SetupState.defaultPath
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        let service = SetupService(currentVersion: version)
        let success = await service.bootstrap()

        if success {
            try SetupState.markComplete(version: version)
            print()
            print("\u{1B}[32mSetup complete.\u{1B}[0m Run \u{1B}[1mshi doctor\u{1B}[0m to verify.")
        } else {
            print()
            print("\u{1B}[31mSetup incomplete.\u{1B}[0m Fix the errors above and re-run \u{1B}[1mshi setup\u{1B}[0m.")
            throw ExitCode(1)
        }
    }
}
