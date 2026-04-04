import Foundation

// MARK: - ReactiveDashboardEngine

/// Maintains live dashboard state by subscribing to the EventBus.
/// Events flow in, state is updated, and the dashboard re-renders.
///
/// This is the reactive core — the DashboardCommand drives the TUI loop,
/// and this engine provides the data stream.
public actor ReactiveDashboardEngine {
    private let eventBus: InProcessEventBus
    private var state: DashboardState
    private var sessionStartTime: Date
    private var eventLog: [DashboardState.DashboardEvent] = []
    private var agentMap: [String: DashboardState.AgentStatus] = [:]
    private var budgetSpent: Double = 0
    private var budgetLimit: Double = 0
    private var testCount: Int = 0
    private var openPRs: Int = 0

    private static let maxEventLog = 50

    public init(
        eventBus: InProcessEventBus,
        initialState: DashboardState = DashboardState()
    ) {
        self.eventBus = eventBus
        self.state = initialState
        self.sessionStartTime = Date()
    }

    // MARK: - Public API

    /// Get current snapshot of dashboard state.
    public func currentState() -> DashboardState {
        var s = state
        s.sessionUptime = Date().timeIntervalSince(sessionStartTime)
        s.agents = Array(agentMap.values).sorted { $0.name < $1.name }
        s.budget = DashboardState.BudgetDisplay(spent: budgetSpent, limit: budgetLimit)
        s.testCount = testCount
        s.openPRs = openPRs
        s.events = Array(eventLog.prefix(10))
        return s
    }

    /// Start listening to the EventBus. Call from a detached Task.
    /// Returns when the stream terminates.
    public func startListening() async {
        let stream = await eventBus.subscribe(filter: .all)
        for await event in stream {
            processEvent(event)
        }
    }

    /// Manually inject an event (useful for testing or hybrid mode).
    public func injectEvent(_ event: ShikkiEvent) {
        processEvent(event)
    }

    /// Update budget limits (from external source like backend).
    public func setBudget(spent: Double, limit: Double) {
        self.budgetSpent = spent
        self.budgetLimit = limit
    }

    /// Update branch info.
    public func setBranch(_ branch: String) {
        state.branch = branch
    }

    /// Update version string.
    public func setVersion(_ version: String) {
        state.version = version
    }

    /// Reset session start time (e.g., on session resume).
    public func resetSessionStart(_ date: Date = Date()) {
        self.sessionStartTime = date
    }

    // MARK: - Event Processing

    private func processEvent(_ event: ShikkiEvent) {
        // Classify the event and extract dashboard-relevant info
        let significance = EventClassifier.classify(event)

        switch event.type {
        // Session lifecycle
        case .sessionStart:
            state.sessionStatus = "active"
            sessionStartTime = event.timestamp
        case .sessionEnd:
            state.sessionStatus = "idle"
        case .sessionTransition:
            if let newState = event.payload["state"]?.stringValue {
                state.sessionStatus = newState
            }

        // Agent tracking
        case .companyDispatched:
            let agentName = extractAgentName(from: event)
            let detail = event.payload["task"]?.stringValue ?? "Dispatched"
            agentMap[agentName] = DashboardState.AgentStatus(
                name: agentName, status: .active, progress: 0, detail: detail
            )
        case .companyStale:
            let agentName = extractAgentName(from: event)
            if var agent = agentMap[agentName] {
                agent = DashboardState.AgentStatus(
                    name: agent.name, status: .failed,
                    progress: agent.progress, detail: "Stale"
                )
                agentMap[agentName] = agent
            }
        case .companyRelaunched:
            let agentName = extractAgentName(from: event)
            agentMap[agentName] = DashboardState.AgentStatus(
                name: agentName, status: .active, progress: 0, detail: "Relaunched"
            )

        // Budget
        case .budgetExhausted:
            if let spent = event.payload["spent"]?.doubleValue {
                budgetSpent = spent
            }

        // Code & Tests
        case .testRun:
            if event.payload["passed"] == .bool(true) {
                if let count = event.payload["count"]?.intValue {
                    testCount = count
                } else {
                    testCount += 1
                }
            }
        case .buildResult:
            if let agentName = event.payload["agent"]?.stringValue {
                let success = event.payload["success"] == .bool(true)
                if var agent = agentMap[agentName] {
                    let newProgress = min(agent.progress + 10, 95)
                    agent = DashboardState.AgentStatus(
                        name: agent.name,
                        status: success ? .active : .failed,
                        progress: newProgress,
                        detail: success ? "Build passed" : "Build failed"
                    )
                    agentMap[agentName] = agent
                }
            }

        // PR
        case .prVerdictSet:
            openPRs += 1

        // Ship
        case .shipCompleted:
            let agentName = extractAgentName(from: event)
            agentMap[agentName] = DashboardState.AgentStatus(
                name: agentName, status: .completed, progress: 100, detail: "Shipped"
            )

        // CodeGen progress
        case .codeGenAgentDispatched:
            let agentName = event.payload["agent"]?.stringValue ?? "codegen"
            let detail = event.payload["workUnit"]?.stringValue ?? "Code generation"
            agentMap[agentName] = DashboardState.AgentStatus(
                name: agentName, status: .active, progress: 10, detail: detail
            )
        case .codeGenAgentCompleted:
            let agentName = event.payload["agent"]?.stringValue ?? "codegen"
            agentMap[agentName] = DashboardState.AgentStatus(
                name: agentName, status: .completed, progress: 100, detail: "Complete"
            )
        case .codeGenPipelineFailed:
            let agentName = event.payload["agent"]?.stringValue ?? "codegen"
            let reason = event.payload["error"]?.stringValue ?? "Pipeline failed"
            agentMap[agentName] = DashboardState.AgentStatus(
                name: agentName, status: .failed, progress: 0, detail: reason
            )

        default:
            break
        }

        // Log significant events to the dashboard event feed
        if significance >= .progress {
            let dashEvent = DashboardState.DashboardEvent(
                timestamp: event.timestamp,
                type: eventTypeLabel(event.type),
                agent: extractAgentName(from: event),
                detail: eventDetailSummary(event)
            )
            eventLog.insert(dashEvent, at: 0)
            if eventLog.count > Self.maxEventLog {
                eventLog.removeLast()
            }
        }
    }

    // MARK: - Helpers

    private func extractAgentName(from event: ShikkiEvent) -> String {
        // Try payload first
        if let name = event.payload["company"]?.stringValue { return name }
        if let name = event.payload["agent"]?.stringValue { return name }

        // Try source
        switch event.source {
        case .agent(_, let name):
            return name ?? "agent"
        case .process(let name):
            return name
        default:
            break
        }

        // Try scope
        switch event.scope {
        case .project(let slug):
            return slug
        case .session(let id):
            return String(id.prefix(12))
        default:
            return "system"
        }
    }

    private func eventTypeLabel(_ type: EventType) -> String {
        switch type {
        case .sessionStart: return "session_start"
        case .sessionEnd: return "session_end"
        case .companyDispatched: return "dispatched"
        case .companyStale: return "stale"
        case .testRun: return "test_run"
        case .buildResult: return "build"
        case .prVerdictSet: return "pr_verdict"
        case .shipStarted: return "ship_start"
        case .shipCompleted: return "ship_done"
        case .shipGatePassed: return "gate_pass"
        case .shipGateFailed: return "gate_fail"
        case .codeGenStarted: return "codegen_start"
        case .codeGenPipelineCompleted: return "codegen_done"
        case .codeGenPipelineFailed: return "codegen_fail"
        case .decisionPending: return "decision"
        case .budgetExhausted: return "budget_warn"
        case .contextCompaction: return "compaction"
        case .custom(let name): return name
        default: return "event"
        }
    }

    private func eventDetailSummary(_ event: ShikkiEvent) -> String {
        if let detail = event.payload["detail"]?.stringValue { return detail }
        if let task = event.payload["task"]?.stringValue { return task }
        if let file = event.payload["file"]?.stringValue { return file }
        if let question = event.payload["question"]?.stringValue {
            return String(question.prefix(40))
        }
        return ""
    }
}
