// ProgressRendererTests.swift — Tests for live progress rendering
// Part of ShikkiTestRunnerTests

import Foundation
import Testing
@testable import ShikkiTestRunner

@Suite("ProgressRenderer")
struct ProgressRendererTests {

    @Test("scope started shows running state with diamond marker")
    func scopeStartedShowsRunning() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        await renderer.scopeStarted(TestFixtures.natsScope)

        let snapshot = await renderer.currentSnapshot()
        #expect(snapshot.contains(ProgressRenderer.runningMarker))
        #expect(snapshot.contains("nats"))
        #expect(snapshot.contains("running..."))
    }

    @Test("scope progress updates completed count")
    func scopeProgressUpdates() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        await renderer.scopeStarted(TestFixtures.natsScope)
        await renderer.scopeProgress(TestFixtures.natsScope, completed: 12, total: 57)

        let snapshot = await renderer.currentSnapshot()
        #expect(snapshot.contains("[12/57]"))
    }

    @Test("scope finished collapses to completed line with filled diamond")
    func scopeFinishedCollapsesToOneLiner() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        let result = TestFixtures.allPassedScopeResult(
            scope: TestFixtures.natsScope,
            count: 57
        )

        await renderer.scopeStarted(TestFixtures.natsScope)
        await renderer.scopeFinished(TestFixtures.natsScope, result: result)

        let snapshot = await renderer.currentSnapshot()
        #expect(snapshot.contains(ProgressRenderer.completedMarker))
        #expect(snapshot.contains("57/57"))
        #expect(!snapshot.contains("running..."))
    }

    @Test("multiple scopes render in order")
    func multipleScopesInOrder() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        await renderer.scopeStarted(TestFixtures.natsScope)
        await renderer.scopeStarted(TestFixtures.flywheelScope)
        await renderer.scopeStarted(TestFixtures.tuiScope)

        let snapshot = await renderer.currentSnapshot()
        let lines = snapshot.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(String(lines[0]).contains("nats"))
        #expect(String(lines[1]).contains("flywheel"))
        #expect(String(lines[2]).contains("tui"))
    }

    @Test("mixed running and completed scopes render correctly")
    func mixedRunningAndCompleted() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        let flywheelResult = TestFixtures.allPassedScopeResult(
            scope: TestFixtures.flywheelScope,
            count: 80
        )

        await renderer.scopeStarted(TestFixtures.natsScope)
        await renderer.scopeStarted(TestFixtures.flywheelScope)
        await renderer.scopeFinished(TestFixtures.flywheelScope, result: flywheelResult)
        await renderer.scopeProgress(TestFixtures.natsScope, completed: 31, total: 57)

        let snapshot = await renderer.currentSnapshot()

        // NATS should still show running
        #expect(snapshot.contains("running..."))
        #expect(snapshot.contains("[31/57]"))
        // Flywheel should show completed
        #expect(snapshot.contains("80/80"))
    }

    @Test("reset clears all state")
    func resetClearsState() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        await renderer.scopeStarted(TestFixtures.natsScope)
        await renderer.reset()

        let snapshot = await renderer.currentSnapshot()
        #expect(snapshot.isEmpty)
    }

    @Test("terminal output receives ANSI cursor control codes")
    func terminalOutputReceivesANSI() async {
        let output = MockTerminalOutput()
        let renderer = ProgressRenderer(output: output)

        // First render — no cursor up
        await renderer.scopeStarted(TestFixtures.natsScope)

        // Second render — should contain cursor up escape
        await renderer.scopeProgress(TestFixtures.natsScope, completed: 5, total: 57)

        let allOutput = await output.allOutput()
        // After first render, subsequent renders should move cursor up
        // ESC[1A = move up 1 line
        #expect(allOutput.contains("\u{1B}["))
    }
}
