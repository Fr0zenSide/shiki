import Foundation
import Testing
@testable import ShikkiKit

// MARK: - AuditLoggerTests

@Suite("AuditLogger — SOC 2 / ISO 27001 audit trail")
struct AuditLoggerTests {

    // MARK: - Helpers

    private func makeLogger(
        store: InMemoryAuditStore = InMemoryAuditStore(),
        detector: SecurityPatternDetector? = nil,
        budgetACL: BudgetACL? = nil
    ) -> AuditLogger {
        AuditLogger(store: store, securityDetector: detector, budgetACL: budgetACL)
    }

    // MARK: - Log Entry Creation

    @Test("logToolCall creates an AuditEvent with correct fields")
    func logToolCall_createsEvent() async throws {
        let store = InMemoryAuditStore()
        let logger = makeLogger(store: store)

        let (event, _) = try await logger.logToolCall(
            userId: "alice",
            toolName: "memory_search",
            parameters: ["query": "test"],
            projectSlug: "shikki",
            workspaceId: "ws1",
            context: "searching for test data",
            sessionId: "session-123"
        )

        #expect(event.userId == "alice")
        #expect(event.toolName == "memory_search")
        #expect(event.parameters == ["query": "test"])
        #expect(event.projectSlug == "shikki")
        #expect(event.workspaceId == "ws1")
        #expect(event.context == "searching for test data")
        #expect(event.sessionId == "session-123")
    }

    @Test("logToolCall generates a UUID for the event")
    func logToolCall_generatesId() async throws {
        let logger = makeLogger()
        let (event, _) = try await logger.logToolCall(userId: "alice", toolName: "search")
        #expect(event.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test("logToolCall records timestamp close to now")
    func logToolCall_timestampIsRecent() async throws {
        let logger = makeLogger()
        let before = Date()
        let (event, _) = try await logger.logToolCall(userId: "alice", toolName: "search")
        let after = Date()

        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    @Test("logToolCall defaults outcome to success")
    func logToolCall_defaultsToSuccess() async throws {
        let logger = makeLogger()
        let (event, _) = try await logger.logToolCall(userId: "alice", toolName: "search")
        #expect(event.outcome == .success)
    }

    @Test("logToolCall respects custom outcome")
    func logToolCall_customOutcome() async throws {
        let logger = makeLogger()
        let (event, _) = try await logger.logToolCall(
            userId: "alice",
            toolName: "search",
            outcome: .failure(reason: "timeout")
        )
        #expect(event.outcome == .failure(reason: "timeout"))
    }

    @Test("logToolCall supports parentEventId for chaining")
    func logToolCall_parentEventId() async throws {
        let logger = makeLogger()
        let parentId = UUID()
        let (event, _) = try await logger.logToolCall(
            userId: "alice",
            toolName: "search",
            parentEventId: parentId
        )
        #expect(event.parentEventId == parentId)
    }

    // MARK: - Log Persistence

    @Test("events are persisted to the store")
    func logToolCall_persistsToStore() async throws {
        let store = InMemoryAuditStore()
        let logger = makeLogger(store: store)

        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "bob", toolName: "upsert")

        let count = await store.count()
        #expect(count == 2)
    }

    @Test("eventCount returns total persisted events")
    func eventCount_returnsTotal() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "alice", toolName: "upsert")
        try await logger.logToolCall(userId: "alice", toolName: "delete")

