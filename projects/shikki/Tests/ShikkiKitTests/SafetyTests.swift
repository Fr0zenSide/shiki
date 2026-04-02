import Foundation
import Testing

@testable import ShikkiKit

// MARK: - Test Helpers

/// Thread-safe callback tracker for async tests.
private actor CallbackTracker {
    var fired = false
    var count = 0

    func fire() {
        fired = true
        count += 1
    }
}

// MARK: - AuditEvent Tests

@Suite("AuditEvent")
struct AuditEventTests {

    @Test("creates event with all 5W1H fields")
    func createEventWithAllFields() {
        let parentId = UUID()
        let event = AuditEvent(
            userId: "bob",
            toolName: "search",
            parameters: ["query": "swift concurrency"],
            projectSlug: "maya",
            workspaceId: "ws-1",
            context: "researching async patterns",
            sessionId: "sess-42",
            parentEventId: parentId,
            outcome: .success
        )

        #expect(event.userId == "bob")
        #expect(event.toolName == "search")
        #expect(event.parameters["query"] == "swift concurrency")
        #expect(event.projectSlug == "maya")
        #expect(event.workspaceId == "ws-1")
        #expect(event.context == "researching async patterns")
        #expect(event.sessionId == "sess-42")
        #expect(event.parentEventId == parentId)
        #expect(event.outcome == .success)
    }

    @Test("creates event with minimal fields")
    func createEventMinimal() {
        let event = AuditEvent(userId: "alice", toolName: "ping")

        #expect(event.userId == "alice")
        #expect(event.toolName == "ping")
        #expect(event.parameters.isEmpty)
        #expect(event.projectSlug == nil)
        #expect(event.workspaceId == nil)
        #expect(event.context == nil)
        #expect(event.sessionId == nil)
        #expect(event.parentEventId == nil)
        #expect(event.outcome == .success)
    }

    @Test("outcome variants encode correctly")
    func outcomeEncoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let success = AuditOutcome.success
        let failure = AuditOutcome.failure(reason: "timeout")
        let blocked = AuditOutcome.blocked(reason: "over budget")

        for outcome in [success, failure, blocked] {
            let data = try encoder.encode(outcome)
            let decoded = try decoder.decode(AuditOutcome.self, from: data)
            #expect(decoded == outcome)
        }
    }
}

// MARK: - AuditQuery Tests

@Suite("AuditQuery")
struct AuditQueryTests {

    @Test("matches filters correctly")
    func matchesFilters() {
        let event = AuditEvent(
            userId: "bob",
            toolName: "search",
            projectSlug: "maya",
            workspaceId: "ws-1"
        )

        let matchAll = AuditQuery()
        #expect(matchAll.matches(event))

        let matchUser = AuditQuery(userId: "bob")
        #expect(matchUser.matches(event))

        let noMatchUser = AuditQuery(userId: "alice")
        #expect(!noMatchUser.matches(event))

        let matchProject = AuditQuery(projectSlug: "maya")
        #expect(matchProject.matches(event))

        let noMatchProject = AuditQuery(projectSlug: "wabisabi")
        #expect(!noMatchProject.matches(event))

        let matchTool = AuditQuery(toolName: "search")
        #expect(matchTool.matches(event))

        let noMatchTool = AuditQuery(toolName: "write")
        #expect(!noMatchTool.matches(event))
    }

    @Test("date range filtering works")
    func dateRangeFilter() {
        let now = Date()
        let event = AuditEvent(
            timestamp: now,
            userId: "bob",
            toolName: "search"
        )

        let sincePast = AuditQuery(since: now.addingTimeInterval(-3600))
        #expect(sincePast.matches(event))

        let sinceFuture = AuditQuery(since: now.addingTimeInterval(3600))
        #expect(!sinceFuture.matches(event))

        let untilFuture = AuditQuery(until: now.addingTimeInterval(3600))
        #expect(untilFuture.matches(event))

        let untilPast = AuditQuery(until: now.addingTimeInterval(-3600))
        #expect(!untilPast.matches(event))
    }
}

// MARK: - AuditReport Tests

@Suite("AuditReport")
struct AuditReportTests {

