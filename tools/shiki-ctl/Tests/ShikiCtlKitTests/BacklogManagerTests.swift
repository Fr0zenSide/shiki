import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Mock BackendClient for Backlog

/// Minimal mock that tracks calls and returns pre-configured responses.
actor MockBacklogBackendClient: BackendClientProtocol {
    var createdItems: [BacklogItem] = []
    var enrichedIds: [String] = []
    var killedIds: [(id: String, reason: String)] = []
    var updatedItems: [(id: String, status: BacklogItem.Status?)] = []
    var reorderedItems: [(id: String, sortOrder: Int)] = []
    var countResult: Int = 0
    var listResult: [BacklogItem] = []
    var enrichResult: BacklogItem?
    var killResult: BacklogItem?
    var updateResult: BacklogItem?
    var createResult: BacklogItem?

    // Backlog implementations
    func listBacklogItems(status: BacklogItem.Status?, companyId: String?, tags: [String]?, sort: BacklogSort?) async throws -> [BacklogItem] {
        listResult
    }

    func getBacklogItem(id: String) async throws -> BacklogItem {
        if let item = listResult.first(where: { $0.id == id }) { return item }
        throw BackendError.httpError(statusCode: 404, body: "Not found")
    }

    func createBacklogItem(title: String, description: String?, companyId: String?, sourceType: BacklogItem.SourceType, sourceRef: String?, priority: Int?, tags: [String]) async throws -> BacklogItem {
        let item = createResult ?? BacklogItem(
            id: "new-\(createdItems.count + 1)",
            companyId: companyId,
            title: title,
            sourceType: sourceType,
            status: .raw,
            priority: priority ?? 50,
            tags: tags
        )
        createdItems.append(item)
        return item
    }

    func updateBacklogItem(id: String, status: BacklogItem.Status?, priority: Int?, sortOrder: Int?, tags: [String]?, description: String?) async throws -> BacklogItem {
        updatedItems.append((id: id, status: status))
        return updateResult ?? BacklogItem(id: id, title: "Updated", status: status ?? .raw)
    }

    func enrichBacklogItem(id: String, notes: String, tags: [String]?, description: String?) async throws -> BacklogItem {
        enrichedIds.append(id)
        return enrichResult ?? BacklogItem(id: id, title: "Enriched", status: .enriched, enrichmentNotes: notes)
    }

    func killBacklogItem(id: String, reason: String) async throws -> BacklogItem {
        killedIds.append((id: id, reason: reason))
        return killResult ?? BacklogItem(id: id, title: "Killed", status: .killed, killReason: reason)
    }

    func reorderBacklogItems(_ items: [(id: String, sortOrder: Int)]) async throws {
        reorderedItems = items
    }

    func getBacklogCount(status: BacklogItem.Status?, companyId: String?) async throws -> Int {
        countResult
    }

    // Required protocol stubs (unused by BacklogManager)
    func healthCheck() async throws -> Bool { true }
    func getStatus() async throws -> OrchestratorStatus { fatalError("unused") }
    func getStaleCompanies(thresholdMinutes: Int) async throws -> [Company] { [] }
    func getReadyCompanies() async throws -> [Company] { [] }
    func getDispatcherQueue() async throws -> [DispatcherTask] { [] }
    func getDailyReport(date: String?) async throws -> DailyReport { fatalError("unused") }
    func sendHeartbeat(companyId: String, sessionId: String) async throws -> HeartbeatResponse { fatalError("unused") }
    func getCompanies(status: String?) async throws -> [Company] { [] }
    func getPendingDecisions() async throws -> [Decision] { [] }
    func answerDecision(id: String, answer: String, answeredBy: String) async throws -> Decision { fatalError("unused") }
    func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript { fatalError("unused") }
    func getSessionTranscripts(companySlug: String?, taskId: String?, limit: Int) async throws -> [SessionTranscript] { [] }
    func getSessionTranscript(id: String) async throws -> SessionTranscript { fatalError("unused") }
    func getBoardOverview() async throws -> [BoardEntry] { [] }
    func shutdown() async throws {}
}

// MARK: - Tests

@Suite("BacklogManager — curation lifecycle")
struct BacklogManagerTests {

    // MARK: - BR-F-01: Every item starts raw