        let count = await logger.eventCount()
        #expect(count == 3)
    }

    // MARK: - Log Filtering (Query)

    @Test("query filters by userId")
    func query_filtersByUserId() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "bob", toolName: "search")
        try await logger.logToolCall(userId: "alice", toolName: "upsert")

        let results = try await logger.query(AuditQuery(userId: "alice"))
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.userId == "alice" })
    }

    @Test("query filters by toolName")
    func query_filtersByToolName() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "alice", toolName: "upsert")
        try await logger.logToolCall(userId: "alice", toolName: "search")

        let results = try await logger.query(AuditQuery(toolName: "search"))
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.toolName == "search" })
    }

    @Test("query filters by projectSlug")
    func query_filtersByProject() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search", projectSlug: "shikki")
        try await logger.logToolCall(userId: "alice", toolName: "search", projectSlug: "maya")
        try await logger.logToolCall(userId: "alice", toolName: "search", projectSlug: "shikki")

        let results = try await logger.query(AuditQuery(projectSlug: "shikki"))
        #expect(results.count == 2)
    }

    @Test("query filters by workspaceId")
    func query_filtersByWorkspace() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search", workspaceId: "ws1")
        try await logger.logToolCall(userId: "alice", toolName: "search", workspaceId: "ws2")

        let results = try await logger.query(AuditQuery(workspaceId: "ws1"))
        #expect(results.count == 1)
    }

    @Test("query filters by date range (since/until)")
    func query_filtersByDateRange() async throws {
        let store = InMemoryAuditStore()
        let logger = makeLogger(store: store)

        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let twoDaysAgo = now.addingTimeInterval(-172800)

        // Manually create events with controlled timestamps
        try await store.append(AuditEvent(timestamp: twoDaysAgo, userId: "alice", toolName: "search"))
        try await store.append(AuditEvent(timestamp: yesterday, userId: "alice", toolName: "search"))
        try await store.append(AuditEvent(timestamp: now, userId: "alice", toolName: "search"))

        let sinceYesterday = AuditQuery(since: yesterday.addingTimeInterval(-1))
        let results = try await logger.query(sinceYesterday)
        #expect(results.count == 2)

        let onlyYesterday = AuditQuery(
            since: twoDaysAgo.addingTimeInterval(1),
            until: now.addingTimeInterval(-1)
        )
        let rangeResults = try await logger.query(onlyYesterday)
        #expect(rangeResults.count == 1)
    }

    @Test("query respects limit")
    func query_respectsLimit() async throws {
        let logger = makeLogger()
        for i in 0..<10 {
            try await logger.logToolCall(userId: "alice", toolName: "search-\(i)")
        }

        let results = try await logger.query(AuditQuery(limit: 3))
        #expect(results.count == 3)
    }

    @Test("query with no filters returns all (up to limit)")
    func query_noFiltersReturnsAll() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "bob", toolName: "upsert")

        let results = try await logger.query(AuditQuery())
        #expect(results.count == 2)
    }

    @Test("query results are sorted newest-first")
    func query_sortedNewestFirst() async throws {
        let store = InMemoryAuditStore()
        let logger = makeLogger(store: store)

        let now = Date()
        try await store.append(AuditEvent(timestamp: now.addingTimeInterval(-100), userId: "a", toolName: "t1"))
        try await store.append(AuditEvent(timestamp: now, userId: "a", toolName: "t2"))
        try await store.append(AuditEvent(timestamp: now.addingTimeInterval(-50), userId: "a", toolName: "t3"))

        let results = try await logger.query(AuditQuery())
        #expect(results.count == 3)
        #expect(results[0].toolName == "t2") // newest
        #expect(results[1].toolName == "t3") // middle
        #expect(results[2].toolName == "t1") // oldest
    }

    // MARK: - Security Detector Integration

    @Test("logToolCall feeds security detector when present")
    func logToolCall_feedsSecurityDetector() async throws {
        let detector = SecurityPatternDetector(config: .testing)
        let logger = makeLogger(detector: detector)

        try await logger.logToolCall(
            userId: "alice",
            toolName: "memory_search",
            projectSlug: "proj"
        )

        let windowSize = await detector.windowSize()
        #expect(windowSize == 1)
    }

    @Test("logToolCall marks memory reads for search/get/read tools")
    func logToolCall_marksMemoryReads() async throws {
        let detector = SecurityPatternDetector(config: .testing)
        let logger = makeLogger(detector: detector)

        // Log enough memory reads to trigger export pattern (threshold = 5)
        for i in 0..<6 {
            try await logger.logToolCall(
                userId: "exporter",
                toolName: "memory_search_\(i)",
                projectSlug: "secret"
            )
        }

        let incidents = await logger.detectSecurityAnomalies()
        // Should detect bulk extraction (6 >= 5 threshold) since all have same userId
        let bulkOrExport = incidents.filter {
            $0.anomaly == .bulkExtraction || $0.anomaly == .exportPattern
        }
        #expect(!bulkOrExport.isEmpty)
    }

    @Test("detectSecurityAnomalies returns empty when no detector configured")
    func detectSecurityAnomalies_emptyWithoutDetector() async {
        let logger = makeLogger(detector: nil)
        let incidents = await logger.detectSecurityAnomalies()
        #expect(incidents.isEmpty)
    }

    // MARK: - Budget ACL Integration

    @Test("logToolCall checks budget when ACL and cost provided")
    func logToolCall_checksBudget() async throws {
        let clock = FixedBudgetClock(
            now: Date(),
            periodStarts: [
                .daily: Date().addingTimeInterval(-3600),
                .weekly: Date().addingTimeInterval(-3600),
                .monthly: Date().addingTimeInterval(-3600),
            ]
        )
        let acl = BudgetACL(clock: clock)
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))

        let logger = makeLogger(budgetACL: acl)
        let (_, budgetResult) = try await logger.logToolCall(
            userId: "alice",
            toolName: "search",
            estimatedCostUsd: 3.0
        )

        if case .allowed(let remaining) = budgetResult {
            #expect(remaining == 7.0)
        } else {
            Issue.record("Expected .allowed, got \(String(describing: budgetResult))")
        }
    }

    @Test("logToolCall marks outcome as blocked when budget exceeded")
    func logToolCall_blockedOutcomeOnOverBudget() async throws {
        let clock = FixedBudgetClock(
            now: Date(),
            periodStarts: [
                .daily: Date().addingTimeInterval(-3600),
                .weekly: Date().addingTimeInterval(-3600),
                .monthly: Date().addingTimeInterval(-3600),
            ]
        )
        let acl = BudgetACL(clock: clock)
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 5.0))
        await acl.recordSpend(userId: "alice", toolName: "prev", costUsd: 4.0)

        let logger = makeLogger(budgetACL: acl)
        let (event, budgetResult) = try await logger.logToolCall(
            userId: "alice",
            toolName: "search",
            estimatedCostUsd: 3.0
        )

        if case .blocked = budgetResult {
            // Expected
        } else {
            Issue.record("Expected .blocked, got \(String(describing: budgetResult))")
        }

        if case .blocked = event.outcome {
            // Expected — outcome should reflect the budget block
        } else {
            Issue.record("Expected event outcome .blocked, got \(event.outcome)")
        }
    }

    @Test("logToolCall records spend only when allowed")
    func logToolCall_recordsSpendOnlyWhenAllowed() async throws {
        let clock = FixedBudgetClock(
            now: Date(),
            periodStarts: [
                .daily: Date().addingTimeInterval(-3600),
                .weekly: Date().addingTimeInterval(-3600),
                .monthly: Date().addingTimeInterval(-3600),
            ]
        )
        let acl = BudgetACL(clock: clock)
        await acl.setPolicy(BudgetPolicy(userId: "alice", period: .daily, capUsd: 10.0))

        let logger = makeLogger(budgetACL: acl)

        // First call should be allowed and recorded
        try await logger.logToolCall(userId: "alice", toolName: "search", estimatedCostUsd: 3.0)
        let spentAfterFirst = await acl.spentInPeriod(userId: "alice", period: .daily)
        #expect(spentAfterFirst == 3.0)

        // Spend most of the remaining budget
        await acl.recordSpend(userId: "alice", toolName: "manual", costUsd: 6.5)

        // This call should be blocked and NOT record additional spend
        try await logger.logToolCall(userId: "alice", toolName: "search", estimatedCostUsd: 5.0)
        let spentAfterBlocked = await acl.spentInPeriod(userId: "alice", period: .daily)
        #expect(spentAfterBlocked == 9.5) // 3.0 + 6.5, not 14.5
    }

    @Test("logToolCall returns nil budget result when no cost provided")
    func logToolCall_nilBudgetWithoutCost() async throws {
        let clock = FixedBudgetClock(now: Date(), periodStarts: [:])
        let acl = BudgetACL(clock: clock)
        let logger = makeLogger(budgetACL: acl)

        let (_, budgetResult) = try await logger.logToolCall(
            userId: "alice",
            toolName: "search"
        )
        #expect(budgetResult == nil)
    }

    // MARK: - Report Generation

    @Test("generateReport produces correct aggregate data")
    func generateReport_producesAggregates() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "bob", toolName: "upsert")
        try await logger.logToolCall(
            userId: "alice",
            toolName: "delete",
            outcome: .failure(reason: "not found")
        )

        let report = try await logger.generateReport(query: AuditQuery())

        #expect(report.totalCount == 3)
        #expect(report.uniqueUsers == Set(["alice", "bob"]))
        #expect(report.uniqueTools == Set(["search", "upsert", "delete"]))
        #expect(report.outcomeCounts["success"] == 2)
        #expect(report.outcomeCounts["failure"] == 1)
    }

    @Test("generateReport respects query filter")
    func generateReport_respectsFilter() async throws {
        let logger = makeLogger()
        try await logger.logToolCall(userId: "alice", toolName: "search")
        try await logger.logToolCall(userId: "bob", toolName: "search")

        let report = try await logger.generateReport(query: AuditQuery(userId: "alice"))
        #expect(report.totalCount == 1)
        #expect(report.uniqueUsers == Set(["alice"]))
    }

    // MARK: - AuditReportFormatter — Text

    @Test("renderText includes report header with total count")
    func renderText_includesHeader() async throws {
        let events = [
            AuditEvent(userId: "alice", toolName: "search"),
            AuditEvent(userId: "bob", toolName: "upsert"),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)
        let text = AuditReportFormatter.renderText(report)

        #expect(text.contains("Audit Report"))
        #expect(text.contains("Total events: 2"))
        #expect(text.contains("alice"))
        #expect(text.contains("bob"))
    }

    @Test("renderText shows outcome labels")
    func renderText_showsOutcomes() {
        let events = [
            AuditEvent(userId: "alice", toolName: "search", outcome: .success),
            AuditEvent(userId: "alice", toolName: "delete", outcome: .failure(reason: "not found")),
            AuditEvent(userId: "alice", toolName: "upsert", outcome: .blocked(reason: "budget")),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)
        let text = AuditReportFormatter.renderText(report)

        #expect(text.contains("OK"))
        #expect(text.contains("FAIL: not found"))
        #expect(text.contains("BLOCKED: budget"))
    }

    @Test("renderText truncates at 50 events with overflow message")
    func renderText_truncatesAt50() {
        let events = (0..<60).map { i in
            AuditEvent(userId: "alice", toolName: "tool-\(i)")
        }
        let report = AuditReport(query: AuditQuery(), events: events)
        let text = AuditReportFormatter.renderText(report)

        #expect(text.contains("and 10 more"))
    }

    // MARK: - AuditReportFormatter — JSON

    @Test("renderJSON produces valid JSON with all fields")
    func renderJSON_producesValidJSON() throws {
        let events = [
            AuditEvent(userId: "alice", toolName: "search"),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)
        let json = try AuditReportFormatter.renderJSON(report)

        #expect(json.contains("\"totalCount\""))
        #expect(json.contains("\"uniqueUsers\""))
        #expect(json.contains("\"uniqueTools\""))
        #expect(json.contains("alice"))

        // Verify it's actually valid JSON
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any])
    }

    // MARK: - InMemoryAuditStore

    @Test("InMemoryAuditStore append and count work correctly")
    func inMemoryStore_appendAndCount() async throws {
        let store = InMemoryAuditStore()
        try await store.append(AuditEvent(userId: "alice", toolName: "search"))
        try await store.append(AuditEvent(userId: "bob", toolName: "upsert"))
        let count = await store.count()
        #expect(count == 2)
    }

    @Test("InMemoryAuditStore clear removes all events")
    func inMemoryStore_clearRemovesAll() async throws {
        let store = InMemoryAuditStore()
        try await store.append(AuditEvent(userId: "alice", toolName: "search"))
        await store.clear()
        let count = await store.count()
        #expect(count == 0)
    }

    @Test("InMemoryAuditStore query matches filters correctly")
    func inMemoryStore_queryFilters() async throws {
        let store = InMemoryAuditStore()
        try await store.append(AuditEvent(userId: "alice", toolName: "search", projectSlug: "proj-a"))
        try await store.append(AuditEvent(userId: "bob", toolName: "search", projectSlug: "proj-b"))
        try await store.append(AuditEvent(userId: "alice", toolName: "upsert", projectSlug: "proj-a"))

        let results = try await store.query(AuditQuery(userId: "alice", projectSlug: "proj-a"))
        #expect(results.count == 2)
    }

    // MARK: - AuditQuery.matches

    @Test("AuditQuery matches filters correctly")
    func auditQuery_matchesFilters() {
        let event = AuditEvent(
            userId: "alice",
            toolName: "search",
            projectSlug: "shikki",
            workspaceId: "ws1"
        )

        #expect(AuditQuery(userId: "alice").matches(event) == true)
        #expect(AuditQuery(userId: "bob").matches(event) == false)
        #expect(AuditQuery(toolName: "search").matches(event) == true)
        #expect(AuditQuery(toolName: "upsert").matches(event) == false)
        #expect(AuditQuery(projectSlug: "shikki").matches(event) == true)
        #expect(AuditQuery(projectSlug: "maya").matches(event) == false)
        #expect(AuditQuery(workspaceId: "ws1").matches(event) == true)
        #expect(AuditQuery(workspaceId: "ws2").matches(event) == false)
    }

    @Test("AuditQuery matches with date range")
    func auditQuery_matchesDateRange() {
        let now = Date()
        let event = AuditEvent(timestamp: now, userId: "alice", toolName: "search")

        let queryBefore = AuditQuery(since: now.addingTimeInterval(100))
        #expect(queryBefore.matches(event) == false)

        let queryAfter = AuditQuery(until: now.addingTimeInterval(-100))
        #expect(queryAfter.matches(event) == false)

        let queryInRange = AuditQuery(
            since: now.addingTimeInterval(-10),
            until: now.addingTimeInterval(10)
        )
        #expect(queryInRange.matches(event) == true)
    }

    @Test("AuditQuery with no filters matches everything")
    func auditQuery_noFiltersMatchesAll() {
        let event = AuditEvent(userId: "anyone", toolName: "anything")
        #expect(AuditQuery().matches(event) == true)
    }

    // MARK: - AuditEvent Model

    @Test("AuditEvent defaults are correct")
    func auditEvent_defaults() {
        let event = AuditEvent(userId: "test", toolName: "search")
        #expect(event.userId == "test")
        #expect(event.toolName == "search")
        #expect(event.parameters.isEmpty)
        #expect(event.projectSlug == nil)
        #expect(event.workspaceId == nil)
        #expect(event.context == nil)
        #expect(event.sessionId == nil)
        #expect(event.parentEventId == nil)
        #expect(event.outcome == .success)
    }

    // MARK: - AuditOutcome

    @Test("AuditOutcome equality works correctly")
    func auditOutcome_equality() {
        #expect(AuditOutcome.success == AuditOutcome.success)
        #expect(AuditOutcome.failure(reason: "a") == AuditOutcome.failure(reason: "a"))
        #expect(AuditOutcome.failure(reason: "a") != AuditOutcome.failure(reason: "b"))
        #expect(AuditOutcome.blocked(reason: "x") == AuditOutcome.blocked(reason: "x"))
        #expect(AuditOutcome.success != AuditOutcome.failure(reason: "a"))
    }

    // MARK: - AuditReport Model

    @Test("AuditReport uniqueUsers and uniqueTools are correct")
    func auditReport_aggregates() {
        let events = [
            AuditEvent(userId: "alice", toolName: "search"),
            AuditEvent(userId: "bob", toolName: "search"),
            AuditEvent(userId: "alice", toolName: "upsert"),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)

        #expect(report.uniqueUsers == Set(["alice", "bob"]))
        #expect(report.uniqueTools == Set(["search", "upsert"]))
        #expect(report.totalCount == 3)
    }

    @Test("AuditReport outcomeCounts groups by outcome type")
    func auditReport_outcomeCounts() {
        let events = [
            AuditEvent(userId: "a", toolName: "t", outcome: .success),
            AuditEvent(userId: "a", toolName: "t", outcome: .success),
            AuditEvent(userId: "a", toolName: "t", outcome: .failure(reason: "err")),
            AuditEvent(userId: "a", toolName: "t", outcome: .blocked(reason: "budget")),
        ]
        let report = AuditReport(query: AuditQuery(), events: events)

        #expect(report.outcomeCounts["success"] == 2)
        #expect(report.outcomeCounts["failure"] == 1)
        #expect(report.outcomeCounts["blocked"] == 1)
    }
}