    @Test("computes aggregates correctly")
    func aggregates() {
        let events = [
            AuditEvent(userId: "bob", toolName: "search", outcome: .success),
            AuditEvent(userId: "alice", toolName: "write", outcome: .success),
            AuditEvent(userId: "bob", toolName: "search", outcome: .failure(reason: "timeout")),
            AuditEvent(userId: "bob", toolName: "read", outcome: .blocked(reason: "budget")),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)

        #expect(report.totalCount == 4)
        #expect(report.uniqueUsers == Set(["bob", "alice"]))
        #expect(report.uniqueTools == Set(["search", "write", "read"]))
        #expect(report.outcomeCounts["success"] == 2)
        #expect(report.outcomeCounts["failure"] == 1)
        #expect(report.outcomeCounts["blocked"] == 1)
    }
}

// MARK: - InMemoryAuditStore Tests

@Suite("InMemoryAuditStore")
struct InMemoryAuditStoreTests {

    @Test("append and query round-trip")
    func appendAndQuery() async throws {
        let store = InMemoryAuditStore()
        let event = AuditEvent(userId: "bob", toolName: "search", projectSlug: "maya")

        try await store.append(event)
        #expect(await store.count() == 1)

        let results = try await store.query(AuditQuery(userId: "bob"))
        #expect(results.count == 1)
        #expect(results[0].id == event.id)
    }

    @Test("query respects limit")
    func queryLimit() async throws {
        let store = InMemoryAuditStore()
        for i in 0..<10 {
            try await store.append(AuditEvent(userId: "user-\(i)", toolName: "tool"))
        }

        let results = try await store.query(AuditQuery(limit: 3))
        #expect(results.count == 3)
    }

    @Test("query filters by user")
    func queryFilterByUser() async throws {
        let store = InMemoryAuditStore()
        try await store.append(AuditEvent(userId: "bob", toolName: "search"))
        try await store.append(AuditEvent(userId: "alice", toolName: "search"))
        try await store.append(AuditEvent(userId: "bob", toolName: "write"))

        let results = try await store.query(AuditQuery(userId: "bob"))
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.userId == "bob" })
    }

    @Test("clear removes all events")
    func clearEvents() async throws {
        let store = InMemoryAuditStore()
        try await store.append(AuditEvent(userId: "bob", toolName: "search"))
        try await store.append(AuditEvent(userId: "alice", toolName: "write"))

        await store.clear()
        #expect(await store.count() == 0)
    }
}

// MARK: - AuditLogger Tests

@Suite("AuditLogger")
struct AuditLoggerSafetyTests {

    @Test("logs tool call and persists event")
    func logToolCall() async throws {
        let store = InMemoryAuditStore()
        let logger = AuditLogger(store: store)

        let (event, budgetCheck) = try await logger.logToolCall(
            userId: "bob",
            toolName: "search",
            parameters: ["query": "test"],
            projectSlug: "maya"
        )

        #expect(event.userId == "bob")
        #expect(event.toolName == "search")
        #expect(budgetCheck == nil)
        #expect(await logger.eventCount() == 1)
    }

