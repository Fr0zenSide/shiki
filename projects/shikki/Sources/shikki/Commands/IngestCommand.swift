import ArgumentParser
import Foundation
import ShikkiKit

struct IngestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Analyze project architecture and build cache for fast agent context."
    )

    @Argument(help: "Path to the project directory.")
    var projectPath: String

    @Option(name: .long, help: "Project ID (default: directory name).")
    var id: String?

    @Flag(name: .long, help: "Force rebuild even if cache exists.")
    var rebuild: Bool = false

    func run() async throws {
        let resolvedPath = (projectPath as NSString).standardizingPath
        let absolutePath: String
        if resolvedPath.hasPrefix("/") {
            absolutePath = resolvedPath
        } else {
            absolutePath = FileManager.default.currentDirectoryPath + "/" + resolvedPath
        }

        let projectId = id ?? URL(fileURLWithPath: absolutePath).lastPathComponent
        let store = CacheStore()

        // Check if cache exists and is fresh
        if !rebuild {
            let analyzer = ProjectAnalyzer()
            if let currentHash = try? analyzer.currentGitHash(at: absolutePath),
               !store.isStale(projectId: projectId, currentGitHash: currentHash) {
                print("\u{1B}[2m[cache] \(projectId) is up-to-date (git: \(String(currentHash.prefix(8))))\u{1B}[0m")
                return
            }
        }

        print("\u{1B}[1m[ingest]\u{1B}[0m Analyzing \(projectId) at \(absolutePath)...")

        let analyzer = ProjectAnalyzer()
        let startTime = CFAbsoluteTimeGetCurrent()
        var cache = try await analyzer.analyze(projectPath: absolutePath)

        // Override project ID if specified
        if let customId = id {
            cache = ArchitectureCache(
                projectId: customId,
                projectPath: cache.projectPath,
                gitHash: cache.gitHash,
                builtAt: cache.builtAt,
                packageInfo: cache.packageInfo,
                protocols: cache.protocols,
                types: cache.types,
                dependencyGraph: cache.dependencyGraph,
                patterns: cache.patterns,
                testInfo: cache.testInfo
            )
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        try store.save(cache)

        // Print summary
        let ms = Int(elapsed * 1000)
        print("\u{1B}[32m[done]\u{1B}[0m Cached \(projectId) in \(ms)ms")
        print("  Targets: \(cache.packageInfo.targets.count)")
        print("  Protocols: \(cache.protocols.count)")
        print("  Types: \(cache.types.count)")
        print("  Patterns: \(cache.patterns.count)")
        print("  Tests: \(cache.testInfo.testCount) (\(cache.testInfo.framework))")
        print("  Git: \(String(cache.gitHash.prefix(8)))")
    }
}
