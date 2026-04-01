import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki fast` — the ultimate shortcut: quick + test + pre-pr + ship.
///
/// BR-CA-06: Emoji alias 🌪️ maps to `fast`.
/// BR-CA-08: Swift code is the authoritative definition.
///
/// Runs: quick flow -> full test suite -> pre-pr gates -> ship
/// in one pipeline with zero user interaction.
///
/// Usage:
///   shikki fast "add error handling to API"
///   shikki fast "fix off-by-one in pagination" --dry-run
///   shikki 🌪️ "hotfix typo"
struct FastCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fast",
        abstract: "Quick + ship in one command — the ultimate shortcut (emoji: \u{1F32A}\u{FE0F})"
    )

    @Argument(help: "Description of the change to make")
    var prompt: String

    @Flag(name: .long, help: "Preview all stages without executing")
    var dryRun: Bool = false

    @Option(name: .long, help: "Project path (default: current directory)")
    var project: String?

    @Option(name: .long, help: "Target branch for ship (default: develop)")
    var target: String = "develop"

    @Option(name: .long, help: "Comma-separated ship gates to skip (e.g. lint,changelog)")
    var skip: String?

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let projectPath = project ?? FileManager.default.currentDirectoryPath

        // Dry-run mode — show full plan
        if dryRun {
            printDryRun(projectPath: projectPath)
            return
        }

        let startTime = Date()

        // Build pipeline
        let agent = ClaudeAgentProvider()
        let fastPipeline = FastPipeline(agent: agent)

        FileHandle.standardError.write(Data(
            "\u{1B}[1m\u{1B}[36m\u{1F32A}\u{FE0F} Fast pipeline starting...\u{1B}[0m\n".utf8
        ))

        // Detect branch
        let branch = detectCurrentBranch()

        // Build ship context + gates
        let projectRoot = URL(fileURLWithPath: projectPath)
        let skipList = (skip ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        let shipContext: ShipContext
        if dryRun {
            shipContext = DryRunShipContext(
                branch: branch,
                target: target,
                projectRoot: projectRoot
            )
        } else {
            shipContext = RealShipContext(
                branch: branch,
                target: target,
                projectRoot: projectRoot
            )
        }

        let gates = buildGates(skipList: skipList)

        // Run fast pipeline
        let result: FastPipelineResult
        do {
            result = try await fastPipeline.run(
                prompt: prompt,
                projectPath: projectPath,
                dryRun: dryRun,
                shipContext: shipContext,
                shipGates: gates
            )
        } catch {
            FileHandle.standardError.write(Data(
                "\u{1B}[31mFast pipeline failed:\u{1B}[0m \(error)\n".utf8
            ))
            throw ExitCode.failure
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        // Print summary
        printSummary(result, totalDuration: totalDuration)

        if !result.success {
            if let stage = result.failedStage {
                FileHandle.standardError.write(Data(
                    "\u{1B}[31mPipeline aborted at stage: \(stage.displayName)\u{1B}[0m\n".utf8
                ))
            }
            throw ExitCode.failure
        }
    }

    // MARK: - Helpers

    private func detectCurrentBranch() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--show-current"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        } catch {
            return "unknown"
        }
    }

    private func buildGates(skipList: [String]) -> [any ShipGate] {
        var gates: [any ShipGate] = []

        // Fast pipeline uses a subset of ship gates:
        // Test + Lint + Build (skip branch-clean, changelog, version, tag, push)
        if !skipList.contains("test") {
            gates.append(TestGate())
        }
        if !skipList.contains("lint") {
            gates.append(LintGate())
        }
        if !skipList.contains("build") {
            gates.append(BuildGate())
        }

        return gates
    }

    // MARK: - Output

    private func printDryRun(projectPath: String) {
        FileHandle.standardOutput.write(Data(
            "\u{1B}[1m\u{1F32A}\u{FE0F} Fast Pipeline — Dry Run\u{1B}[0m\n".utf8
        ))
        FileHandle.standardOutput.write(Data("  Prompt: \"\(prompt)\"\n".utf8))
        FileHandle.standardOutput.write(Data("  Project: \(projectPath)\n".utf8))
        FileHandle.standardOutput.write(Data("  Target: \(target)\n".utf8))
        if let skip {
            FileHandle.standardOutput.write(Data("  Skip: \(skip)\n".utf8))
        }
        FileHandle.standardOutput.write(Data("\n  Pipeline stages:\n".utf8))
        for stage in FastPipelineStage.allCases {
            FileHandle.standardOutput.write(Data(
                "    \(stage.rawValue + 1). \(stage.displayName)\n".utf8
            ))
        }
        FileHandle.standardOutput.write(Data(
            "\n  \u{1B}[2mNo changes will be made in dry-run mode.\u{1B}[0m\n".utf8
        ))
    }

    private func printSummary(_ result: FastPipelineResult, totalDuration: TimeInterval) {
        let icon = result.success ? "\u{2705}" : "\u{274C}"
        let timeStr = String(format: "%.1fs", totalDuration)

        FileHandle.standardOutput.write(Data(
            "\n\u{1B}[1m\(icon) Fast Pipeline \(result.success ? "Complete" : "Failed")\u{1B}[0m\n".utf8
        ))
        FileHandle.standardOutput.write(Data(
            "- Quick: \(result.quickResult.summary)\n".utf8
        ))
        FileHandle.standardOutput.write(Data(
            "- Files: \(result.quickResult.filesChanged) changed\n".utf8
        ))
        FileHandle.standardOutput.write(Data(
            "- Tests: \(result.testsAllPassed ? "all passed" : "FAILED")\n".utf8
        ))
        if result.gatesTotal > 0 {
            FileHandle.standardOutput.write(Data(
                "- Gates: \(result.gatesPassed)/\(result.gatesTotal) passed\n".utf8
            ))
        }
        FileHandle.standardOutput.write(Data(
            "- Time: \(timeStr)\n".utf8
        ))

        if let reason = result.failureReason {
            FileHandle.standardOutput.write(Data(
                "- Failure: \(reason)\n".utf8
            ))
        }
    }
}