    @Test("integrates with budget ACL to block over-budget calls")
    func budgetIntegration() async throws {
        let store = InMemoryAuditStore()
        let clock = FixedBudgetClock(
            now: Date(),
            periodStarts: [.daily: Date().addingTimeInterval(-3600)]
        )
        let acl = BudgetACL(clock: clock)
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 1.00))

        let logger = AuditLogger(store: store, budgetACL: acl)

        // First call: within budget
        let (event1, check1) = try await logger.logToolCall(
            userId: "bob",
            toolName: "search",
            estimatedCostUsd: 0.50
        )
        #expect(event1.outcome == .success)
        if case .allowed(let remaining) = check1 {
            #expect(remaining >= 0.49 && remaining <= 0.51)
        } else {
            Issue.record("Expected .allowed, got \(String(describing: check1))")
        }

        // Second call: over budget
        let (event2, check2) = try await logger.logToolCall(
            userId: "bob",
            toolName: "write",
            estimatedCostUsd: 0.60
        )
        if case .blocked = event2.outcome {
            // expected
        } else {
            Issue.record("Expected .blocked outcome, got \(event2.outcome)")
        }
        if case .blocked = check2 {
            // expected
        } else {
            Issue.record("Expected .blocked check, got \(String(describing: check2))")
        }
    }

    @Test("feeds security detector on tool calls")
    func securityDetectorFeed() async throws {
        let store = InMemoryAuditStore()
        let detector = SecurityPatternDetector(config: .testing)
        let logger = AuditLogger(store: store, securityDetector: detector)

        try await logger.logToolCall(userId: "bob", toolName: "search_memories")
        try await logger.logToolCall(userId: "bob", toolName: "write_file")

        #expect(await detector.windowSize() == 2)
    }

    @Test("generates compliance report")
    func generateReport() async throws {
        let store = InMemoryAuditStore()
        let logger = AuditLogger(store: store)

        try await logger.logToolCall(userId: "bob", toolName: "search")
        try await logger.logToolCall(userId: "alice", toolName: "write")

        let report = try await logger.generateReport(query: AuditQuery())
        #expect(report.totalCount == 2)
        #expect(report.uniqueUsers.count == 2)
    }
}

// MARK: - AuditReportFormatter Tests

@Suite("AuditReportFormatter")
struct AuditReportFormatterTests {

    @Test("renders text report")
    func renderText() {
        let events = [
            AuditEvent(userId: "bob", toolName: "search", outcome: .success),
            AuditEvent(userId: "alice", toolName: "write", outcome: .blocked(reason: "budget")),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)
        let text = AuditReportFormatter.renderText(report)

        #expect(text.contains("Audit Report"))
        #expect(text.contains("Total events: 2"))
        #expect(text.contains("bob"))
        #expect(text.contains("alice"))
        #expect(text.contains("BLOCKED"))
    }

    @Test("renders JSON report")
    func renderJSON() throws {
        let events = [
            AuditEvent(userId: "bob", toolName: "search"),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)
        let json = try AuditReportFormatter.renderJSON(report)

        #expect(json.contains("\"totalCount\""))
        #expect(json.contains("\"bob\""))
    }
}

// MARK: - BudgetPolicy Tests

@Suite("BudgetPolicy")
struct BudgetPolicyTests {

    @Test("creates policy with defaults")
    func createWithDefaults() {
        let policy = BudgetPolicy(userId: "bob", capUsd: 10.0)

        #expect(policy.userId == "bob")
        #expect(policy.workspaceId == nil)
        #expect(policy.period == .daily)
        #expect(policy.capUsd == 10.0)
    }

    @Test("creates policy with all fields")
    func createWithAllFields() {
        let policy = BudgetPolicy(
            userId: "alice",
            workspaceId: "ws-1",
            period: .monthly,
            capUsd: 500.0
        )

        #expect(policy.userId == "alice")
        #expect(policy.workspaceId == "ws-1")
        #expect(policy.period == .monthly)
        #expect(policy.capUsd == 500.0)
    }

    @Test("encodes and decodes via JSON")
    func jsonRoundTrip() throws {
        // Use a date with whole-second precision to survive ISO 8601 round-trip
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = BudgetPolicy(userId: "bob", workspaceId: "ws-1", period: .weekly, capUsd: 50.0, createdAt: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(policy)
        let decoded = try decoder.decode(BudgetPolicy.self, from: data)
        #expect(decoded.id == policy.id)
        #expect(decoded.userId == policy.userId)
        #expect(decoded.workspaceId == policy.workspaceId)
        #expect(decoded.period == policy.period)
        #expect(decoded.capUsd == policy.capUsd)
        #expect(abs(decoded.createdAt.timeIntervalSince(policy.createdAt)) < 1.0)
    }
}

// MARK: - BudgetSnapshot Tests

@Suite("BudgetSnapshot")
struct BudgetSnapshotTests {

    @Test("computes remaining and percent")
    func computesDerivedValues() {
        let snap = BudgetSnapshot(userId: "bob", period: .daily, capUsd: 10.0, spentUsd: 3.0)

        #expect(snap.remainingUsd == 7.0)
        #expect(snap.percentUsed == 30.0)
    }

