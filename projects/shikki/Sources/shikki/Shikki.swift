import ArgumentParser
import Foundation

@main
struct ShikkiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shikki",
        abstract: "Shikki -- ship + testflight CLI",
        version: "0.3.0-pre",
        subcommands: [
            ShipCommand.self,
        ]
    )
}
