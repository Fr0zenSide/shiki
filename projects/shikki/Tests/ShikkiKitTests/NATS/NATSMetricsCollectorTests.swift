import Foundation
import Testing
@testable import ShikkiKit

@Suite("NATSMetricsCollector")
struct NATSMetricsCollectorTests {

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Subject Extraction

    @Test("extractCompany parses company from event subject")
    func extractCompanyFromSubject() {
        #expect(NATSMetricsCollector.extractCompany(from: "shikki.events.maya.agent") == "maya")
        #expect(NATSMetricsCollector.extractCompany(from: "shikki.events.shiki.lifecycle") == "shiki")
        #expect(NATSMetricsCollector.extractCompany(from: "shikki.events.wabisabi.ship") == "wabisabi")
    }

    @Test("extractCompany returns nil for non-event subjects")
    func extractCompanyReturnsNilForNonEvents() {
        #expect(NATSMetricsCollector.extractCompany(from: "shikki.discovery.announce") == nil)
        #expect(NATSMetricsCollector.extractCompany(from: "shikki.commands.node1") == nil)
        #expect(NATSMetricsCollector.extractCompany(from: "random.topic") == nil)
        #expect(NATSMetricsCollector.extractCompany(from: "") == nil)
    }

    @Test("extractCompany handles short subjects")
    func extractCompanyHandlesShortSubjects() {
        #expect(NATSMetricsCollector.extractCompany(from: "shikki.events") == nil)
        #expect(NATSMetricsCollector.extractCompany(from: "shikki") == nil)
    }

    // MARK: - WindowedCounter

    @Test("WindowedCounter counts events within window")
    func windowedCounterCounts() {
        var counter = WindowedCounter()
        let base = now

        // Record 3 events within the last minute
        counter.record(at: base.addingTimeInterval(-30))
        counter.record(at: base.addingTimeInterval(-20))
        counter.record(at: base.addingTimeInterval(-10))

        #expect(counter.count(window: .oneMinute, now: base) == 3)
        #expect(counter.count(window: .fiveMinutes, now: base) == 3)
        #expect(counter.total == 3)
    }

    @Test("WindowedCounter excludes events outside window")
    func windowedCounterExcludes() {
        var counter = WindowedCounter()
        let base = now

        // 2 events within 1 minute, 1 event 3 minutes ago
        counter.record(at: base.addingTimeInterval(-30))
        counter.record(at: base.addingTimeInterval(-45))
        counter.record(at: base.addingTimeInterval(-180))

        #expect(counter.count(window: .oneMinute, now: base) == 2)
        #expect(counter.count(window: .fiveMinutes, now: base) == 3)
    }

    @Test("WindowedCounter rate computes events per second")
    func windowedCounterRate() {
        var counter = WindowedCounter()
        let base = now

        // 60 events in 1 minute = 1.0 events/sec
        for i in 0..<60 {
            counter.record(at: base.addingTimeInterval(-Double(i)))
        }

        let rate = counter.rate(window: .oneMinute, now: base)
        #expect(rate == 1.0)
    }

    @Test("WindowedCounter prune removes old entries")
    func windowedCounterPrune() {
        var counter = WindowedCounter()
        let base = now

        // 1 event 25 hours ago (should be pruned)
        counter.record(at: base.addingTimeInterval(-90_000))
        // 1 event 1 hour ago (should survive)
        counter.record(at: base.addingTimeInterval(-3_600))

        #expect(counter.total == 2)
        counter.prune(now: base)
        #expect(counter.total == 1)
    }

    // MARK: - Collector Recording

    @Test("Recording events updates subject and company counters")
    func recordingUpdatesCounters() async {
        let collector = NATSMetricsCollector()
        let base = now

        await collector.record(subject: "shikki.events.maya.agent", at: base)
        await collector.record(subject: "shikki.events.maya.lifecycle", at: base)
        await collector.record(subject: "shikki.events.shiki.agent", at: base)

        #expect(await collector.trackedSubjectCount == 3)
        #expect(await collector.trackedCompanyCount == 2)
        #expect(await collector.companyCount(company: "maya", window: .oneMinute, now: base) == 2)
        #expect(await collector.companyCount(company: "shiki", window: .oneMinute, now: base) == 1)
    }

    @Test("Global count reflects all events across companies")
    func globalCountReflectsAll() async {
        let collector = NATSMetricsCollector()
        let base = now

        await collector.record(subject: "shikki.events.maya.agent", at: base)
        await collector.record(subject: "shikki.events.shiki.agent", at: base)
        await collector.record(subject: "shikki.events.wabisabi.ship", at: base)

        #expect(await collector.globalCount(window: .oneMinute, now: base) == 3)
    }

