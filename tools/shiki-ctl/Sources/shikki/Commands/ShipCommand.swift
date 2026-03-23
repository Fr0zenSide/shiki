import ArgumentParser
import Foundation
import ShikiCtlKit

struct ShipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ship",
        abstract: "Pipeline-of-gates release command — quality-gated, event-driven shipping"
    )

    @Flag(name: .long, help: "Run all gates without side effects")
    var dryRun: Bool = false

    @Option(name: .long, help: "Target branch (default: develop)")
    var target: String = "develop"

    @Option(name: .long, help: "Mandatory reason for this release")
    var why: String?

    @Option(name: .long, help: "Manual version override (semver)")
    var version: String?

    @Flag(name: .long, help: "Squash commits into one before PR")
    var squash: Bool = false

    @Flag(name: .long, help: "Show ship history from log")
    var history: Bool = false

    @Option(name: .long, help: "Epic branch name — scopes changelog to epic range instead of last tag")
    var epic: String?

    func run() async throws {
        // Handle --history mode
        if history {
            let log = ShipLog()
            let contents = try log.readHistory()
            FileHandle.standardOutput.write(Data(contents.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Validate mandatory --why
        guard let reason = why else {
            FileHandle.standardError.write(Data("Error: --why is required. Every release needs a reason.\n".utf8))
            FileHandle.standardError.write(Data("Usage: shiki ship --why \"reason for release\" [--dry-run] [--target develop]\n".utf8))
            throw ExitCode.failure
        }

        // Detect project root and current branch
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let branchProcess = Process()
        branchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        branchProcess.arguments = ["branch", "--show-current"]
        let branchPipe = Pipe()
        branchProcess.standardOutput = branchPipe
        try branchProcess.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let branchData = branchPipe.fileHandleForReading.readDataToEndOfFile()
        branchProcess.waitUntilExit()
        let branch = String(data: branchData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        // Build context — when --epic is set, target the epic branch for PR creation
        let resolvedTarget = epic ?? target
        let context: ShipContext
        if dryRun {
            context = DryRunShipContext(
                branch: branch,
                target: resolvedTarget,
                projectRoot: projectRoot
            )
        } else {
            context = RealShipContext(
                branch: branch,
                target: resolvedTarget,
                projectRoot: projectRoot
            )
        }

        // Build gate pipeline
        let gates: [any ShipGate] = [
            CleanBranchGate(),
            TestGate(),
            CoverageGate(),
            RiskGate(),
            ChangelogGate(scopeBranch: epic),
            VersionBumpGate(versionOverride: version),
            CommitGate(squash: squash),
            PRGate(),
        ]

        // Render preflight
        ShipRenderer.renderPreflight(
            branch: branch,
            target: target,
            currentVersion: "detecting...",
            nextVersion: version ?? "auto",
            commitCount: 0,
            isDryRun: dryRun,
            why: reason
        )

        if !dryRun {
            FileHandle.standardError.write(Data("  Press Enter to proceed (Ctrl-C to abort)...".utf8))
            _ = readLine()
        }

        // Run pipeline
        let startTime = Date()
        let service = ShipService()

        // Run with progress rendering
        let result = try await service.run(gates: gates, context: context)

        // Render gate results
        for (index, gr) in result.gateResults.enumerated() {
            ShipRenderer.renderGateProgress(
                gate: gr.gate,
                index: index,
                total: gates.count,
                elapsed: nil,
                result: gr.result
            )
        }

        let totalElapsed = Date().timeIntervalSince(startTime)
        ShipRenderer.renderSummary(result: result, elapsed: totalElapsed)

        // Append to ship log
        if result.success {
            let log = ShipLog()
            let gateSummary = "\(result.gateResults.count)/\(gates.count) passed" +
                (result.warnings.isEmpty ? "" : ", \(result.warnings.count) warnings")
            try? log.append(ShipLogEntry(
                date: Date(),
                version: version ?? "auto",
                project: projectRoot.lastPathComponent,
                branch: branch,
                why: reason,
                riskScore: 0,
                gateSummary: gateSummary
            ))
        }

        // Send ntfy notification (best effort, using Process to avoid shell injection)
        let ntfyPayload: String
        if result.success {
            ntfyPayload = "Ship complete: \(branch) -> \(target)"
        } else if let gate = result.failedGate, let reason = result.failureReason {
            ntfyPayload = "Ship failed at \(gate): \(reason)"
        } else {
            ntfyPayload = ""
        }

        if !ntfyPayload.isEmpty {
            let ntfyProcess = Process()
            ntfyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            ntfyProcess.arguments = ["curl", "-s", "--max-time", "10", "-d", ntfyPayload, "https://ntfy.sh/shiki-notify"]
            ntfyProcess.standardOutput = FileHandle.nullDevice
            ntfyProcess.standardError = FileHandle.nullDevice
            try? ntfyProcess.run()
            ntfyProcess.waitUntilExit()
        }

        if !result.success {
            throw ExitCode.failure
        }
    }
}
