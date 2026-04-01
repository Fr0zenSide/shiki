import ArgumentParser
import Foundation
import ShikkiKit

struct MotoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "moto",
        abstract: "Moto DNS for Code -- pre-computed project architecture cache.",
        discussion: """
        Moto provides a standardized cache of project architecture \
        (protocols, types, dependencies, patterns, tests) so AI agents \
        can query a pre-computed snapshot instead of scraping raw source files.

        Subcommands:
          init    - Create a .moto dotfile and build the initial cache
          build   - Rebuild the architecture cache from source
          status  - Show cache status and staleness
          validate - Verify cache integrity (checksums)
          query   - Query the cache (types, protocols, patterns)
        """,
        subcommands: [
            MotoInitCommand.self,
            MotoBuildCommand.self,
            MotoStatusCommand.self,
            MotoValidateCommand.self,
            MotoQueryCommand.self,
        ],
        defaultSubcommand: MotoStatusCommand.self
    )
}

// MARK: - Init

struct MotoInitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize Moto: create .moto dotfile and build initial cache."
    )

    @Argument(help: "Path to the project directory (default: current directory).")
    var projectPath: String?

    @Option(name: .long, help: "Project name (default: directory name).")
    var name: String?

    @Option(name: .long, help: "Project language (default: swift).")
    var language: String = "swift"

    @Option(name: .long, help: "Cache output path (default: .moto-cache/).")
    var cachePath: String?

    func run() async throws {
        let resolvedPath = resolveProjectPath(projectPath)
        let projectName = name ?? URL(fileURLWithPath: resolvedPath).lastPathComponent
        let cacheOutput = cachePath ?? "\(resolvedPath)/.moto-cache"

        // Check if .moto already exists
        let motoFilePath = "\(resolvedPath)/.moto"
        if FileManager.default.fileExists(atPath: motoFilePath) {
            printDim("[moto] .moto file already exists at \(motoFilePath)")
            printDim("[moto] Use 'shikki moto build' to rebuild the cache.")
            return
        }

        printBold("[moto] Initializing Moto for \(projectName)...")

        // Analyze project
        let analyzer = ProjectAnalyzer()
        let startTime = CFAbsoluteTimeGetCurrent()
        let cache = try await analyzer.analyze(projectPath: resolvedPath)
        let analyzeTime = CFAbsoluteTimeGetCurrent() - startTime

        // Build moto cache
        let builder = MotoCacheBuilder()
        let manifest = try builder.build(
            from: cache,
            outputPath: cacheOutput,
            branch: detectBranch(at: resolvedPath) ?? "main"
        )

        let buildTime = CFAbsoluteTimeGetCurrent() - startTime

        // Create .moto dotfile
        let gitHash = (try? analyzer.currentGitHash(at: resolvedPath)) ?? "unknown"
        let dotfile = MotoDotfile(
            project: .init(
                name: projectName,
                description: "",
                language: language
            ),
            cache: .init(
                version: nil,
                commit: String(gitHash.prefix(8)),
                schema: "1",
                branches: [detectBranch(at: resolvedPath) ?? "main"],
                localPath: ".moto-cache/"
            ),
            attribution: .init(
                authors: detectGitAuthor(at: resolvedPath).map { [$0] } ?? [],
                created: ISO8601DateFormatter().string(from: Date())
            )
        )

        let parser = MotoDotfileParser()
        let tomlContent = parser.serialize(dotfile)
        try tomlContent.write(toFile: motoFilePath, atomically: true, encoding: .utf8)

        // Print summary
        let analyzeMs = Int(analyzeTime * 1000)
        let totalMs = Int(buildTime * 1000)

        printSuccess("[done] Moto initialized for \(projectName) in \(totalMs)ms")
        print("  Created: .moto (dotfile)")
        print("  Created: .moto-cache/ (architecture cache)")
        print("  Analyzed in: \(analyzeMs)ms")
        print("  Protocols: \(manifest.stats.protocols)")
        print("  Types: \(manifest.stats.types)")
        print("  Source files: \(manifest.stats.sourceFiles)")
        print("  Tests: \(manifest.stats.testCount)")
        print("  Cache tokens: ~\(manifest.stats.totalCacheTokens)")
        print("  Git: \(String(cache.gitHash.prefix(8)))")
        printDim("")
        printDim("  Add .moto-cache/ to .gitignore (or commit for offline use).")
        printDim("  Run 'shikki moto build' after code changes to refresh.")
    }
}

// MARK: - Build

