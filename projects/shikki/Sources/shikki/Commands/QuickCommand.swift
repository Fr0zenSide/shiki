import ArgumentParser
import Foundation
import ShikkiKit

/// `shi quick` — small change, single agent, no spec ceremony.
///
/// BR-CA-04: Every user-facing skill gets a Swift entry point.
/// Maps the /quick-flow skill into a compiled command with typed args,
/// scope detection, and gate enforcement.
///
/// Usage:
///   shi quick "fix the typo in README"
///   shi quick "rename var to camelCase" --yolo
///   shi quick "add test for edge case" --dry-run
struct QuickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quick",
        abstract: "Quick change — small fix, single agent, no spec ceremony"
    )

    @Argument(help: "Description of the change to make")
    var prompt: String

    @Flag(name: .long, help: "Skip confirmation, auto-commit with conventional message")
    var yolo: Bool = false

    @Flag(name: .long, help: "Show plan without executing")
    var dryRun: Bool = false

    @Option(name: .long, help: "Project path (default: current directory)")
    var project: String?

    @Option(name: .long, help: "Backend URL for pipeline checkpointing")
    var url: String = "http://localhost:3900"

    func run() async throws {
        let projectPath = project ?? FileManager.default.currentDirectoryPath

        // Step 0: Scope detection — warn if change looks too big
        let scopeDetector = ScopeDetector()
        let scope = scopeDetector.evaluate(prompt)

        if scope.score >= 2 {
            FileHandle.standardError.write(Data(
                "\u{1B}[33mScope warning:\u{1B}[0m This looks bigger than a quick fix (score: \(scope.score)/7).\n".utf8
            ))
            for signal in scope.signals {
                FileHandle.standardError.write(Data(
                    "  - \(signal.rawValue)\n".utf8
                ))
            }
            FileHandle.standardError.write(Data(
                "\u{1B}[2mConsider `shi spec` instead for structured changes.\u{1B}[0m\n".utf8
            ))
            if !yolo {
                throw ExitCode.failure
            }
        }

        // Dry-run mode
        if dryRun {
            printDryRun(projectPath: projectPath, scopeScore: scope.score)
            return
        }

        // Build pipeline
        let agent = ClaudeAgentProvider()
        let pipeline = QuickPipeline(agent: agent)

        FileHandle.standardError.write(Data(
            "\u{1B}[2mQuick pipeline starting...\u{1B}[0m\n".utf8
        ))

        // Run quick flow (steps 1-3)
        let result: QuickPipelineResult
        do {
            result = try await pipeline.run(
                prompt: prompt,
                yolo: yolo,
                projectPath: projectPath
            )
        } catch let error as QuickPipelineError {
            FileHandle.standardError.write(Data(
                "\u{1B}[31mQuick flow failed:\u{1B}[0m \(errorMessage(error))\n".utf8
            ))
            throw ExitCode.failure
        }

        // Step 4: Ship — offer options (or auto-commit in yolo mode)
        if yolo {
            FileHandle.standardError.write(Data(
                "\u{1B}[2m--yolo: auto-committing...\u{1B}[0m\n".utf8
            ))
        }

        // Print summary
        printSummary(result)
    }

    // MARK: - Output

    private func printDryRun(projectPath: String, scopeScore: Int) {
        FileHandle.standardOutput.write(Data("\u{1B}[1mQuick Flow — Dry Run\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data("  Prompt: \"\(prompt)\"\n".utf8))
        FileHandle.standardOutput.write(Data("  Project: \(projectPath)\n".utf8))
        FileHandle.standardOutput.write(Data("  Scope score: \(scopeScore)/7\n".utf8))
        FileHandle.standardOutput.write(Data("  Mode: \(yolo ? "--yolo (auto-commit)" : "interactive")\n".utf8))
        FileHandle.standardOutput.write(Data(
            "  Pipeline: scope-check → spec → implement (TDD) → self-review → ship\n".utf8
        ))
    }

    private func printSummary(_ result: QuickPipelineResult) {
        FileHandle.standardOutput.write(Data("\n\u{1B}[1m## Quick Flow Complete\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data("- Spec: \(result.summary)\n".utf8))
        FileHandle.standardOutput.write(Data("- Files: \(result.filesChanged) changed\n".utf8))
        FileHandle.standardOutput.write(Data(
            "- Tests: \(result.testsPassing) passing (\(result.newTests) new)\n".utf8
        ))
        let commitStr = result.commitHash ?? "unstaged"
        FileHandle.standardOutput.write(Data("- Commit: \(commitStr)\n".utf8))
        let timeStr = String(format: "%.1fs", result.duration)
        FileHandle.standardOutput.write(Data("- Time: \(timeStr)\n".utf8))
    }

    private func errorMessage(_ error: QuickPipelineError) -> String {
        switch error {
        case .emptyPrompt:
            return "Empty prompt. Usage: shi quick \"description of change\""
        case .scopeTooLarge(let score, let signals):
            return "Scope too large (score \(score)): \(signals.joined(separator: ", "))"
        case .agentFailed(let msg):
            return "Agent error: \(msg)"
        case .testsFailed(let msg):
            return "Tests failed: \(msg)"
        case .escalationRequired(let attempts):
            return "Escalation required after \(attempts) fix attempts. Use `shi spec` instead."
        }
    }
}
