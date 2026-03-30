import Foundation
import Testing
@testable import ShikkiKit

@Suite("NATSReportAggregator")
struct NATSReportAggregatorTests {

    // MARK: - Helpers

    private func makeEvent(
        type: EventType = .heartbeat,
        scope: EventScope = .project(slug: "maya"),
        source: EventSource = .orchestrator,
        payload: [String: EventValue] = [:],
        metadata: EventMetadata? = nil
    ) -> ShikkiEvent {
        ShikkiEvent(source: source, type: type, scope: scope, payload: payload, metadata: metadata)
    }

    private func encodeEvent(_ event: ShikkiEvent) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(event)
    }

    // MARK: - Lifecycle

    @Test("Aggregator starts and subscribes to all events")
    func aggregatorStartsAndSubscribes() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()

        // Give subscription time to register
        try await Task.sleep(for: .milliseconds(50))

        let subs = await mock.subscribedSubjects
        #expect(subs.contains("shikki.events.>"))
        #expect(await aggregator.isRunning)

        await aggregator.stop()
        #expect(await mock.isConnected == false)
    }

    @Test("Aggregator auto-connects if not connected")
    func aggregatorAutoConnects() async throws {
        let mock = MockNATSClient()
        #expect(await mock.isConnected == false)

        let aggregator = NATSReportAggregator(nats: mock)
        try await aggregator.start()

        #expect(await mock.isConnected == true)

        await aggregator.stop()
    }

    @Test("Aggregator stop cancels task and disconnects")
    func aggregatorStopCleansUp() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        #expect(await aggregator.isRunning)

        await aggregator.stop()
        #expect(await aggregator.isRunning == false)
    }

    // MARK: - Event Processing

    @Test("Aggregator counts events per company")
    func aggregatorCountsPerCompany() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        // Publish events for two companies
        let event1 = makeEvent(type: .heartbeat, scope: .project(slug: "maya"))
        let event2 = makeEvent(type: .companyDispatched, scope: .project(slug: "shiki"))
        let event3 = makeEvent(type: .heartbeat, scope: .project(slug: "maya"))

        try await mock.publish(subject: "shikki.events.maya.heartbeat", data: encodeEvent(event1))
        try await mock.publish(subject: "shikki.events.shiki.orchestration", data: encodeEvent(event2))
        try await mock.publish(subject: "shikki.events.maya.heartbeat", data: encodeEvent(event3))

        try await Task.sleep(for: .milliseconds(100))

        #expect(await aggregator.totalProcessed == 3)

        let snapshot = await aggregator.snapshot()
        #expect(snapshot.companies.count == 2)

        // Maya should have 2 events, shiki 1
        let maya = snapshot.companies.first { $0.slug == "maya" }
        let shiki = snapshot.companies.first { $0.slug == "shiki" }
        #expect(maya != nil)
        #expect(shiki != nil)

        await aggregator.stop()
    }

    @Test("Aggregator tracks agent completions")
    func aggregatorTracksAgentCompletions() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        let event = makeEvent(
            type: .codeGenAgentCompleted,
            scope: .project(slug: "maya"),
            source: .agent(id: "agent-a1", name: "Worker"),
            metadata: EventMetadata(duration: 45.0)
        )
        try await mock.publish(subject: "shikki.events.maya.codegen", data: encodeEvent(event))

        try await Task.sleep(for: .milliseconds(100))

        let snapshot = await aggregator.snapshot()
        let maya = snapshot.companies.first { $0.slug == "maya" }
        #expect(maya?.agentCompletions == 1)

        // Agent should appear in utilization
        #expect(snapshot.agents.count >= 1)

        await aggregator.stop()
    }

    @Test("Aggregator tracks gate results")
    func aggregatorTracksGateResults() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        // 2 passes, 1 fail
        let pass1 = makeEvent(type: .shipGatePassed, scope: .project(slug: "maya"))
        let pass2 = makeEvent(type: .shipGatePassed, scope: .project(slug: "maya"))
        let fail1 = makeEvent(type: .shipGateFailed, scope: .project(slug: "maya"))

        try await mock.publish(subject: "shikki.events.maya.ship", data: encodeEvent(pass1))
        try await mock.publish(subject: "shikki.events.maya.ship", data: encodeEvent(pass2))
        try await mock.publish(subject: "shikki.events.maya.ship", data: encodeEvent(fail1))

        try await Task.sleep(for: .milliseconds(100))

        let snapshot = await aggregator.snapshot()
        let maya = snapshot.companies.first { $0.slug == "maya" }
        #expect(maya?.gateResults.passed == 2)
        #expect(maya?.gateResults.failed == 1)
        #expect(maya?.gateResults.passRate == 66)

        await aggregator.stop()
    }

    @Test("Aggregator ignores malformed messages")
    func aggregatorIgnoresMalformed() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        // Publish garbage data
        try await mock.publish(subject: "shikki.events.maya.lifecycle", data: Data("not json".utf8))

        try await Task.sleep(for: .milliseconds(100))

        // Should still count the message but not crash
        #expect(await aggregator.totalProcessed == 1)

        let snapshot = await aggregator.snapshot()
        // No gate results or agent completions from garbage
        let maya = snapshot.companies.first { $0.slug == "maya" }
        #expect(maya?.agentCompletions == 0)

        await aggregator.stop()
    }

    // MARK: - Snapshot

    @Test("Snapshot includes global rates and counts")
    func snapshotIncludesGlobalMetrics() async throws {
        let mock = MockNATSClient()
        let startTime = Date()
        let aggregator = NATSReportAggregator(nats: mock, startedAt: startTime)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        let event = makeEvent(type: .heartbeat)
        try await mock.publish(subject: "shikki.events.maya.heartbeat", data: encodeEvent(event))

        try await Task.sleep(for: .milliseconds(100))

        let snapshot = await aggregator.snapshot()

        // Should have global counts for each window
        #expect(snapshot.globalCounts["1m"] != nil)
        #expect(snapshot.globalCounts["5m"] != nil)
        #expect(snapshot.globalCounts["1h"] != nil)
        #expect(snapshot.globalCounts["24h"] != nil)

        // Should have rates
        #expect(snapshot.globalRates["1m"] != nil)

        // Uptime should be positive
        #expect(snapshot.uptimeSeconds >= 0)

        await aggregator.stop()
    }

    @Test("Empty snapshot when no events received")
    func emptySnapshotNoEvents() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        let snapshot = await aggregator.snapshot()

        #expect(snapshot.companies.isEmpty)
        #expect(snapshot.agents.isEmpty)
        #expect(snapshot.globalCounts["1m"] == 0)

        await aggregator.stop()
    }

    @Test("Aggregator tracks decision latency")
    func aggregatorTracksDecisionLatency() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        // Decision pending
        let pending = makeEvent(
            type: .decisionPending,
            scope: .project(slug: "maya"),
            payload: ["decision_id": .string("dec-001")]
        )
        try await mock.publish(subject: "shikki.events.maya.decision", data: encodeEvent(pending))

        try await Task.sleep(for: .milliseconds(100))

        // Decision answered
        let answered = makeEvent(
            type: .decisionAnswered,
            scope: .project(slug: "maya"),
            payload: ["decision_id": .string("dec-001")]
        )
        try await mock.publish(subject: "shikki.events.maya.decision", data: encodeEvent(answered))

        try await Task.sleep(for: .milliseconds(100))

        let snapshot = await aggregator.snapshot()
        let maya = snapshot.companies.first { $0.slug == "maya" }
        // Decision latency should be non-nil (some positive value)
        #expect(maya?.avgDecisionLatencySeconds != nil)

        await aggregator.stop()
    }

    @Test("Aggregator prune delegates to collector")
    func aggregatorPrune() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        // Should not crash
        await aggregator.prune()

        await aggregator.stop()
    }

    @Test("Aggregator tracks agent dispatches via source field")
    func aggregatorTracksAgentDispatchesViaSource() async throws {
        let mock = MockNATSClient()
        let aggregator = NATSReportAggregator(nats: mock)

        try await aggregator.start()
        try await Task.sleep(for: .milliseconds(50))

        let event = makeEvent(
            type: .codeGenAgentDispatched,
            scope: .project(slug: "shiki"),
            source: .agent(id: "agent-b3", name: "Builder")
        )
        try await mock.publish(subject: "shikki.events.shiki.codegen", data: encodeEvent(event))

        try await Task.sleep(for: .milliseconds(100))

        let snapshot = await aggregator.snapshot()
        #expect(!snapshot.agents.isEmpty)

        let agent = snapshot.agents.first { $0.agentId == "agent-b3" }
        #expect(agent != nil)
        #expect(agent?.dispatched == 1)

        await aggregator.stop()
    }

    // MARK: - AggregatedReport model

    @Test("AggregatedReport is Equatable")
    func aggregatedReportEquatable() {
        let now = Date()
        let report1 = AggregatedReport(
            companies: [],
            globalCounts: ["1m": 5],
            globalRates: ["1m": 0.08],
            agents: [],
            generatedAt: now,
            uptimeSeconds: 60
        )
        let report2 = AggregatedReport(
            companies: [],
            globalCounts: ["1m": 5],
            globalRates: ["1m": 0.08],
            agents: [],
            generatedAt: now,
            uptimeSeconds: 60
        )
        #expect(report1 == report2)
    }

    @Test("CompanyLiveMetrics is Equatable")
    func companyLiveMetricsEquatable() {
        let m1 = CompanyLiveMetrics(
            slug: "maya",
            eventCounts: ["1m": 10],
            agentCompletions: 3,
            gateResults: GateResultCounts(passed: 2, failed: 1),
            avgDecisionLatencySeconds: 5.0
        )
        let m2 = CompanyLiveMetrics(
            slug: "maya",
            eventCounts: ["1m": 10],
            agentCompletions: 3,
            gateResults: GateResultCounts(passed: 2, failed: 1),
            avgDecisionLatencySeconds: 5.0
        )
        #expect(m1 == m2)
    }
}
