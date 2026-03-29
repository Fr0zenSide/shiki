import Foundation
import Testing
@testable import ShikkiKit

@Suite("Dashboard Renderer")
struct DashboardRendererTests {

    // MARK: - Helpers

    private func makeState(
        agents: [DashboardState.AgentStatus] = [],
        budget: DashboardState.BudgetDisplay = .init(spent: 0, limit: 0),
        events: [DashboardState.DashboardEvent] = [],
        showEvents: Bool = true
    ) -> DashboardState {
        DashboardState(
            version: "0.2.0",
            branch: "develop",
            sessionStatus: "active",
            sessionUptime: 8100, // 2h 15m
            agents: agents,
            budget: budget,
            testCount: 134,
            openPRs: 2,
            events: events,
            showEvents: showEvents
        )
    }

    // MARK: - Agent Progress Bar

    @Test("renders agent progress bar correctly")
    func agentProgressBar() {
        let agents = [
            DashboardState.AgentStatus(name: "Maya", status: .active, progress: 65, detail: "Building Wave 3"),
        ]
        let state = makeState(agents: agents)
        let output = DashboardRenderer.render(state: state, width: 60)

        #expect(output.contains("Maya"))
        #expect(output.contains("65%"))
        #expect(output.contains("Building Wave 3"))
        // Progress bar should contain filled blocks
        #expect(output.contains("\u{2588}"))
    }

    // MARK: - Budget Gauge

    @Test("renders budget gauge with percentage")
    func budgetGauge() {
        let budget = DashboardState.BudgetDisplay(spent: 12.40, limit: 31.00)
        let state = makeState(budget: budget)
        let output = DashboardRenderer.render(state: state, width: 60)

        #expect(output.contains("40%"))
        #expect(output.contains("$12.40"))
        #expect(output.contains("$31.00"))
        #expect(output.contains("\u{2588}")) // filled blocks in bar
    }

    // MARK: - Events Ordering

