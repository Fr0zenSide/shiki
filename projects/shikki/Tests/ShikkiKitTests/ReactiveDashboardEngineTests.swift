import Foundation
import Testing
@testable import ShikkiKit

@Suite("ReactiveDashboardEngine")
struct ReactiveDashboardEngineTests {

    // MARK: - Helpers

    private func makeEngine(bus: InProcessEventBus? = nil) -> (ReactiveDashboardEngine, InProcessEventBus) {
        let eventBus = bus ?? InProcessEventBus()
        let engine = ReactiveDashboardEngine(eventBus: eventBus)
        return (engine, eventBus)
    }

    // MARK: - Initial State

    @Test("initial state has defaults")
    func initialState() async {
        let (engine, _) = makeEngine()
        let state = await engine.currentState()

        #expect(state.version == "0.2.0")
        #expect(state.agents.isEmpty)
        #expect(state.events.isEmpty)
        #expect(state.budget.spent == 0)
        #expect(state.budget.limit == 0)
    }

    // MARK: - Session Events

    @Test("session start sets status to active")
    func sessionStart() async {
        let (engine, _) = makeEngine()

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .sessionStart,
            scope: .global
        )
        await engine.injectEvent(event)

        let state = await engine.currentState()
        #expect(state.sessionStatus == "active")
    }

    @Test("session end sets status to idle")
    func sessionEnd() async {
        let (engine, _) = makeEngine()

        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .sessionStart,
            scope: .global
        ))
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .sessionEnd,
            scope: .global
        ))

        let state = await engine.currentState()
        #expect(state.sessionStatus == "idle")
    }

    // MARK: - Agent Tracking

    @Test("company dispatched adds agent")
    func companyDispatched() async {
        let (engine, _) = makeEngine()

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya"),
            payload: [
                "company": .string("maya"),
                "task": .string("Wave 3 implementation"),
            ]
        )
        await engine.injectEvent(event)

        let state = await engine.currentState()
        #expect(state.agents.count == 1)
        #expect(state.agents.first?.name == "maya")
        #expect(state.agents.first?.status == .active)
        #expect(state.agents.first?.detail == "Wave 3 implementation")
    }

    @Test("company stale marks agent as failed")
    func companyStale() async {
        let (engine, _) = makeEngine()

        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya"),
            payload: ["company": .string("maya"), "task": .string("Building")]
        ))
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .companyStale,
            scope: .project(slug: "maya"),
            payload: ["company": .string("maya")]
        ))

        let state = await engine.currentState()
        #expect(state.agents.first?.status == .failed)
        #expect(state.agents.first?.detail == "Stale")
    }

    @Test("ship completed marks agent as completed")
    func shipCompleted() async {
        let (engine, _) = makeEngine()

        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "wabisabi"),
            payload: ["company": .string("wabisabi"), "task": .string("Ship v1")]
        ))
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .shipCompleted,
            scope: .project(slug: "wabisabi"),
            payload: ["company": .string("wabisabi")]
        ))

        let state = await engine.currentState()
        let agent = state.agents.first { $0.name == "wabisabi" }
        #expect(agent?.status == .completed)
        #expect(agent?.progress == 100)
    }

    // MARK: - Budget

    @Test("setBudget updates budget display")
    func budgetUpdates() async {
        let (engine, _) = makeEngine()

        await engine.setBudget(spent: 15.50, limit: 50.00)
        let state = await engine.currentState()

        #expect(state.budget.spent == 15.50)
        #expect(state.budget.limit == 50.00)
        #expect(state.budget.percent == 31)
    }

    // MARK: - Test Count

    @Test("test run events increment test count")
    func testRunCount() async {
        let (engine, _) = makeEngine()

        await engine.injectEvent(ShikkiEvent(
            source: .process(name: "swift-test"),
            type: .testRun,
            scope: .project(slug: "maya"),
            payload: ["passed": .bool(true), "count": .int(42)]
        ))

        let state = await engine.currentState()
        #expect(state.testCount == 42)
    }

    // MARK: - Event Feed

    @Test("significant events appear in event log")
    func eventFeedCapture() async {
        let (engine, _) = makeEngine()

        // Heartbeat = noise, should NOT appear
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .heartbeat,
            scope: .global
        ))

        // Session start = progress, SHOULD appear
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .sessionStart,
            scope: .global
        ))

        let state = await engine.currentState()
        #expect(state.events.count == 1)
        #expect(state.events.first?.type == "session_start")
    }

    @Test("event log caps at 10 for display")
    func eventLogCap() async {
        let (engine, _) = makeEngine()

        for i in 0..<20 {
            await engine.injectEvent(ShikkiEvent(
                source: .orchestrator,
                type: .sessionStart,
                scope: .global,
                payload: ["detail": .string("Event \(i)")]
            ))
        }

        let state = await engine.currentState()
        #expect(state.events.count == 10)
        // Most recent should be first
        #expect(state.events.first?.detail == "Event 19")
    }

    // MARK: - Version and Branch

    @Test("setVersion and setBranch update state")
    func versionAndBranch() async {
        let (engine, _) = makeEngine()

        await engine.setVersion("1.0.0")
        await engine.setBranch("feature/awesome")

        let state = await engine.currentState()
        #expect(state.version == "1.0.0")
        #expect(state.branch == "feature/awesome")
    }

    // MARK: - Session Uptime

    @Test("session uptime increases over time")
    func sessionUptime() async {
        let (engine, _) = makeEngine()

        // Set start time to 60 seconds ago
        let startTime = Date().addingTimeInterval(-60)
        await engine.resetSessionStart(startTime)

        let state = await engine.currentState()
        #expect(state.sessionUptime >= 59) // Allow 1s tolerance
        #expect(state.sessionUptime <= 62)
    }

    // MARK: - Multiple Agents Sorted

    @Test("agents are sorted by name")
    func agentsSorted() async {
        let (engine, _) = makeEngine()

        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "zeta"),
            payload: ["company": .string("zeta"), "task": .string("Task Z")]
        ))
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "alpha"),
            payload: ["company": .string("alpha"), "task": .string("Task A")]
        ))
        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya"),
            payload: ["company": .string("maya"), "task": .string("Task M")]
        ))

        let state = await engine.currentState()
        let names = state.agents.map(\.name)
        #expect(names == ["alpha", "maya", "zeta"])
    }

    // MARK: - CodeGen Events

    @Test("codegen events track agent lifecycle")
    func codeGenLifecycle() async {
        let (engine, _) = makeEngine()

        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .codeGenAgentDispatched,
            scope: .global,
            payload: ["agent": .string("codegen-1"), "workUnit": .string("Wave 2")]
        ))

        var state = await engine.currentState()
        let active = state.agents.first { $0.name == "codegen-1" }
        #expect(active?.status == .active)
        #expect(active?.detail == "Wave 2")

        await engine.injectEvent(ShikkiEvent(
            source: .orchestrator,
            type: .codeGenAgentCompleted,
            scope: .global,
            payload: ["agent": .string("codegen-1")]
        ))

        state = await engine.currentState()
        let completed = state.agents.first { $0.name == "codegen-1" }
        #expect(completed?.status == .completed)
        #expect(completed?.progress == 100)
    }
}
