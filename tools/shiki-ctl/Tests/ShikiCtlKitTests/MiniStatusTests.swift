import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Mini status output")
struct MiniStatusTests {

    // MARK: - Test Helpers

    private func makeRegistry(sessions: [(String, SessionState)] = []) async -> SessionRegistry {
        let discoverer = MockMiniDiscoverer()
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-mini-test-\(UUID().uuidString)")
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        for (name, state) in sessions {
            await registry.registerManual(
                windowName: name, paneId: "%\(name.hashValue)", pid: pid_t(abs(name.hashValue % 99999)),
                state: state
            )
        }
        return registry
    }

    // MARK: - Mini Format Tests

    @Test("Mini format with healthy agents")
    func miniFormatHealthy() async {
        let registry = await makeRegistry(sessions: [
            ("maya:task1", .working),
            ("wabi:task2", .working),
        ])
        let sessions = await registry.allSessions
        let output = MiniStatusFormatter.formatCompact(sessions: sessions, pendingQuestions: 0, spentUsd: 0, budgetUsd: 0)
        #expect(output.contains("●2"))
        #expect(output.contains("Q:0"))
        #expect(output.contains("$0/$0"))
    }

    @Test("Mini format with mixed states")
    func miniFormatMixed() async {
        let registry = await makeRegistry(sessions: [
            ("maya:task1", .working),
            ("wabi:task2", .awaitingApproval),
            ("flsh:task3", .done),
        ])
        let sessions = await registry.allSessions
        let output = MiniStatusFormatter.formatCompact(sessions: sessions, pendingQuestions: 1, spentUsd: 0, budgetUsd: 0)
        #expect(output.contains("●1"))
        #expect(output.contains("▲1"))
        #expect(output.contains("○1"))
        #expect(output.contains("Q:1"))
    }

    @Test("Mini format when backend unreachable")
    func miniFormatUnreachable() {
        let output = MiniStatusFormatter.formatUnreachable()
        #expect(output == "? Q:? $?")
    }

    @Test("Expanded format shows company names")
    func expandedFormat() async {
        let registry = await makeRegistry(sessions: [
            ("maya:task1", .working),
            ("wabi:task2", .awaitingApproval),
        ])
        let sessions = await registry.allSessions
        let output = MiniStatusFormatter.formatExpanded(sessions: sessions, pendingQuestions: 1, spentUsd: 0, budgetUsd: 0)
        #expect(output.contains("maya:●"))
        #expect(output.contains("wabi:▲"))
        #expect(output.contains("Q:1"))
    }

    @Test("Toggle persists state to file")
    func togglePersistsState() throws {
        let tmpDir = NSTemporaryDirectory() + "shiki-tmux-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        let statePath = "\(tmpDir)/tmux-state.json"

        // Default should be compact
        let initial = TmuxStateManager(statePath: statePath)
        #expect(initial.isExpanded == false)

        // Toggle to expanded
        initial.toggle()
        #expect(initial.isExpanded == true)

        // Reload from disk — should still be expanded
        let reloaded = TmuxStateManager(statePath: statePath)
        #expect(reloaded.isExpanded == true)

        // Toggle back
        reloaded.toggle()
        #expect(reloaded.isExpanded == false)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    @Test("Menu renders command grid")
    func menuRendersGrid() {
        let output = MenuRenderer.renderGrid()
        #expect(output.contains("SHIKI"))
        #expect(output.contains("status"))
        #expect(output.contains("decide"))
        #expect(output.contains("attach"))
        #expect(output.contains("Esc"))
    }

    @Test("Mini output has no trailing newline")
    func miniNoTrailingNewline() async {
        let registry = await makeRegistry(sessions: [
            ("maya:task1", .working),
        ])
        let sessions = await registry.allSessions
        let output = MiniStatusFormatter.formatCompact(sessions: sessions, pendingQuestions: 0, spentUsd: 0, budgetUsd: 0)
        #expect(!output.hasSuffix("\n"))
    }

    @Test("Empty sessions shows all zeros")
    func emptySessionsAllZeros() {
        let output = MiniStatusFormatter.formatCompact(sessions: [], pendingQuestions: 0, spentUsd: 0, budgetUsd: 0)
        #expect(output.contains("Q:0"))
        #expect(output.contains("$0/$0"))
    }
}

// MARK: - Test Double

private final class MockMiniDiscoverer: SessionDiscoverer, @unchecked Sendable {
    func discover() async -> [DiscoveredSession] { [] }
}