struct MotoBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Rebuild the Moto architecture cache from source."
    )

    @Argument(help: "Path to the project directory (default: current directory).")
    var projectPath: String?

    @Flag(name: .long, help: "Force rebuild even if cache appears fresh.")
    var force: Bool = false

    func run() async throws {
        let resolvedPath = resolveProjectPath(projectPath)

        // Try to load .moto dotfile for config
        let parser = MotoDotfileParser()
        let motoFilePath = "\(resolvedPath)/.moto"
        let dotfile: MotoDotfile?
        if FileManager.default.fileExists(atPath: motoFilePath) {
            dotfile = try parser.parse(at: motoFilePath)
        } else {
            dotfile = nil
        }

        let cacheOutput = "\(resolvedPath)/\(dotfile?.cache.localPath ?? ".moto-cache/")"
        let projectName = dotfile?.project.name ?? URL(fileURLWithPath: resolvedPath).lastPathComponent

        // Check staleness (skip if --force)
        if !force {
            let manifestPath = "\(cacheOutput)/manifest.json"
            if FileManager.default.fileExists(atPath: manifestPath) {
                let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
                let manifest = try JSONDecoder().decode(MotoCacheManifest.self, from: data)
                let analyzer = ProjectAnalyzer()
                if let currentHash = try? analyzer.currentGitHash(at: resolvedPath),
                   manifest.gitCommit == currentHash {
                    printDim("[moto] Cache is up-to-date (git: \(String(currentHash.prefix(8))))")
                    return
                }
            }
        }

        printBold("[moto] Building cache for \(projectName)...")

        let analyzer = ProjectAnalyzer()
        let startTime = CFAbsoluteTimeGetCurrent()
        let cache = try await analyzer.analyze(projectPath: resolvedPath)

        let builder = MotoCacheBuilder()
        let manifest = try builder.build(
            from: cache,
            outputPath: cacheOutput,
            branch: detectBranch(at: resolvedPath) ?? "main"
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let ms = Int(elapsed * 1000)

        // Update .moto commit hash if dotfile exists
        if var df = dotfile {
            df.cache.commit = String(cache.gitHash.prefix(8))
            let content = parser.serialize(df)
            try content.write(toFile: motoFilePath, atomically: true, encoding: .utf8)
        }

        printSuccess("[done] Cache rebuilt in \(ms)ms")
        print("  Protocols: \(manifest.stats.protocols)")
        print("  Types: \(manifest.stats.types)")
        print("  Tests: \(manifest.stats.testCount)")
        print("  Tokens: ~\(manifest.stats.totalCacheTokens)")
        print("  Git: \(String(cache.gitHash.prefix(8)))")
    }
}

// MARK: - Status

struct MotoStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Moto cache status for the current project."
    )

    @Argument(help: "Path to the project directory (default: current directory).")
    var projectPath: String?

    func run() async throws {
        let resolvedPath = resolveProjectPath(projectPath)
        let motoFilePath = "\(resolvedPath)/.moto"

        guard FileManager.default.fileExists(atPath: motoFilePath) else {
            printDim("[moto] No .moto file found. Run 'shikki moto init' first.")
            throw ExitCode(1)
        }

        let parser = MotoDotfileParser()
        let dotfile = try parser.parse(at: motoFilePath)

        printBold("[moto] \(dotfile.project.name)")
        print("  Language: \(dotfile.project.language)")
        print("  Schema: v\(dotfile.cache.schema)")
        print("  Branches: \(dotfile.cache.branches.joined(separator: ", "))")

        let cacheOutput = "\(resolvedPath)/\(dotfile.cache.localPath)"
        let manifestPath = "\(cacheOutput)/manifest.json"

        if FileManager.default.fileExists(atPath: manifestPath) {
            let reader = MotoCacheReader(cachePath: cacheOutput)
            let manifest = try reader.loadManifest()

            print("  Cache commit: \(String(manifest.gitCommit.prefix(8)))")
            print("  Built at: \(manifest.builtAt)")
            print("  Protocols: \(manifest.stats.protocols)")
            print("  Types: \(manifest.stats.types)")
            print("  Source files: \(manifest.stats.sourceFiles)")
            print("  Tests: \(manifest.stats.testCount)")
            print("  Cache tokens: ~\(manifest.stats.totalCacheTokens)")

            // Check staleness
            let analyzer = ProjectAnalyzer()
            if let currentHash = try? analyzer.currentGitHash(at: resolvedPath) {
                if manifest.gitCommit == currentHash {
                    printSuccess("  Status: UP-TO-DATE")
                } else {
                    printWarning("  Status: STALE (current: \(String(currentHash.prefix(8))))")
                }
            }

            // Validate checksums
            let failures = try reader.validate()
            if failures.isEmpty {
                printSuccess("  Integrity: VALID")
            } else {
                printWarning("  Integrity: FAILED (\(failures.joined(separator: ", ")))")
            }
        } else {
            printWarning("  Cache: NOT BUILT (run 'shikki moto build')")
        }
    }
}

// MARK: - Validate