    @Test("events display in reverse chronological order")
    func eventsOrder() {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 12, minute: 10))!
        let events = [
            DashboardState.DashboardEvent(
                timestamp: cal.date(byAdding: .minute, value: 20, to: base)!,
                type: "task_completed", agent: "WabiSabi", detail: "30/30 tests"
            ),
            DashboardState.DashboardEvent(
                timestamp: cal.date(byAdding: .minute, value: 18, to: base)!,
                type: "pr_created", agent: "WabiSabi", detail: "PR #24"
            ),
            DashboardState.DashboardEvent(
                timestamp: cal.date(byAdding: .minute, value: 5, to: base)!,
                type: "test_passed", agent: "Maya", detail: "15/23"
            ),
            DashboardState.DashboardEvent(
                timestamp: base,
                type: "task_started", agent: "Maya", detail: "Wave 3"
            ),
        ]
        let state = makeState(events: events)
        let output = DashboardRenderer.render(state: state, width: 60)

        // All events should be present
        #expect(output.contains("task_completed"))
        #expect(output.contains("pr_created"))
        #expect(output.contains("test_passed"))
        #expect(output.contains("task_started"))

        // First event should appear before last in rendered output
        let completedPos = output.range(of: "task_completed")!.lowerBound
        let startedPos = output.range(of: "task_started")!.lowerBound
        #expect(completedPos < startedPos)
    }

    // MARK: - Completed Agent

    @Test("completed agent shows checkmark")
    func completedAgentCheckmark() {
        let agents = [
            DashboardState.AgentStatus(name: "WabiSabi", status: .completed, progress: 100, detail: "PR #24 created"),
        ]
        let state = makeState(agents: agents)
        let output = DashboardRenderer.render(state: state, width: 60)

        #expect(output.contains("\u{2713}")) // ✓ checkmark
        #expect(output.contains("WabiSabi"))
        #expect(output.contains("100%"))
        #expect(output.contains("PR #24 created"))
    }

    // MARK: - Queued Agent

    @Test("queued agent shows dim circle")
    func queuedAgentDimCircle() {
        let agents = [
            DashboardState.AgentStatus(name: "ShikiCore", status: .queued, progress: 0, detail: "Waiting for Maya"),
        ]
        let state = makeState(agents: agents)
        let output = DashboardRenderer.render(state: state, width: 60)

        #expect(output.contains("\u{25CB}")) // ○ empty circle
        #expect(output.contains("ShikiCore"))
        #expect(output.contains("QUEUED"))
        #expect(output.contains("Waiting for Maya"))
    }

    // MARK: - Failed Agent

    @Test("failed agent shows X icon")
    func failedAgentIcon() {
        let agents = [
            DashboardState.AgentStatus(name: "Brainy", status: .failed, progress: 30, detail: "Build error"),
        ]
        let state = makeState(agents: agents)
        let output = DashboardRenderer.render(state: state, width: 60)

        #expect(output.contains("\u{2717}")) // ✗
        #expect(output.contains("Brainy"))
        #expect(output.contains("FAILED"))
        #expect(output.contains("Build error"))
    }

    // MARK: - Box Drawing

    @Test("dashboard has proper box drawing borders")
    func boxDrawingBorders() {
        let state = makeState()
        let output = DashboardRenderer.render(state: state, width: 60)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)

        // First line should start with top-left corner
        #expect(lines.first?.hasPrefix("\u{250C}") == true)
        // Last line should start with bottom-left corner
        #expect(lines.last?.hasPrefix("\u{2514}") == true)
        // Should contain vertical bars
        #expect(output.contains("\u{2502}"))
    }

    // MARK: - Uptime Formatting

    @Test("uptime formats hours and minutes")
    func uptimeFormatting() {
        let state = DashboardState(sessionUptime: 8100) // 2h 15m
        let output = DashboardRenderer.render(state: state, width: 60)
        #expect(output.contains("2h 15m"))
    }

    // MARK: - Budget Display Model

    @Test("budget percent calculation")
    func budgetPercent() {
        let budget = DashboardState.BudgetDisplay(spent: 12.40, limit: 31.00)
        #expect(budget.percent == 40)

        let zeroBudget = DashboardState.BudgetDisplay(spent: 5.0, limit: 0)
        #expect(zeroBudget.percent == 0)

        let fullBudget = DashboardState.BudgetDisplay(spent: 31.0, limit: 31.0)
        #expect(fullBudget.percent == 100)
    }

    // MARK: - Progress Bar

    @Test("progress bar renders correct fill ratio")
    func progressBarFill() {
        let bar0 = progressBar(percent: 0, width: 10)
        #expect(bar0 == String(repeating: "\u{2591}", count: 10))

        let bar100 = progressBar(percent: 100, width: 10)
        #expect(bar100 == String(repeating: "\u{2588}", count: 10))

        let bar50 = progressBar(percent: 50, width: 10)
        #expect(bar50.filter { $0 == "\u{2588}" }.count == 5)
        #expect(bar50.filter { $0 == "\u{2591}" }.count == 5)
    }

    // MARK: - Empty State

    @Test("empty agents shows no active sessions message")
    func emptyAgents() {
        let state = makeState(agents: [])
        let output = DashboardRenderer.render(state: state, width: 60)
        #expect(output.contains("No active sessions"))
    }

    // MARK: - Events Toggle

    @Test("events hidden when showEvents is false")
    func eventsToggle() {
        let events = [
            DashboardState.DashboardEvent(timestamp: Date(), type: "test_passed", agent: "Maya", detail: "15/23"),
        ]
        let stateWithEvents = makeState(events: events, showEvents: true)
        let outputWith = DashboardRenderer.render(state: stateWithEvents, width: 60)
        #expect(outputWith.contains("Events"))
        #expect(outputWith.contains("test_passed"))

        let stateWithout = makeState(events: events, showEvents: false)
        let outputWithout = DashboardRenderer.render(state: stateWithout, width: 60)
        #expect(!outputWithout.contains("test_passed"))
    }

    // MARK: - Multi-Agent Layout

    @Test("multiple agents render in sequence")
    func multipleAgents() {
        let agents = [
            DashboardState.AgentStatus(name: "Maya", status: .active, progress: 65, detail: "Building Wave 3"),
            DashboardState.AgentStatus(name: "WabiSabi", status: .completed, progress: 100, detail: "PR #24 created"),
            DashboardState.AgentStatus(name: "ShikiCore", status: .queued, progress: 0, detail: "Waiting for Maya"),
        ]
        let state = makeState(agents: agents)
        let output = DashboardRenderer.render(state: state, width: 60)

        // All three agents present
        #expect(output.contains("Maya"))
        #expect(output.contains("WabiSabi"))
        #expect(output.contains("ShikiCore"))

        // Correct icons for each
        #expect(output.contains("\u{25CF}")) // ● active
        #expect(output.contains("\u{2713}")) // ✓ completed
        #expect(output.contains("\u{25CB}")) // ○ queued
    }
}
