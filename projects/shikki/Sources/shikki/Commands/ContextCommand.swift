import ArgumentParser
import Foundation
import ShikkiKit

struct ContextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Query project architecture cache."
    )

    @Argument(help: "Project ID.")
    var projectId: String

    @Flag(name: .long, help: "Show all protocols.")
    var protocols: Bool = false

    @Option(name: .long, help: "Show details for a specific type.")
    var type: String?

    @Option(name: .customLong("proto"), help: "Show details for a specific protocol.")
    var proto: String?

    @Flag(name: .long, help: "Show detected patterns.")
    var patterns: Bool = false

    @Flag(name: .long, help: "Show compact agent summary.")
    var summary: Bool = false

    func run() async throws {
        let store = CacheStore()

        guard let cache = try store.load(projectId: projectId) else {
            print("\u{1B}[31m[error]\u{1B}[0m No cache found for '\(projectId)'. Run: shikki ingest <path>")
            throw ExitCode.failure
        }

        if let protoName = proto {
            print(ContextBuilder.protocolContext(protoName, cache: cache))
            return
        }

        if let typeName = type {
            print(ContextBuilder.typeContext(typeName, cache: cache))
            return
        }

        if protocols {
            printProtocols(cache)
            return
        }

        if patterns {
            printPatterns(cache)
            return
        }

        if summary {
            print(ContextBuilder.agentSummary(cache))
            return
        }

        // Default: full overview
        print(ContextBuilder.projectOverview(cache))
    }

    // MARK: - Renderers

    private func printProtocols(_ cache: ArchitectureCache) {
        if cache.protocols.isEmpty {
            print("No protocols found.")
            return
        }

        print("# Protocols in \(projectId) (\(cache.protocols.count))")
        print("")

        for proto in cache.protocols.sorted(by: { $0.name < $1.name }) {
            let conformers = proto.conformers.isEmpty ? "none" : proto.conformers.joined(separator: ", ")
            print("  \(proto.name) [\(proto.module)]")
            print("    Methods: \(proto.methods.count)")
            print("    Conformers: \(conformers)")
            print("    File: \(proto.file)")
            print("")
        }
    }

    private func printPatterns(_ cache: ArchitectureCache) {
        if cache.patterns.isEmpty {
            print("No patterns detected.")
            return
        }

        print("# Patterns in \(projectId) (\(cache.patterns.count))")
        print("")

        for pattern in cache.patterns {
            print("  ## \(pattern.name)")
            print("  \(pattern.description)")
            print("  Files: \(pattern.files.joined(separator: ", "))")
            if !pattern.example.isEmpty {
                print("  ```")
                for line in pattern.example.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("  \(line)")
                }
                print("  ```")
            }
            print("")
        }
    }
}
