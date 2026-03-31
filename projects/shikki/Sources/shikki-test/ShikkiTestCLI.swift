import ArgumentParser
import Foundation
import ShikkiTestRunner

@main
struct ShikkiTestCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shikki-test",
        abstract: "Run tests with architecture-scoped parallel execution",
        discussion: """
        Runs tests using Moto-scoped groups with per-test timeout,
        SQLite history, and regression detection.

        Examples:
          shikki test                    Run all scopes sequentially
          shikki test --parallel         Run all scopes in parallel
          shikki test --scope nats       Run only NATS scope
          shikki test --scope nats,tui   Run multiple scopes
          shikki test --scopes           List available scopes
          shikki test --history          Show recent test runs
          shikki test --regression       Find new failures
          shikki test --slow             Find tests > 2s
        """
    )

    @Flag(name: .long, help: "Run scopes in parallel")
    var parallel: Bool = false

    @Option(name: .long, help: "Run specific scope(s), comma-separated")
    var scope: String?

    @Flag(name: .long, help: "List available test scopes from Moto cache")
    var scopes: Bool = false

    @Flag(name: .long, help: "Stop on first failure")
    var failFast: Bool = false

    @Flag(name: .long, help: "Show log file path at end")
    var verbose: Bool = false

    @Flag(name: .long, help: "Stream logs in real-time (with --verbose)")
    var live: Bool = false

    @Flag(name: .long, help: "Show recent test run history")
    var history: Bool = false

    @Flag(name: .long, help: "Find tests that were green, now red")
    var regression: Bool = false

    @Flag(name: .long, help: "Find tests exceeding 2s threshold")
    var slow: Bool = false

    @Option(name: .long, help: "Number of history entries to show")
    var limit: Int = 10

    func run() async throws {
        let projectRoot = FileManager.default.currentDirectoryPath
        let historyPath = "\(projectRoot)/.shikki/test-history.sqlite"

        // Ensure .shikki directory exists
        try FileManager.default.createDirectory(
            atPath: "\(projectRoot)/.shikki",
            withIntermediateDirectories: true
        )

        // List scopes
        if scopes {
            let manifest = ScopeManifest.shikkiDefaults()
            let grouper = TestGrouper(manifest: manifest)
            print("\u{1B}[1mAvailable test scopes:\u{1B}[0m")
            for scope in manifest.scopes {
                print("  \(scope.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(scope.testFilePatterns.count) patterns")
            }
            return
        }

        // History
        if history {
            let store = try SQLiteStore(path: historyPath)
            let runs = try store.allRuns(limit: limit)
            if runs.isEmpty {
                print("\u{1B}[2mNo test history yet. Run shikki test to create the first entry.\u{1B}[0m")
                return
            }
            let reporter = TUIReporter()
            for run in runs {
                let marker = (run.failed ?? 0) > 0 ? "\u{F0622}" : "\u{F01DB}"
                let failed = run.failed ?? 0
                let total = run.totalTests ?? 0
                let passed = run.passed ?? 0
                let duration = run.durationMs.map { "\(Double($0) / 1000.0)s" } ?? "?"
                let failStr = failed > 0 ? " !!\(failed)" : ""
                print("\(marker) [\(run.startedAt)] \(run.gitHash.prefix(7)) \(run.branchName ?? "detached") [\(duration)] \(passed)/\(total)\(failStr)")
            }
            return
        }

        // Regression detection
        if regression {
            let store = try SQLiteStore(path: historyPath)
            let detector = RegressionDetector(store: store)
            let regressions = try detector.detectFromLatest()
            if regressions.isEmpty {
                print("\u{F01DB} No regressions detected.")
            } else {
                print("\u{F0622} \(regressions.count) regression(s) found:")
                for r in regressions {
                    print("  \(r.testName) — was passing, now \(r.currentStatus.rawValue)")
                }
            }
            return
        }

        // Slow tests
        if slow {
            let store = try SQLiteStore(path: historyPath)
            let results = try store.slowResults(thresholdMs: 2000)
            if results.isEmpty {
                print("\u{F01DB} No tests exceeding 2s threshold.")
            } else {
                print("\u{F0622} \(results.count) slow test(s):")
                for r in results {
                    let dur = r.durationMs.map { "\(Double($0) / 1000.0)s" } ?? "?"
                    print("  [\(dur)] \(r.testName)")
                }
            }
            return
        }

        // Run tests
        print("\u{1B}[1mShikkiTestRunner\u{1B}[0m")
        print("Running swift test\(parallel ? " --parallel" : "")...")

        // For now, delegate to swift test with event stream parsing
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["swift", "test"]
        if parallel { args.append("--parallel") }
        if let scope {
            let scopes = scope.split(separator: ",").map(String.init)
            let filter = scopes.map { "ShikkiKitTests.\($0)" }.joined(separator: "|")
            args += ["--filter", filter]
        }
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Stream output
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        print(output)

        // Record to SQLite
        let store = try SQLiteStore(path: historyPath)
        let gitHash = (try? shellOutput("git", "rev-parse", "--short", "HEAD")) ?? "unknown"
        let branch = (try? shellOutput("git", "branch", "--show-current")) ?? nil

        let runID = try store.recordRun(gitHash: gitHash, branch: branch)
        let passed = output.components(separatedBy: "passed").count - 1
        let failed = output.components(separatedBy: "failed").count - 1
        let total = passed + failed
        try store.finishRun(
            runID: runID,
            totalTests: Int64(total),
            passed: Int64(passed),
            failed: Int64(failed),
            skipped: 0,
            durationMs: nil
        )

        // Summary
        let marker = failed > 0 ? "\u{F0622}" : "\u{F01DB}"
        let failStr = failed > 0 ? " !!\(failed)" : ""
        print("\u{2501}".repeated(50))
        print("\(marker) \(gitHash) \(branch ?? "detached") \(passed)/\(total)\(failStr)")

        if verbose {
            print("\nFull log: \(historyPath)")
        }

        if failed > 0 {
            throw ExitCode(1)
        }
    }

    private func shellOutput(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = Array(args)
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private extension String {
    func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
