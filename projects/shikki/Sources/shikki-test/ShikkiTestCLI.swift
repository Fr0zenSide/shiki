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
          shikki-test                    Run all scopes sequentially
          shikki-test --parallel         Run all scopes in parallel
          shikki-test --scope nats       Run only NATS scope
          shikki-test --scope nats,tui   Run multiple scopes
          shikki-test --scopes           List available scopes
          shikki-test --history          Show recent test runs
          shikki-test --regression       Find new failures
          shikki-test --slow             Find tests > 2s
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

    // MARK: - Paths

    private var projectRoot: String { FileManager.default.currentDirectoryPath }

    private var shikkiDir: String { "\(projectRoot)/.shikki" }

    private var historyPath: String { "\(shikkiDir)/test-history.sqlite" }

    private var logDir: String { "\(shikkiDir)/test-logs" }

    // MARK: - Run

    func run() async throws {
        try FileManager.default.createDirectory(atPath: shikkiDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        if scopes { return listScopes() }
        if history { return try showHistory() }
        if regression { return try showRegressions() }
        if slow { return try showSlowTests() }

        try await runTests()
    }

    // MARK: - List Scopes

    private func listScopes() {
        let manifest = ScopeManifest.shikkiDefaults
        print("\u{1B}[1mAvailable test scopes (from Moto manifest):\u{1B}[0m")
        for scope in manifest.scopes {
            let patterns = scope.testFilePatterns.count
            let types = scope.typePatterns.count
            print("  \(scope.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(patterns) file patterns  \(types) types")
        }
    }

    // MARK: - History

    private func showHistory() throws {
        let store = try SQLiteStore(path: historyPath)
        let runs = try store.allRuns(limit: limit)
        if runs.isEmpty {
            print("\u{1B}[2mNo test history yet. Run shikki-test to create the first entry.\u{1B}[0m")
            return
        }
        let reporter = TUIReporter()
        for run in runs {
            let passed = run.passed ?? 0
            let failed = run.failed ?? 0
            let total = run.totalTests ?? 0
            let duration = run.durationMs.map { reporter.formatDuration(Int($0)) } ?? "?"
            let marker = failed > 0 ? StatusMarker.hasFailures.symbol : StatusMarker.allPassed.symbol
            let failStr = failed > 0 ? " !!\(failed)" : ""
            print("\(marker) [\(run.startedAt)] \(run.gitHash.prefix(7)) \(run.branchName ?? "detached") [\(duration)] \(passed)/\(total)\(failStr)")
        }
    }

    // MARK: - Regression

    private func showRegressions() throws {
        let store = try SQLiteStore(path: historyPath)
        let detector = RegressionDetector(store: store)
        let regressions = try detector.detectLatestRegressions()
        if regressions.isEmpty {
            print("\(StatusMarker.allPassed.symbol) No regressions detected.")
        } else {
            print("\(StatusMarker.hasFailures.symbol) \(regressions.count) regression(s) found:")
            for r in regressions {
                print("  \(r.testName) \u{1B}[2m(\(r.suiteName ?? "unknown suite"))\u{1B}[0m")
            }
        }
    }

    // MARK: - Slow Tests

    private func showSlowTests() throws {
        let store = try SQLiteStore(path: historyPath)
        let detector = RegressionDetector(store: store)
        let slowTests = try detector.slowTests(thresholdMs: 2000)
        if slowTests.isEmpty {
            print("\(StatusMarker.allPassed.symbol) No tests exceeding 2s threshold.")
        } else {
            print("\(StatusMarker.hasFailures.symbol) \(slowTests.count) slow test(s):")
            let reporter = TUIReporter()
            for t in slowTests {
                print("  [\(reporter.formatDuration(Int(t.durationMs)))] \(t.testName)")
            }
        }
    }

    // MARK: - Run Tests

    private func runTests() async throws {
        let manifest = ScopeManifest.shikkiDefaults
        let store = try SQLiteStore(path: historyPath)
        let reporter = TUIReporter(verbosity: verbose ? (live ? .live : .verbose) : .clean)
        let parser = EventStreamParser()
        let timeoutManager = TimeoutManager(defaultLimit: .seconds(5)) { testID in
            print("  \u{1B}[33m[TIMEOUT]\u{1B}[0m \(testID) exceeded 5s limit")
        }

        // Git info
        let gitProvider = SystemGitInfoProvider()
        let gitHash = (try? await gitProvider.currentGitHash()) ?? "unknown"
        let branch = try? await gitProvider.currentBranch()

        // Record run
        let runID = try store.recordRun(gitHash: gitHash, branch: branch)
        let startTime = Date()

        // Build scope filter
        var args = ["swift", "test"]
        if parallel { args.append("--parallel") }
        if let scope {
            let names = scope.split(separator: ",").map(String.init)
            let filters = names.compactMap { name -> String? in
                manifest.scope(named: name)?.testFilePatterns.first
            }
            if !filters.isEmpty {
                args += ["--filter", filters.joined(separator: "|")]
            }
        }

        print("\u{1B}[1mShikkiTestRunner\u{1B}[0m")
        print("Running: \(args.joined(separator: " "))")
        print("")

        // Launch process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        // Parse event stream with timeout tracking
        var passed = 0
        var failed = 0
        var skipped = 0
        var timedOut = 0
        var logLines: [String] = []

        // Read with global timeout (kill process if tests hang)
        let globalTimeoutSeconds: Int = 120
        let handle = stdoutPipe.fileHandleForReading

        // Run with timeout — kill process if it exceeds limit
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(globalTimeoutSeconds))
            if process.isRunning {
                print("\n\u{1B}[33m[GLOBAL TIMEOUT]\u{1B}[0m Test suite exceeded \(globalTimeoutSeconds)s — killing process")
                process.terminate()
            }
        }

        let data = handle.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutTask.cancel()
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)

        // Parse output
        let output = String(data: data, encoding: .utf8) ?? ""
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

        // Parse Swift Testing text output
        // Lines like: '􁁛  Test "name" passed after 0.001 seconds.'
        //             '􀢄  Test "name" failed after 0.001 seconds with 1 issue.'
        //             '􁁛  Suite "name" passed after 0.243 seconds.'
        //             '􀢄  Suite "name" failed after 0.243 seconds with 1 issue.'
        // We count individual Test lines only (not Suite summaries)
        for line in output.split(separator: "\n") {
            let l = String(line)
            logLines.append(l)
            // Only count Test lines, not Suite lines
            guard l.contains("Test \"") else { continue }
            if l.contains("passed after") {
                passed += 1
            } else if l.contains("failed after") || l.contains("with") && l.contains("issue") {
                failed += 1
            }
        }
        // Also check stderr for test output (some Swift versions write there)
        for line in stderrOutput.split(separator: "\n") {
            let l = String(line)
            logLines.append(l)
            guard l.contains("Test \"") else { continue }
            if l.contains("passed after") {
                passed += 1
            } else if l.contains("failed after") {
                failed += 1
            }
        }

        var total = passed + failed + skipped + timedOut

        // Save to SQLite
        try store.finishRun(
            runID: runID,
            totalTests: Int64(total),
            passed: Int64(passed),
            failed: Int64(failed),
            skipped: Int64(skipped),
            durationMs: Int64(duration)
        )

        // Save log file
        let logPath = "\(logDir)/\(gitHash.prefix(7))-\(runID.prefix(8)).log"
        let fullLog = output + "\n---STDERR---\n" + stderrOutput
        try fullLog.write(toFile: logPath, atomically: true, encoding: .utf8)

        // Render summary
        let durationStr = reporter.formatDuration(duration)
        let marker = failed > 0 ? StatusMarker.hasFailures.symbol : (total == 0 ? StatusMarker.partialRun.symbol : StatusMarker.allPassed.symbol)
        let failStr = failed > 0 ? " !!\(failed)" : ""
        let skipStr = skipped > 0 ? " ??\(skipped)" : ""

        // If test runner captured a summary line, use its counts
        for line in logLines {
            // "Test run with 177 tests in 16 suites passed after 0.230 seconds."
            if line.contains("Test run with") {
                if let match = line.range(of: #"(\d+) tests?"#, options: .regularExpression) {
                    let numStr = line[match].filter { $0.isNumber }
                    if let n = Int(numStr), n > total {
                        // Swift Testing summary is more accurate than our line counting
                        let realTotal = n
                        passed = realTotal - failed - skipped
                    }
                }
            }
        }
        total = passed + failed + skipped + timedOut

        // Show failures inline (if not verbose --live which already showed everything)
        if failed > 0 && !live {
            for line in logLines {
                if line.contains("failed after") || line.contains("Expectation failed") {
                    print("  \(line)")
                }
            }
        }

        print(String(repeating: "\u{2501}", count: 55))
        print("\(marker) \(gitHash.prefix(7)) \(branch ?? "detached") [\(durationStr)] \(passed)/\(total)\(failStr)\(skipStr)")

        if verbose {
            print("\nFull log: \(logPath)")
        }

        if failed > 0 {
            throw ExitCode(1)
        }
    }
}
