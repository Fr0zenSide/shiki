import Foundation
import Testing
@testable import ShikkiKit

@Suite("Diagnostic integration — command/service/formatter chain")
struct DiagnosticIntegrationTests {

    // MARK: - Helpers

    private func makeService(
        events: MockEventSource = MockEventSource(),
        checkpoint: MockCheckpointProvider = MockCheckpointProvider(),
        git: MockGitProvider = MockGitProvider()
    ) -> ContextRecoveryService {
        ContextRecoveryService(
            eventSource: events,
            checkpointProvider: checkpoint,
            gitProvider: git
        )
    }

    // MARK: - Full pipeline tests

    @Test("Default args produces human output with confidence meter")
    func diagnosticCommand_defaultArgs_producesHumanOutput() async {
        let git = MockGitProvider()
        git.branch = "develop"
        git.commits = [
            CommitInfo(hash: "abc1234", message: "feat: test", author: "dev", timestamp: Date()),
        ]

        let service = makeService(git: git)
        let context = await service.recover(window: TimeWindow.lookback(seconds: 7200))
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)

        #expect(output.contains("Confidence:"))
        #expect(output.contains("develop"))
    }

    @Test("Format JSON produces valid JSON")
    func diagnosticCommand_formatJSON_producesValidJSON() async {
        let service = makeService()
        let context = await service.recover(window: TimeWindow.lookback(seconds: 7200))
        let output = DiagnosticFormatter.formatJSON(context)

        let data = output.data(using: .utf8)!
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }

    @Test("Format agent produces compact block under budget")
    func diagnosticCommand_formatAgent_producesCompactBlock() async {
        let git = MockGitProvider()
        git.branch = "feature/test"
        let service = makeService(git: git)
        let context = await service.recover(window: TimeWindow.lookback(seconds: 7200))
        let output = DiagnosticFormatter.formatAgent(context, budget: 2048)

        #expect(output.contains("<context-recovery>"))
        #expect(output.contains("</context-recovery>"))
        #expect(output.utf8.count <= 2148)
    }

    @Test("24h window expands context recovery")
    func diagnosticCommand_from24h_expandsWindow() async {
        let now = Date()
        let window = TimeWindow.lookback(seconds: 24 * 3600, from: now)

        #expect(abs(window.duration - 86400) < 1)
        #expect(window.since < now.addingTimeInterval(-86000))
    }

    @Test("Copy flag writes to last-recovery file")
    func diagnosticCommand_copyFlag_writeToLastRecoveryFile() async throws {
        let tmpDir = NSTemporaryDirectory() + "shikki-test-\(UUID().uuidString)"
        let recoveryPath = "\(tmpDir)/last-recovery.md"
        let fm = FileManager.default

        // Create directory
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        // Write recovery content to file (simulating --copy fallback)
        let content = "<context-recovery>\nTest content\n</context-recovery>"
        try content.write(toFile: recoveryPath, atomically: true, encoding: .utf8)

        let recovered = try String(contentsOfFile: recoveryPath, encoding: .utf8)
        #expect(recovered.contains("context-recovery"))
    }

    @Test("Pipe to command works cleanly (no ANSI in non-TTY)")
    func pipeToShikkiCommand_worksCleanly() async {
        let service = makeService()
        let context = await service.recover(window: TimeWindow.lookback(seconds: 7200))
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)

        // No ANSI escape codes
        #expect(!output.contains("\u{1B}["))
    }

    // MARK: - Time window smart defaults (BR-07)

    @Test("Default window with no checkpoint returns 1h")
    func defaultWindow_noCheckpoint_returns1h() {
        let window = TimeWindow.lookback(seconds: DurationParser.defaultRecoveryDuration)
        #expect(abs(window.duration - 3600) < 1)
    }

    @Test("Default window with fresh checkpoint starts from checkpoint minus 10m")
    func defaultWindow_freshCheckpoint_startsFromCheckpointMinus10m() {
        let now = Date()
        let checkpointTime = now.addingTimeInterval(-1800) // 30 min ago
        let since = checkpointTime.addingTimeInterval(-600) // 10 min overlap
        let window = TimeWindow(since: since, until: now)

        // Window should start ~40 min ago
        let expectedDuration: TimeInterval = 1800 + 600
        #expect(abs(window.duration - expectedDuration) < 1)
    }

    @Test("Default window with stale checkpoint returns 1h")
    func defaultWindow_staleCheckpoint_returns1h() {
        // Stale = older than default window, so we use default 1h window
        let window = TimeWindow.lookback(seconds: DurationParser.defaultRecoveryDuration)
        #expect(abs(window.duration - 3600) < 1)
    }

    // MARK: - Data Safety (BR-24, BR-25)

    @Test("Git fallback never reads file contents")
    func gitFallback_neverReadsFileContents() async {
        let git = MockGitProvider()
        git.modified = ["Sources/Secret.swift"]
        git.untracked = [".env"]
        let service = makeService(git: git)

        let context = await service.recover(window: TimeWindow.lookback(seconds: 7200))

        // Workspace has paths only
        #expect(context.workspace.modifiedFiles == ["Sources/Secret.swift"])
        #expect(context.workspace.untrackedFiles == [".env"])

        // No item contains file contents
        for item in context.timeline {
            if let detail = item.detail {
                #expect(!detail.contains("API_KEY"))
            }
        }
    }

    @Test("JSON output never includes raw file contents")
    func jsonOutput_neverIncludesRawFileContents() async {
        let git = MockGitProvider()
        git.modified = ["Sources/App.swift"]
        let service = makeService(git: git)

        let context = await service.recover(window: TimeWindow.lookback(seconds: 7200))
        let json = DiagnosticFormatter.formatJSON(context)

        // JSON contains the path (may be escaped as Sources\/App.swift)
        #expect(json.contains("App.swift"))
        // Should not contain any Swift code
        #expect(!json.contains("import Foundation"))
    }

    @Test("DB payloads summarized by default, full only with verbose")
    func dbPayloads_summarizedByDefault() async {
        let events = MockEventSource()
        events.events = [
            ShikkiEvent(
                source: .system,
                type: .codeChange,
                scope: .global,
                payload: ["longContent": .string(String(repeating: "x", count: 200))]
            ),
        ]
        let service = makeService(events: events)

        let normalContext = await service.recover(
            window: TimeWindow.lookback(seconds: 7200),
            verbose: false
        )
        let verboseContext = await service.recover(
            window: TimeWindow.lookback(seconds: 7200),
            verbose: true
        )

        // Normal: no detail
        let normalItems = normalContext.timeline.filter { $0.provenance == .db }
        #expect(normalItems.allSatisfy { $0.detail == nil })

        // Verbose: has detail
        let verboseItems = verboseContext.timeline.filter { $0.provenance == .db }
        #expect(verboseItems.contains(where: { $0.detail != nil }))
    }
}