    @Test("clamps remaining to zero when overspent")
    func clampsRemaining() {
        let snap = BudgetSnapshot(userId: "bob", period: .daily, capUsd: 10.0, spentUsd: 15.0)

        #expect(snap.remainingUsd == 0.0)
        #expect(snap.percentUsed == 100.0)
    }

    @Test("handles zero cap gracefully")
    func zeroCap() {
        let snap = BudgetSnapshot(userId: "bob", period: .daily, capUsd: 0.0, spentUsd: 0.0)

        #expect(snap.remainingUsd == 0.0)
        #expect(snap.percentUsed == 0.0)
    }
}

// MARK: - BudgetACL Tests

@Suite("BudgetACL")
struct BudgetACLSafetyTests {

    private func makeClock() -> FixedBudgetClock {
        FixedBudgetClock(
            now: Date(),
            periodStarts: [
                .daily: Date().addingTimeInterval(-3600),
                .weekly: Date().addingTimeInterval(-86400),
                .monthly: Date().addingTimeInterval(-86400 * 7),
            ]
        )
    }

    @Test("allows call when under budget")
    func allowsUnderBudget() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 10.0))

        let result = await acl.check(userId: "bob", toolName: "search", estimatedCostUsd: 1.0)
        if case .allowed(let remaining) = result {
            #expect(remaining == 9.0)
        } else {
            Issue.record("Expected .allowed, got \(result)")
        }
    }

    @Test("blocks call when over budget")
    func blocksOverBudget() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 5.0))
        await acl.recordSpend(userId: "bob", toolName: "search", costUsd: 4.0)

        let result = await acl.check(userId: "bob", toolName: "write", estimatedCostUsd: 2.0)
        if case .blocked(let reason) = result {
            #expect(reason.contains("exceeded"))
        } else {
            Issue.record("Expected .blocked, got \(result)")
        }
    }

    @Test("returns noPolicyDefined when no policy set")
    func noPolicyDefined() async {
        let acl = BudgetACL(clock: makeClock())

        let result = await acl.check(userId: "unknown", toolName: "search", estimatedCostUsd: 1.0)
        #expect(result == .noPolicyDefined)
    }

    @Test("policy inheritance: user > workspace default")
    func policyInheritance() async {
        let acl = BudgetACL(clock: makeClock())

        // Workspace default: $10/day
        await acl.setPolicy(BudgetPolicy(userId: "*", workspaceId: "ws-1", period: .daily, capUsd: 10.0))
        // User override: $50/day
        await acl.setPolicy(BudgetPolicy(userId: "bob", workspaceId: "ws-1", period: .daily, capUsd: 50.0))

        let effective = await acl.effectivePolicy(userId: "bob", workspaceId: "ws-1", period: .daily)
        #expect(effective?.capUsd == 50.0)

        // Another user inherits workspace default
        let defaultPolicy = await acl.effectivePolicy(userId: "alice", workspaceId: "ws-1", period: .daily)
        #expect(defaultPolicy?.capUsd == 10.0)
    }

    @Test("records spend and tracks cumulative cost")
    func recordSpend() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 10.0))

        await acl.recordSpend(userId: "bob", toolName: "search", costUsd: 3.0)
        await acl.recordSpend(userId: "bob", toolName: "write", costUsd: 2.0)

        let spent = await acl.spentInPeriod(userId: "bob", period: .daily)
        #expect(spent == 5.0)
    }

    @Test("snapshot returns current budget state")
    func snapshot() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 10.0))
        await acl.recordSpend(userId: "bob", toolName: "search", costUsd: 4.0)

        let snap = await acl.snapshot(userId: "bob", period: .daily)
        #expect(snap?.capUsd == 10.0)
        #expect(snap?.spentUsd == 4.0)
        #expect(snap?.remainingUsd == 6.0)
        #expect(snap?.percentUsed == 40.0)
    }

    @Test("remove policy works")
    func removePolicy() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 10.0))
        await acl.removePolicy(userId: "bob", period: .daily)

        let effective = await acl.effectivePolicy(userId: "bob", workspaceId: nil, period: .daily)
        #expect(effective == nil)
    }

    @Test("budget exceeded callback fires")
    func budgetExceededCallback() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", period: .daily, capUsd: 1.0))
        await acl.recordSpend(userId: "bob", toolName: "search", costUsd: 0.90)

        let tracker = CallbackTracker()
        await acl.setOnBudgetExceeded { userId, period, spent in
            await tracker.fire()
        }

        _ = await acl.check(userId: "bob", toolName: "write", estimatedCostUsd: 0.20)
        #expect(await tracker.fired)
    }

    @Test("workspace isolation: different workspaces track separately")
    func workspaceIsolation() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.setPolicy(BudgetPolicy(userId: "bob", workspaceId: "ws-1", period: .daily, capUsd: 10.0))
        await acl.setPolicy(BudgetPolicy(userId: "bob", workspaceId: "ws-2", period: .daily, capUsd: 10.0))

        await acl.recordSpend(userId: "bob", workspaceId: "ws-1", toolName: "search", costUsd: 9.0)

        let spentWs1 = await acl.spentInPeriod(userId: "bob", workspaceId: "ws-1", period: .daily)
        let spentWs2 = await acl.spentInPeriod(userId: "bob", workspaceId: "ws-2", period: .daily)

        #expect(spentWs1 == 9.0)
        #expect(spentWs2 == 0.0)
    }

    @Test("clearLedger resets all spend")
    func clearLedger() async {
        let acl = BudgetACL(clock: makeClock())
        await acl.recordSpend(userId: "bob", toolName: "search", costUsd: 5.0)
        await acl.clearLedger()

        let entries = await acl.allEntries()
        #expect(entries.isEmpty)
    }
}

