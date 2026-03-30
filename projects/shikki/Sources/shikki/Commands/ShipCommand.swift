import ArgumentParser
import Foundation
import ShikkiKit

struct ShipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ship",
        abstract: "Pipeline-of-gates release command -- quality-gated, event-driven shipping"
    )

    @Flag(name: .long, help: "Run all gates without side effects")
    var dryRun: Bool = false

    @Option(name: .long, help: "Target branch (default: develop)")
    var target: String = "develop"

    @Option(name: .long, help: "Mandatory reason for this release")
    var why: String?

    @Option(name: .long, help: "Manual version override (semver)")
    var version: String?

    @Flag(name: .long, help: "Show ship history from log")
    var history: Bool = false

    @Flag(name: .long, help: "Ship to TestFlight after quality gates")
    var testflight: Bool = false

    @Option(name: .long, help: "App slug from apps.toml (required when multiple apps configured)")
    var app: String?

    @Option(name: .long, help: "Comma-separated list of gates to skip (e.g. lint,changelog)")
    var skip: String?

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
            FileHandle.standardError.write(
                Data("Error: --why is required. Every release needs a reason.\n".utf8)
            )
            FileHandle.standardError.write(
                Data("Usage: shikki ship --why \"reason\" [--dry-run] [--testflight]\n".utf8)
            )
            throw ExitCode.failure
        }

        // Parse skip list
        let skipList = (skip ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        // Detect project root and current branch
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let branchProcess = Process()
        branchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        branchProcess.arguments = ["branch", "--show-current"]
        let branchPipe = Pipe()
        branchProcess.standardOutput = branchPipe
        try branchProcess.run()
        let branchData = branchPipe.fileHandleForReading.readDataToEndOfFile()
        branchProcess.waitUntilExit()
        let branch = String(data: branchData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        // Build context
        let context: ShipContext
        if dryRun {
            context = DryRunShipContext(
                branch: branch,
                target: target,
                projectRoot: projectRoot
            )
        } else {
            context = RealShipContext(
                branch: branch,
                target: target,
                projectRoot: projectRoot
            )
        }

        // Build gate pipeline -- core 8 gates
        let changelogStore = ChangelogStore()
        var gates: [any ShipGate] = []

        if !skipList.contains("cleanbranch") {
            gates.append(CleanBranchGate())
        }
        if !skipList.contains("test") {
            gates.append(TestGate())
        }
        if !skipList.contains("lint") {
            gates.append(LintGate())
        }
        if !skipList.contains("build") {
            gates.append(BuildGate())
        }
        if !skipList.contains("changelog") {
            gates.append(ChangelogGate(changelogStore: changelogStore))
        }
        if !skipList.contains("versionbump") {
            gates.append(VersionBumpGate(versionOverride: version))
        }
        if !skipList.contains("tag") {
            gates.append(TagGate(versionOverride: version))
        }
        if !skipList.contains("push") {
            gates.append(PushGate())
        }

        // TestFlight gates (9-12) -- appended when --testflight
        let tfContext = TestFlightContext()
        if testflight {
            gates.append(AppRegistryGate(appSlug: app, tfContext: tfContext))
            gates.append(BuildNumberGate(tfContext: tfContext))
            gates.append(ArchiveGate(
                tfContext: tfContext,
                version: version ?? "auto"
            ))
            gates.append(UploadGate(tfContext: tfContext))
        }

        let totalGates = gates.count

        // Render preflight
        if testflight {
            // TestFlight extended preflight will be rendered after AppRegistryGate loads config
            // For now show standard preflight
            ShipRenderer.renderPreflight(
                branch: branch,
                target: target,
                currentVersion: "detecting...",
                nextVersion: version ?? "auto",
                commitCount: 0,
                gateCount: totalGates,
                isDryRun: dryRun,
                why: reason,
                skipList: skipList
            )
        } else {
            ShipRenderer.renderPreflight(
                branch: branch,
                target: target,
                currentVersion: "detecting...",
                nextVersion: version ?? "auto",
                commitCount: 0,
                gateCount: totalGates,
                isDryRun: dryRun,
                why: reason,
                skipList: skipList
            )
        }

        if !dryRun {
            FileHandle.standardError.write(Data("  Press Enter to proceed (Ctrl-C to abort)...".utf8))
            _ = readLine()
        }

        // Run pipeline
        let startTime = Date()
        let service = ShipService()

        let result = try await service.run(gates: gates, context: context)

        // Render gate results
        for (index, gr) in result.gateResults.enumerated() {
            ShipRenderer.renderGateProgress(
                gate: gr.gate,
                index: index,
                total: totalGates,
                elapsed: nil,
                result: gr.result
            )
        }

        let totalElapsed = Date().timeIntervalSince(startTime)
        ShipRenderer.renderSummary(result: result, elapsed: totalElapsed)

        // Append to ship log
        if result.success {
            let log = ShipLog()
            let gateSummary = "\(result.gateResults.count)/\(totalGates) passed" +
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

        // Send ntfy notification (best effort, using Process)
        let ntfyPayload: String
        if result.success {
            if testflight {
                let buildNum = await tfContext.buildNumber
                ntfyPayload = "TestFlight: \(app ?? "app") build \(buildNum) shipped"
            } else {
                ntfyPayload = "Ship complete: \(branch) -> \(target)"
            }
        } else if let gate = result.failedGate, let failReason = result.failureReason {
            ntfyPayload = "Ship failed at \(gate): \(failReason.prefix(100))"
        } else {
            ntfyPayload = ""
        }

        if !ntfyPayload.isEmpty {
            let ntfyProcess = Process()
            ntfyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            ntfyProcess.arguments = [
                "curl", "-s", "--max-time", "10",
                "-d", ntfyPayload,
                "https://ntfy.sh/shiki-notify",
            ]
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
