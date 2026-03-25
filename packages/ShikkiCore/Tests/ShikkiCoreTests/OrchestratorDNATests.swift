import Testing
import Foundation
@testable import ShikkiCore

@Suite("Orchestrator DNA — S2")
struct OrchestratorDNATests {

    // MARK: - Mock Orchestrator

    struct MockOrchestrator: OrchestratorProtocol {
        func understand(intent: String) async -> OrchestratorPlan {
            OrchestratorPlan(intent: intent, projects: ["projects/Maya/"], waves: [])
        }

        func scope(plan: OrchestratorPlan) async -> [DispatchRequest] {
            plan.projects.map { project in
                DispatchRequest(
                    agentId: "agent-\(project)",
                    project: project,
                    branch: "feature/test",
                    baseBranch: "develop",
                    specPath: "features/test.md"
                )
            }
        }

        func present(plan: OrchestratorPlan) async -> String {
            "Plan: \(plan.intent) across \(plan.projects.count) project(s)"
        }

        func dispatch(requests: [DispatchRequest]) async throws -> [String] {
            requests.map(\.agentId)
        }

        func monitor(agentIds: [String]) async -> AsyncStream<DispatchEvent> {
            AsyncStream { continuation in
                for id in agentIds {
                    continuation.yield(DispatchEvent(agentId: id, type: .taskStarted))
                    continuation.yield(DispatchEvent(agentId: id, type: .taskCompleted))
                }
                continuation.finish()
            }
        }

        func collect(agentIds: [String]) async throws -> OrchestratorResult {
            OrchestratorResult(
                plan: OrchestratorPlan(intent: "test", projects: [], waves: []),
                agentResults: agentIds.map {
                    AgentSummary(agentId: $0, project: "p/", branch: "b", testsRun: 10, testsPassed: 10, filesChanged: 5)
                },
                totalTests: 10 * agentIds.count,
                totalFilesChanged: 5 * agentIds.count,
                prNumbers: [19, 20],
                success: true
            )
        }

        func report(result: OrchestratorResult) async -> String {
            "\(result.prNumbers.count) PRs ready. \(result.totalTests) tests green."
        }
    }

    // MARK: - OrchestratorProtocol Tests

    @Test("Mock orchestrator conforms to OrchestratorProtocol")
    func protocolConformance() async throws {
        let orchestrator = MockOrchestrator()
        let plan = await orchestrator.understand(intent: "Add animations")
        #expect(plan.intent == "Add animations")
        #expect(plan.projects.count == 1)

        let requests = await orchestrator.scope(plan: plan)
        #expect(requests.count == 1)

        let presentation = await orchestrator.present(plan: plan)
        #expect(presentation.contains("1 project"))

        let agentIds = try await orchestrator.dispatch(requests: requests)
        #expect(agentIds.count == 1)

        let result = try await orchestrator.collect(agentIds: agentIds)
        #expect(result.success)
        #expect(result.totalTests == 10)
    }

    @Test("Monitor emits events in correct order")
    func monitorEventOrder() async {
        let orchestrator = MockOrchestrator()
        let stream = await orchestrator.monitor(agentIds: ["agent-1"])

        var events: [DispatchEventType] = []
        for await event in stream {
            events.append(event.type)
        }
        #expect(events == [.taskStarted, .taskCompleted])
    }

    // MARK: - OrchestratorPlan Codable

    @Test("OrchestratorPlan Codable round-trip")
    func planCodable() throws {
        let wave = WaveNode(id: "w1", name: "Wave 1", branch: "feat/x", baseBranch: "develop")
        let plan = OrchestratorPlan(
            intent: "Build feature X",
            projects: ["projects/Maya/", "projects/wabisabi/"],
            waves: [wave],
            estimatedCost: 12.5
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(OrchestratorPlan.self, from: data)

        #expect(decoded.intent == "Build feature X")
        #expect(decoded.projects.count == 2)
        #expect(decoded.waves.count == 1)
        #expect(decoded.estimatedCost == 12.5)
    }

    // MARK: - OrchestratorResult

    @Test("OrchestratorResult aggregates agent summaries")
    func resultAggregation() {
        let summary1 = AgentSummary(agentId: "a1", project: "p1", branch: "b1", testsRun: 23, testsPassed: 23, filesChanged: 10, prNumber: 19)
        let summary2 = AgentSummary(agentId: "a2", project: "p2", branch: "b2", testsRun: 30, testsPassed: 29, filesChanged: 12, prNumber: 20, blockers: ["flaky test"])
        let plan = OrchestratorPlan(intent: "test", projects: ["p1", "p2"], waves: [])

        let result = OrchestratorResult(
            plan: plan,
            agentResults: [summary1, summary2],
            totalTests: 53,
            totalFilesChanged: 22,
            prNumbers: [19, 20],
            success: true
        )

        #expect(result.agentResults.count == 2)
        #expect(result.totalTests == 53)
        #expect(result.prNumbers == [19, 20])
        #expect(result.agentResults[1].blockers.count == 1)
    }
}