// MARK: - SecurityAnomaly Tests

@Suite("SecurityAnomaly")
struct SecurityAnomalyTests {

    @Test("all anomalies map to an action")
    func allAnomaliesMapped() {
        let anomalies: [SecurityAnomaly] = [
            .bulkExtraction, .crossProjectScan, .offHoursAccess,
            .exportPattern, .burnoutSignal, .knowledgeHoarding,
        ]
        for anomaly in anomalies {
            let action = SecurityPolicyMap.action(for: anomaly)
            // Just verify it returns a valid action (no crash)
            _ = action
        }
    }

    @Test("policy map returns expected actions")
    func expectedActions() {
        #expect(SecurityPolicyMap.action(for: .bulkExtraction) == .blockAndAlert)
        #expect(SecurityPolicyMap.action(for: .crossProjectScan) == .alertAndLog)
        #expect(SecurityPolicyMap.action(for: .offHoursAccess) == .logOnly)
        #expect(SecurityPolicyMap.action(for: .exportPattern) == .throttleAndAlert)
        #expect(SecurityPolicyMap.action(for: .burnoutSignal) == .logOnly)
        #expect(SecurityPolicyMap.action(for: .knowledgeHoarding) == .alertAndLog)
    }

    @Test("SecurityIncident stores all fields")
    func incidentFields() {
        let eventIds = [UUID(), UUID()]
        let incident = SecurityIncident(
            anomaly: .bulkExtraction,
            action: .blockAndAlert,
            userId: "bob",
            workspaceId: "ws-1",
            description: "100 queries in 5 min",
            relatedEventIds: eventIds
        )

        #expect(incident.anomaly == .bulkExtraction)
        #expect(incident.action == .blockAndAlert)
        #expect(incident.userId == "bob")
        #expect(incident.workspaceId == "ws-1")
        #expect(incident.relatedEventIds.count == 2)
    }
}

// MARK: - SecurityPatternDetector Tests

@Suite("SecurityPatternDetector")
struct SecurityPatternDetectorSafetyTests {

    @Test("detects bulk extraction")
    func bulkExtraction() async {
        let config = SecurityDetectorConfig(
            bulkExtractionThreshold: 5,
            bulkExtractionWindowSeconds: 300
        )
        let detector = SecurityPatternDetector(config: config)

        for i in 0..<6 {
            await detector.record(SecurityEventRecord(
                userId: "bob",
                toolName: "search-\(i)",
                timestamp: Date()
            ))
        }

        let incidents = await detector.detect()
        #expect(incidents.contains { $0.anomaly == .bulkExtraction })
        #expect(incidents.first { $0.anomaly == .bulkExtraction }?.userId == "bob")
    }