struct MotoValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Verify Moto cache integrity (checksums)."
    )

    @Argument(help: "Path to the project directory (default: current directory).")
    var projectPath: String?

    func run() async throws {
        let resolvedPath = resolveProjectPath(projectPath)
        let parser = MotoDotfileParser()
        let motoFilePath = "\(resolvedPath)/.moto"

        let cacheOutput: String
        if FileManager.default.fileExists(atPath: motoFilePath) {
            let dotfile = try parser.parse(at: motoFilePath)
            cacheOutput = "\(resolvedPath)/\(dotfile.cache.localPath)"
        } else {
            cacheOutput = "\(resolvedPath)/.moto-cache"
        }

        guard FileManager.default.fileExists(atPath: "\(cacheOutput)/manifest.json") else {
            printWarning("[moto] No cache found. Run 'shikki moto init' or 'shikki moto build'.")
            throw ExitCode(1)
        }

        let reader = MotoCacheReader(cachePath: cacheOutput)
        let failures = try reader.validate()

        if failures.isEmpty {
            printSuccess("[moto] Cache integrity: VALID -- all checksums match.")
        } else {
            printWarning("[moto] Cache integrity: FAILED")
            for file in failures {
                print("  Checksum mismatch: \(file)")
            }
            throw ExitCode(1)
        }
    }
}

// MARK: - Query

struct MotoQueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query the Moto cache (types, protocols, patterns)."
    )

    @Argument(help: "What to query: type, protocol, pattern, deps, api")
    var kind: String

    @Argument(help: "Name to look up (type name, protocol name, etc.).")
    var name: String?

    @Argument(help: "Path to the project directory (default: current directory).")
    var projectPath: String?

    func run() async throws {
        let resolvedPath = resolveProjectPath(projectPath)
        let parser = MotoDotfileParser()
        let motoFilePath = "\(resolvedPath)/.moto"

        let cacheOutput: String
        if FileManager.default.fileExists(atPath: motoFilePath) {
            let dotfile = try parser.parse(at: motoFilePath)
            cacheOutput = "\(resolvedPath)/\(dotfile.cache.localPath)"
        } else {
            cacheOutput = "\(resolvedPath)/.moto-cache"
        }

        let mcp = MotoMCPInterface(cachePath: cacheOutput)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        switch kind {
        case "type":
            guard let name else {
                print("Usage: shikki moto query type <TypeName>")
                throw ExitCode(1)
            }
            if let result = try mcp.getType(name: name) {
                let data = try encoder.encode(result)
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                printWarning("Type '\(name)' not found in cache.")
                throw ExitCode(1)
            }

        case "protocol":
            guard let name else {
                print("Usage: shikki moto query protocol <ProtocolName>")
                throw ExitCode(1)
            }
            if let result = try mcp.getProtocol(name: name) {
                let data = try encoder.encode(result)
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                printWarning("Protocol '\(name)' not found in cache.")
                throw ExitCode(1)
            }

        case "pattern":
            guard let name else {
                print("Usage: shikki moto query pattern <pattern_name>")
                throw ExitCode(1)
            }
            if let result = try mcp.getPattern(name: name) {
                let data = try encoder.encode(result)
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                printWarning("Pattern '\(name)' not found in cache.")
                throw ExitCode(1)
            }

        case "deps":
            let result = try mcp.getDependencyGraph(module: name)
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8) ?? "{}")

        case "api":
            let result = try mcp.getAPISurface(module: name)
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8) ?? "{}")

        default:
            print("Unknown query kind: \(kind)")
            print("Available: type, protocol, pattern, deps, api")
            throw ExitCode(1)
        }
    }
}

// MARK: - Helpers

private func resolveProjectPath(_ path: String?) -> String {
    guard let path else {
        return FileManager.default.currentDirectoryPath
    }
    let resolved = (path as NSString).standardizingPath
    if resolved.hasPrefix("/") {
        return resolved
    }
    return FileManager.default.currentDirectoryPath + "/" + resolved
}

private func detectBranch(at path: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
    process.currentDirectoryURL = URL(fileURLWithPath: path)
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func detectGitAuthor(at path: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["config", "user.name"]
    process.currentDirectoryURL = URL(fileURLWithPath: path)
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let nameData = pipe.fileHandleForReading.readDataToEndOfFile()
    let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let process2 = Process()
    let pipe2 = Pipe()
    process2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process2.arguments = ["config", "user.email"]
    process2.currentDirectoryURL = URL(fileURLWithPath: path)
    process2.standardOutput = pipe2
    process2.standardError = FileHandle.nullDevice
    try? process2.run()
    process2.waitUntilExit()
    guard process2.terminationStatus == 0 else { return name.isEmpty ? nil : name }
    let emailData = pipe2.fileHandleForReading.readDataToEndOfFile()
    let email = String(data: emailData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if name.isEmpty && email.isEmpty { return nil }
    if email.isEmpty { return name }
    return "\(name) <\(email)>"
}

// MARK: - Print Helpers

private func printBold(_ text: String) {
    print("\u{1B}[1m\(text)\u{1B}[0m")
}

private func printDim(_ text: String) {
    print("\u{1B}[2m\(text)\u{1B}[0m")
}

private func printSuccess(_ text: String) {
    print("\u{1B}[32m\(text)\u{1B}[0m")
}

private func printWarning(_ text: String) {
    print("\u{1B}[33m\(text)\u{1B}[0m")
}