    @Test("BR-F-01: add() creates item in raw status")
    func addCreatesRawItem() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        let item = try await manager.add(title: "New feature idea")
        #expect(item.status == .raw)
        let created = await mock.createdItems
        #expect(created.count == 1)
        #expect(created[0].title == "New feature idea")
    }

    @Test("BR-F-01: add() with all parameters passes through")
    func addWithParameters() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        let item = try await manager.add(
            title: "Maya animation system",
            companyId: "comp-1",
            sourceType: .conversation,
            priority: 10,
            tags: ["perf", "ux"]
        )

        #expect(item.status == .raw)
        let created = await mock.createdItems
        #expect(created[0].companyId == "comp-1")
        #expect(created[0].sourceType == .conversation)
        #expect(created[0].tags == ["perf", "ux"])
    }

    // MARK: - BR-F-02: Enrichment requires context

    @Test("BR-F-02: enrich() with notes transitions to enriched")
    func enrichWithNotes() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        let result = try await manager.enrich(id: "item-1", notes: "Added link to RFC")
        #expect(result.status == .enriched)
        let enriched = await mock.enrichedIds
        #expect(enriched == ["item-1"])
    }

    @Test("BR-F-02: enrich() with empty notes throws enrichmentRequired")
    func enrichEmptyNotesThrows() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        await #expect(throws: BacklogError.self) {
            try await manager.enrich(id: "item-1", notes: "   ")
        }
    }

    @Test("BR-F-02: enrich() with only tags succeeds")
    func enrichWithTagsOnly() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        // Notes is empty but tags provided
        let result = try await manager.enrich(id: "item-2", notes: "", tags: ["perf"])
        #expect(result.status == .enriched)
    }

    // MARK: - BR-F-12: Kill from any state

    @Test("BR-F-12: kill() archives item with reason")
    func killWithReason() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        let result = try await manager.kill(id: "item-1", reason: "Duplicate of #42")
        #expect(result.status == .killed)
        #expect(result.killReason == "Duplicate of #42")
        let killed = await mock.killedIds
        #expect(killed.count == 1)
        #expect(killed[0].reason == "Duplicate of #42")
    }

    @Test("BR-F-12: kill() without reason throws")
    func killWithoutReasonThrows() async throws {
        let mock = MockBacklogBackendClient()
        let manager = BacklogManager(client: mock)

        await #expect(throws: BacklogError.self) {
            try await manager.kill(id: "item-1", reason: "  ")
        }
    }

    // MARK: - Defer / Un-defer (BR-F-13)

    @Test("BR-F-13: defer() transitions to deferred status")
    func deferItem() async throws {
        let mock = MockBacklogBackendClient()
        await mock.setUpdateResult(BacklogItem(id: "item-1", title: "Deferred", status: .deferred))
        let manager = BacklogManager(client: mock)

        let result = try await manager.defer(id: "item-1")
        #expect(result.status == .deferred)
        let updated = await mock.updatedItems
        #expect(updated[0].status == .deferred)
    }

    // MARK: - State Machine Validation

    @Test("State machine: killed is terminal — no valid transitions")
    func killedIsTerminal() {
        let transitions = BacklogItem.Status.killed.validTransitions
        #expect(transitions.isEmpty)
    }

    @Test("State machine: raw allows enriched, ready, deferred, killed")
    func rawTransitions() {
        let transitions = BacklogItem.Status.raw.validTransitions
        #expect(transitions.contains(.enriched))
        #expect(transitions.contains(.ready))
        #expect(transitions.contains(.deferred))
        #expect(transitions.contains(.killed))
        #expect(!transitions.contains(.raw))
    }

    @Test("State machine: enriched does not allow back to raw")
    func enrichedNoBacktrack() {
        let transitions = BacklogItem.Status.enriched.validTransitions
        #expect(!transitions.contains(.raw))
        #expect(transitions.contains(.ready))
        #expect(transitions.contains(.killed))
    }

    @Test("State machine: canTransition validates correctly")
    func canTransitionValidation() {
        #expect(BacklogItem.Status.raw.canTransition(to: .enriched))
        #expect(BacklogItem.Status.raw.canTransition(to: .killed))
        #expect(!BacklogItem.Status.killed.canTransition(to: .raw))
        #expect(!BacklogItem.Status.killed.canTransition(to: .enriched))
        #expect(!BacklogItem.Status.enriched.canTransition(to: .raw))
        #expect(BacklogItem.Status.ready.canTransition(to: .killed))
        #expect(BacklogItem.Status.deferred.canTransition(to: .enriched))
    }
}

// MARK: - Mock helpers

extension MockBacklogBackendClient {
    func setUpdateResult(_ item: BacklogItem) {
        updateResult = item
    }
}