    @Test("detects cross-project scan")
    func crossProjectScan() async {
        let config = SecurityDetectorConfig(crossProjectThreshold: 3)
        let detector = SecurityPatternDetector(config: config)

        for project in ["maya", "wabisabi", "brainy", "shikki"] {
            await detector.record(SecurityEventRecord(
                userId: "eve",
                toolName: "search",
                projectSlug: project
            ))
        }

        let incidents = await detector.detect()
        #expect(incidents.contains { $0.anomaly == .crossProjectScan })
    }

    @Test("detects off-hours access")
    func offHoursAccess() async {
        let config = SecurityDetectorConfig(workingHoursStart: 9, workingHoursEnd: 18)
        let detector = SecurityPatternDetector(config: config)

        // Create a timestamp at 3 AM today
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        let threeAm = calendar.date(from: components) ?? Date()

        await detector.record(SecurityEventRecord(
            userId: "bob",
            toolName: "search",
            timestamp: threeAm
        ))

        let incidents = await detector.detect()
        #expect(incidents.contains { $0.anomaly == .offHoursAccess })
    }

    @Test("detects export pattern")
    func exportPattern() async {
        let config = SecurityDetectorConfig(
            exportPatternThreshold: 5,
            exportPatternWindowSeconds: 600
        )
        let detector = SecurityPatternDetector(config: config)

        for i in 0..<6 {
            await detector.record(SecurityEventRecord(
                userId: "eve",
                toolName: "read_memory_\(i)",
                projectSlug: "maya",
                timestamp: Date(),
                isMemoryRead: true
            ))
        }

        let incidents = await detector.detect()
        #expect(incidents.contains { $0.anomaly == .exportPattern })
    }

    @Test("detects burnout signal")
    func burnoutSignal() async {
        let config = SecurityDetectorConfig(burnoutThresholdSeconds: 3600)
        let detector = SecurityPatternDetector(config: config)

        let now = Date()
        // Events spanning 2 hours
        await detector.record(SecurityEventRecord(
            userId: "bob",
            toolName: "search",
            timestamp: now.addingTimeInterval(-7200)
        ))
        await detector.record(SecurityEventRecord(
            userId: "bob",
            toolName: "write",
            timestamp: now
        ))

        let incidents = await detector.detect()
        #expect(incidents.contains { $0.anomaly == .burnoutSignal })
    }

    @Test("detects knowledge hoarding")
    func knowledgeHoarding() async {
        let config = SecurityDetectorConfig(
            knowledgeHoardingRatio: 0.8,
            knowledgeHoardingMinQueries: 5
        )
        let detector = SecurityPatternDetector(config: config)

        // Bob does 9/10 queries for project "maya"
        for _ in 0..<9 {
            await detector.record(SecurityEventRecord(
                userId: "bob",
                toolName: "search",
                projectSlug: "maya"
            ))
        }
        await detector.record(SecurityEventRecord(
            userId: "alice",
            toolName: "search",
            projectSlug: "maya"
        ))

        let incidents = await detector.detect()
        #expect(incidents.contains { $0.anomaly == .knowledgeHoarding })
    }

    @Test("no false positives when under thresholds")
    func noFalsePositives() async {
        let config = SecurityDetectorConfig(
            bulkExtractionThreshold: 100,
            crossProjectThreshold: 5,
            exportPatternThreshold: 50,
            burnoutThresholdSeconds: 57600,
            knowledgeHoardingMinQueries: 10
        )
        let detector = SecurityPatternDetector(config: config)

        // Normal usage: 2 queries
        await detector.record(SecurityEventRecord(userId: "bob", toolName: "search"))
        await detector.record(SecurityEventRecord(userId: "bob", toolName: "write"))

        let incidents = await detector.detect()
        // Only off-hours might trigger depending on time of day
        let nonOffHours = incidents.filter { $0.anomaly != .offHoursAccess }
        #expect(nonOffHours.isEmpty)
    }

