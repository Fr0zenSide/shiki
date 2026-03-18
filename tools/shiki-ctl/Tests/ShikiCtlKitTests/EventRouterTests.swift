import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Classification Tests

@Suite("Event Router — Classification")
struct EventClassificationTests {

    @Test("Heartbeat classified as noise by default")
    func heartbeatIsNoise() {
        let event = ShikiEvent(source: .orchestrator, type: .heartbeat, scope: .global)
        let significance = EventClassifier.classify(event)
        #expect(significance == .noise)
    }

    @Test("Session start classified as progress")
    func sessionStartIsProgress() {
        let event = ShikiEvent(source: .orchestrator, type: .sessionStart, scope: .session(id: "s1"))
        let significance = EventClassifier.classify(event)
        #expect(significance == .progress)
    }

    @Test("Decision pending classified as decision")
    func decisionIsPriority() {
        let event = ShikiEvent(source: .orchestrator, type: .decisionPending, scope: .project(slug: "maya"))
        let significance = EventClassifier.classify(event)
        #expect(significance == .decision)
    }

    @Test("Budget exhausted classified as alert")
    func budgetIsAlert() {
        let event = ShikiEvent(source: .orchestrator, type: .budgetExhausted, scope: .project(slug: "maya"))
        let significance = EventClassifier.classify(event)
        #expect(significance == .alert)
    }

    @Test("Custom red flag classified as critical")
    func redFlagIsCritical() {
        let event = ShikiEvent(source: .system, type: .custom("redFlag"), scope: .global)
        let significance = EventClassifier.classify(event)
        #expect(significance == .critical)
    }
}

// MARK: - Enrichment Tests

@Suite("Event Router — Enrichment")
struct EventEnrichmentTests {

    @Test("Enrich adds session state from registry")
    func enrichWithSessionState() async {
        let discoverer = MockSessionDiscoverer()
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "router-enrich-\(UUID().uuidString)")
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        await registry.registerManual(windowName: "maya:task", paneId: "%1", pid: 1, state: .working)

        let event = ShikiEvent(source: .agent(id: "maya:task", name: nil), type: .codeChange, scope: .session(id: "maya:task"))
        let enricher = EventEnricher(registry: registry)
        let context = await enricher.enrich(event)

        #expect(context.sessionState == .working)
        #expect(context.attentionZone == .working)
    }

    @Test("Enrich adds company slug from scope")
    func enrichWithCompanySlug() async {
        let enricher = EventEnricher(registry: nil)
        let event = ShikiEvent(source: .orchestrator, type: .heartbeat, scope: .project(slug: "wabisabi"))
        let context = await enricher.enrich(event)

        #expect(context.companySlug == "wabisabi")
    }

    @Test("Enrich handles missing registry gracefully")
    func enrichWithoutRegistry() async {
        let enricher = EventEnricher(registry: nil)
        let event = ShikiEvent(source: .system, type: .heartbeat, scope: .global)
        let context = await enricher.enrich(event)

        #expect(context.sessionState == nil)
        #expect(context.attentionZone == nil)
    }
}

// MARK: - Routing Tests

@Suite("Event Router — Routing")
struct EventRoutingTests {

    @Test("Noise events get suppress hint")
    func noiseIsSuppressed() {
        let hint = RoutingTable.displayHint(for: .noise)
        #expect(hint == .suppress)
    }

    @Test("Decision events go to timeline")
    func decisionToTimeline() {
        let hint = RoutingTable.displayHint(for: .decision)
        #expect(hint == .timeline)
    }

    @Test("Critical events go to notification")
    func criticalToNotification() {
        let hint = RoutingTable.displayHint(for: .critical)
        #expect(hint == .notification)
    }

    @Test("Progress events go to timeline")
    func progressToTimeline() {
        let hint = RoutingTable.displayHint(for: .progress)
        #expect(hint == .timeline)
    }

    @Test("Destinations for timeline include DB and TUI")
    func timelineDestinations() {
        let dests = RoutingTable.destinations(for: .timeline)
        #expect(dests.contains(.database))
        #expect(dests.contains(.observatoryTUI))
    }

    @Test("Destinations for suppress is empty")
    func suppressDestinations() {
        let dests = RoutingTable.destinations(for: .suppress)
        #expect(dests.isEmpty)
    }

    @Test("Destinations for notification include ntfy")
    func notificationDestinations() {
        let dests = RoutingTable.destinations(for: .notification)
        #expect(dests.contains(.ntfy))
        #expect(dests.contains(.database))
    }
}

// MARK: - Pattern Detection Tests

@Suite("Event Router — Pattern Detection")
struct PatternDetectionTests {

    @Test("Stuck agent detected after 3 heartbeats with no progress")
    func stuckAgentDetected() {
        let detector = PatternDetector()
        let sessionScope = EventScope.session(id: "maya:task")

        // 3 heartbeats, no code changes
        for _ in 0..<3 {
            detector.record(ShikiEvent(source: .orchestrator, type: .heartbeat, scope: sessionScope))
        }

        let patterns = detector.detect()
        #expect(patterns.contains { $0.name == "stuck_agent" })
    }

    @Test("No stuck agent if code changes between heartbeats")
    func noStuckWithProgress() {
        let detector = PatternDetector()
        let scope = EventScope.session(id: "maya:task")

        detector.record(ShikiEvent(source: .orchestrator, type: .heartbeat, scope: scope))
        detector.record(ShikiEvent(source: .agent(id: "maya:task", name: nil), type: .codeChange, scope: scope))
        detector.record(ShikiEvent(source: .orchestrator, type: .heartbeat, scope: scope))

        let patterns = detector.detect()
        #expect(!patterns.contains { $0.name == "stuck_agent" })
    }

    @Test("Repeat failure detected after 3 test failures")
    func repeatFailureDetected() {
        let detector = PatternDetector()
        let scope = EventScope.session(id: "maya:task")

        for _ in 0..<3 {
            detector.record(ShikiEvent(
                source: .agent(id: "maya:task", name: nil), type: .testRun, scope: scope,
                payload: ["passed": .bool(false), "testName": .string("testAuth")]
            ))
        }

        let patterns = detector.detect()
        #expect(patterns.contains { $0.name == "repeat_failure" })
    }
}

// MARK: - Full Pipeline Tests

@Suite("Event Router — Full Pipeline")
struct EventRouterPipelineTests {

    @Test("Event passes through classify → enrich → route")
    func fullPipeline() async {
        let router = EventRouter()
        let event = ShikiEvent(source: .orchestrator, type: .sessionStart, scope: .session(id: "test"))

        let envelope = await router.process(event)

        #expect(envelope.significance == .progress)
        #expect(envelope.displayHint == .timeline)
    }

    @Test("Noise event is suppressed in full pipeline")
    func noiseSuppressed() async {
        let router = EventRouter()
        let event = ShikiEvent(source: .orchestrator, type: .heartbeat, scope: .global)

        let envelope = await router.process(event)

        #expect(envelope.significance == .noise)
        #expect(envelope.displayHint == .suppress)
    }
}