    @Test("allCompanyCounts returns all companies in window")
    func allCompanyCountsReturnsAll() async {
        let collector = NATSMetricsCollector()
        let base = now

        await collector.record(subject: "shikki.events.maya.agent", at: base)
        await collector.record(subject: "shikki.events.maya.agent", at: base)
        await collector.record(subject: "shikki.events.shiki.lifecycle", at: base)

        let counts = await collector.allCompanyCounts(window: .oneMinute, now: base)
        #expect(counts["maya"] == 2)
        #expect(counts["shiki"] == 1)
    }

    // MARK: - Agent Utilization

    @Test("Agent utilization tracks dispatch/complete/fail")
    func agentUtilizationTracking() async {
        let collector = NATSMetricsCollector()

        await collector.recordAgent(agentId: "agent-a1", company: "maya", event: .dispatched)
        await collector.recordAgent(agentId: "agent-a1", company: "maya", event: .completed, duration: 120.0)
        await collector.recordAgent(agentId: "agent-a1", company: "maya", event: .dispatched)
        await collector.recordAgent(agentId: "agent-a1", company: "maya", event: .failed)

        let agents = await collector.allAgentUtilization()
        #expect(agents.count == 1)

        let agent = agents[0]
        #expect(agent.agentId == "agent-a1")
        #expect(agent.company == "maya")
        #expect(agent.dispatched == 2)
        #expect(agent.completed == 1)
        #expect(agent.failed == 1)
        #expect(agent.totalDurationSeconds == 120.0)
        #expect(agent.completionRate == 50)
    }

    @Test("Agent utilization filters by company")
    func agentUtilizationFiltersByCompany() async {
        let collector = NATSMetricsCollector()

        await collector.recordAgent(agentId: "agent-a1", company: "maya", event: .dispatched)
        await collector.recordAgent(agentId: "agent-b1", company: "shiki", event: .dispatched)

        let mayaAgents = await collector.agentUtilization(company: "maya")
        #expect(mayaAgents.count == 1)
        #expect(mayaAgents[0].agentId == "agent-a1")

        let shikiAgents = await collector.agentUtilization(company: "shiki")
        #expect(shikiAgents.count == 1)
        #expect(shikiAgents[0].agentId == "agent-b1")
    }

    // MARK: - Subject Metrics

    @Test("allSubjectMetrics returns rates and counts per subject")
    func allSubjectMetricsReturnsRatesAndCounts() async {
        let collector = NATSMetricsCollector()
        let base = now

        await collector.record(subject: "shikki.events.maya.agent", at: base)
        await collector.record(subject: "shikki.events.maya.agent", at: base)

        let metrics = await collector.allSubjectMetrics(now: base)
        #expect(metrics.count == 1)
        #expect(metrics[0].subject == "shikki.events.maya.agent")
        #expect(metrics[0].counts["1m"] == 2)
    }

    // MARK: - Reset

    @Test("Reset clears all metrics")
    func resetClearsAll() async {
        let collector = NATSMetricsCollector()

        await collector.record(subject: "shikki.events.maya.agent", at: now)
        await collector.recordAgent(agentId: "agent-a1", company: "maya", event: .dispatched)

        #expect(await collector.trackedSubjectCount == 1)
        #expect(await collector.trackedAgentCount == 1)

        await collector.reset()

        #expect(await collector.trackedSubjectCount == 0)
        #expect(await collector.trackedAgentCount == 0)
        #expect(await collector.globalCount(window: .oneMinute, now: now) == 0)
    }

    // MARK: - AgentUtilization model

    @Test("AgentUtilization completionRate handles zero dispatches")
    func completionRateZeroDispatches() {
        let util = AgentUtilization(agentId: "a", company: "x")
        #expect(util.completionRate == 0)
    }

    // MARK: - MetricsWindow

    @Test("MetricsWindow seconds are correct")
    func timeWindowSeconds() {
        #expect(MetricsWindow.oneMinute.seconds == 60)
        #expect(MetricsWindow.fiveMinutes.seconds == 300)
        #expect(MetricsWindow.oneHour.seconds == 3_600)
        #expect(MetricsWindow.twentyFourHours.seconds == 86_400)
    }

    // MARK: - GateResultCounts

    @Test("GateResultCounts passRate computes correctly")
    func gateResultPassRate() {
        let counts = GateResultCounts(passed: 8, failed: 2)
        #expect(counts.passRate == 80)
        #expect(counts.total == 10)
    }

    @Test("GateResultCounts passRate handles zero total")
    func gateResultPassRateZero() {
        let counts = GateResultCounts(passed: 0, failed: 0)
        #expect(counts.passRate == 0)
        #expect(counts.total == 0)
    }
}