    @Test("does not duplicate incidents on re-detect")
    func noDuplicateIncidents() async {
        let config = SecurityDetectorConfig(
            bulkExtractionThreshold: 3,
            bulkExtractionWindowSeconds: 300
        )
        let detector = SecurityPatternDetector(config: config)

        for i in 0..<5 {
            await detector.record(SecurityEventRecord(
                userId: "bob",
                toolName: "search-\(i)"
            ))
        }

        let first = await detector.detect()
        let second = await detector.detect()

        let bulkFirst = first.filter { $0.anomaly == .bulkExtraction }
        let bulkSecond = second.filter { $0.anomaly == .bulkExtraction }

        #expect(bulkFirst.count == 1)
        #expect(bulkSecond.count == 0) // Already reported
    }

    @Test("window trimming respects max size")
    func windowTrimming() async {
        let config = SecurityDetectorConfig(maxWindowSize: 5)
        let detector = SecurityPatternDetector(config: config)

        for i in 0..<10 {
            await detector.record(SecurityEventRecord(
                userId: "bob",
                toolName: "tool-\(i)"
            ))
        }

        #expect(await detector.windowSize() == 5)
    }

    @Test("reset clears window and incidents")
    func reset() async {
        let detector = SecurityPatternDetector(config: .testing)
        await detector.record(SecurityEventRecord(userId: "bob", toolName: "search"))
        _ = await detector.detect()

        await detector.reset()
        #expect(await detector.windowSize() == 0)
        #expect(await detector.allIncidents().isEmpty)
    }

    @Test("incident callback fires on detection")
    func incidentCallback() async {
        let config = SecurityDetectorConfig(bulkExtractionThreshold: 3)
        let detector = SecurityPatternDetector(config: config)

        let tracker = CallbackTracker()
        await detector.setOnIncidentDetected { _ in
            await tracker.fire()
        }

        for i in 0..<5 {
            await detector.record(SecurityEventRecord(
                userId: "bob",
                toolName: "search-\(i)"
            ))
        }

        _ = await detector.detect()
        #expect(await tracker.fired)
    }
}

// MARK: - BudgetClock Tests

@Suite("BudgetClock")
struct BudgetClockTests {

    @Test("SystemBudgetClock returns current time")
    func systemClock() {
        let clock = SystemBudgetClock()
        let now = clock.now()
        let diff = abs(now.timeIntervalSinceNow)
        #expect(diff < 1.0)
    }

    @Test("SystemBudgetClock period starts are in the past")
    func periodStarts() {
        let clock = SystemBudgetClock()
        let now = Date()

        for period in BudgetPeriod.allCases {
            let start = clock.periodStart(for: period)
            #expect(start <= now)
        }
    }

    @Test("FixedBudgetClock returns fixed values")
    func fixedClock() {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let periodStart = Date(timeIntervalSince1970: 900_000)
        let clock = FixedBudgetClock(
            now: fixedDate,
            periodStarts: [.daily: periodStart]
        )

        #expect(clock.now() == fixedDate)
        #expect(clock.periodStart(for: .daily) == periodStart)
    }

    @Test("FixedBudgetClock uses fallback for missing period")
    func fixedClockFallback() {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let clock = FixedBudgetClock(now: fixedDate)

        let start = clock.periodStart(for: .weekly)
        #expect(start == fixedDate.addingTimeInterval(-86400))
    }
}

// MARK: - BudgetPeriod Tests

@Suite("BudgetPeriod")
struct BudgetPeriodTests {

    @Test("all cases are present")
    func allCases() {
        #expect(BudgetPeriod.allCases.count == 3)
        #expect(BudgetPeriod.allCases.contains(.daily))
        #expect(BudgetPeriod.allCases.contains(.weekly))
        #expect(BudgetPeriod.allCases.contains(.monthly))
    }

    @Test("raw values are correct")
    func rawValues() {
        #expect(BudgetPeriod.daily.rawValue == "daily")
        #expect(BudgetPeriod.weekly.rawValue == "weekly")
        #expect(BudgetPeriod.monthly.rawValue == "monthly")
    }
}
