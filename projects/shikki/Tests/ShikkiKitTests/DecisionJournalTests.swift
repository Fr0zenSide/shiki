import Foundation
import Testing
@testable import ShikkiKit

// MARK: - DecisionEvent Model Tests

@Suite("DecisionEvent — Model")
struct DecisionEventModelTests {

    @Test("DecisionEvent initializes with all fields")
    func initializesCorrectly() {
        let parentId = UUID()
        let decision = DecisionEvent(
            sessionId: "maya:wave3",
            agentPersona: "implement",
            companySlug: "maya",
            category: .architecture,
            question: "Actor or class for registry?",
            choice: "Actor",
            rationale: "Thread-safe by default, Swift 6 aligned",
            alternatives: ["Class + locks", "Struct + queue"],
            impact: .architecture,
            confidence: 0.95,
            parentDecisionId: parentId,
            tags: ["concurrency", "swift6"]
        )

        #expect(decision.sessionId == "maya:wave3")
        #expect(decision.category == .architecture)
        #expect(decision.choice == "Actor")
        #expect(decision.alternatives.count == 2)
        #expect(decision.confidence == 0.95)
        #expect(decision.parentDecisionId == parentId)
        #expect(decision.tags.contains("swift6"))
    }

    @Test("Confidence clamped to 0.0-1.0 range")
    func confidenceClamped() {
        let over = DecisionEvent(
            sessionId: "test", category: .implementation,
            question: "q", choice: "c", rationale: "r",
            impact: .implementation, confidence: 1.5
        )
        #expect(over.confidence == 1.0)

        let under = DecisionEvent(
            sessionId: "test", category: .implementation,
            question: "q", choice: "c", rationale: "r",
            impact: .implementation, confidence: -0.5
        )
        #expect(under.confidence == 0.0)
    }

    @Test("DecisionEvent converts to ShikkiEvent for EventBus")
    func convertsToShikkiEvent() {
        let decision = DecisionEvent(
            sessionId: "maya:wave3",
            agentPersona: "implement",
            companySlug: "maya",
            category: .architecture,
            question: "Actor or class?",
            choice: "Actor",
            rationale: "Thread-safe",
            impact: .architecture,
            tags: ["concurrency"]
        )

        let event = decision.toShikkiEvent()

        #expect(event.type == .architectureChoice)
        #expect(event.payload["question"]?.stringValue == "Actor or class?")
        #expect(event.payload["choice"]?.stringValue == "Actor")
        #expect(event.metadata?.tags?.contains("concurrency") == true)
    }

    @Test("Trade-off category maps to tradeOffEvaluated event type")
    func tradeOffEventType() {
        let decision = DecisionEvent(
            sessionId: "test", category: .tradeOff,
            question: "q", choice: "c", rationale: "r",
            impact: .implementation
        )
        let event = decision.toShikkiEvent()
        #expect(event.type == .tradeOffEvaluated)
    }

    @Test("Implementation category maps to decisionMade event type")
    func implementationEventType() {
        let decision = DecisionEvent(
            sessionId: "test", category: .implementation,
            question: "q", choice: "c", rationale: "r",
            impact: .implementation
        )
        let event = decision.toShikkiEvent()
        #expect(event.type == .decisionMade)
    }

    @Test("DecisionEvent is Codable round-trip")
    func codableRoundTrip() throws {
        let original = DecisionEvent(
            sessionId: "test-session",
            agentPersona: "implement",
            companySlug: "wabisabi",
            category: .tradeOff,
            question: "SQLite or JSONL?",
            choice: "JSONL",
            rationale: "Append-only, simpler",
            alternatives: ["SQLite", "Plist"],
            impact: .architecture,
            confidence: 0.85,
            tags: ["persistence"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DecisionEvent.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.category == original.category)
        #expect(decoded.question == original.question)
        #expect(decoded.choice == original.choice)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.alternatives == original.alternatives)
    }
}

// MARK: - DecisionQuery Tests

@Suite("DecisionQuery — Filtering")
struct DecisionQueryTests {

    @Test("Empty query matches all decisions")
    func emptyQueryMatchesAll() {
        let query = DecisionQuery.all
        let decision = DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        #expect(query.matches(decision))
    }

    @Test("Session filter narrows results")
    func sessionFilter() {
        let query = DecisionQuery(sessionId: "maya:wave3")
        let match = DecisionEvent(
            sessionId: "maya:wave3", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        let noMatch = DecisionEvent(
            sessionId: "wabisabi:fix", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        #expect(query.matches(match))
        #expect(!query.matches(noMatch))
    }

    @Test("Category filter narrows results")
    func categoryFilter() {
        let query = DecisionQuery(category: .tradeOff)
        let match = DecisionEvent(
            sessionId: "test", category: .tradeOff,
            question: "q", choice: "c", rationale: "r",
            impact: .implementation
        )
        let noMatch = DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        #expect(query.matches(match))
        #expect(!query.matches(noMatch))
    }

    @Test("Tag filter requires all specified tags")
    func tagFilter() {
        let query = DecisionQuery(tags: Set(["swift6", "concurrency"]))
        let match = DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture, tags: ["swift6", "concurrency", "extra"]
        )
        let partial = DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture, tags: ["swift6"]
        )
        #expect(query.matches(match))
        #expect(!query.matches(partial))
    }

    @Test("Date range filter")
    func dateRangeFilter() {
        let now = Date()
        let query = DecisionQuery(
            since: now.addingTimeInterval(-3600),
            until: now
        )
        let inRange = DecisionEvent(
            timestamp: now.addingTimeInterval(-1800),
            sessionId: "test", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        let outOfRange = DecisionEvent(
            timestamp: now.addingTimeInterval(-7200),
            sessionId: "test", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        #expect(query.matches(inRange))
        #expect(!query.matches(outOfRange))
    }

    @Test("Composite query: session + category + impact")
    func compositeQuery() {
        let query = DecisionQuery(
            sessionId: "maya:wave3",
            category: .architecture,
            impact: .architecture
        )
        let match = DecisionEvent(
            sessionId: "maya:wave3", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        let wrongSession = DecisionEvent(
            sessionId: "other", category: .architecture,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        let wrongCategory = DecisionEvent(
            sessionId: "maya:wave3", category: .process,
            question: "q", choice: "c", rationale: "r",
            impact: .architecture
        )
        #expect(query.matches(match))
        #expect(!query.matches(wrongSession))
        #expect(!query.matches(wrongCategory))
    }
}

// MARK: - DecisionChain Tests

@Suite("DecisionChain — Traceability")
struct DecisionChainTests {

    @Test("Chain depth is 1 for root-only")
    func rootOnlyDepth() {
        let root = makeDecision(question: "Root")
        let chain = DecisionChain(root: root, children: [])
        #expect(chain.depth == 1)
    }

    @Test("Chain depth reflects children count")
    func chainDepth() {
        let root = makeDecision(question: "Root")
        let child1 = makeDecision(question: "Child 1", parentId: root.id)
        let child2 = makeDecision(question: "Child 2", parentId: root.id)
        let chain = DecisionChain(root: root, children: [child1, child2])
        #expect(chain.depth == 3)
    }

    @Test("allDecisions returns root first, then children sorted by timestamp")
    func allDecisionsSorted() {
        let now = Date()
        let root = DecisionEvent(
            timestamp: now.addingTimeInterval(-100),
            sessionId: "test", category: .architecture,
            question: "Root", choice: "c", rationale: "r",
            impact: .architecture
        )
        let laterChild = DecisionEvent(
            timestamp: now,
            sessionId: "test", category: .implementation,
            question: "Later", choice: "c", rationale: "r",
            impact: .implementation, parentDecisionId: root.id
        )
        let earlierChild = DecisionEvent(
            timestamp: now.addingTimeInterval(-50),
            sessionId: "test", category: .implementation,
            question: "Earlier", choice: "c", rationale: "r",
            impact: .implementation, parentDecisionId: root.id
        )
        let chain = DecisionChain(root: root, children: [laterChild, earlierChild])

        let all = chain.allDecisions
        #expect(all[0].question == "Root")
        #expect(all[1].question == "Earlier")
        #expect(all[2].question == "Later")
    }

    private func makeDecision(question: String, parentId: UUID? = nil) -> DecisionEvent {
        DecisionEvent(
            sessionId: "test", category: .architecture,
            question: question, choice: "c", rationale: "r",
            impact: .architecture, parentDecisionId: parentId
        )
    }
}

// MARK: - DecisionJournal Persistence Tests

@Suite("DecisionJournal — JSONL Persistence")
struct DecisionJournalPersistenceTests {

    @Test("Record and load decisions for a session")
    func recordAndLoad() async throws {
        let journal = makeJournal()
        let decision = makeDecision(sessionId: "sess-1", question: "Use JSONL?")

        try await journal.record(decision)
        let loaded = try await journal.loadDecisions(sessionId: "sess-1")

        #expect(loaded.count == 1)
        #expect(loaded[0].question == "Use JSONL?")
        #expect(loaded[0].id == decision.id)
    }

    @Test("Multiple decisions append to same session file")
    func multipleAppend() async throws {
        let journal = makeJournal()

        try await journal.record(makeDecision(sessionId: "sess-1", question: "Q1"))
        try await journal.record(makeDecision(sessionId: "sess-1", question: "Q2"))
        try await journal.record(makeDecision(sessionId: "sess-1", question: "Q3"))

        let loaded = try await journal.loadDecisions(sessionId: "sess-1")
        #expect(loaded.count == 3)
    }

    @Test("Separate sessions have separate files")
    func separateSessions() async throws {
        let journal = makeJournal()

        try await journal.record(makeDecision(sessionId: "sess-a", question: "QA"))
        try await journal.record(makeDecision(sessionId: "sess-b", question: "QB"))

        let loadedA = try await journal.loadDecisions(sessionId: "sess-a")
        let loadedB = try await journal.loadDecisions(sessionId: "sess-b")

        #expect(loadedA.count == 1)
        #expect(loadedA[0].question == "QA")
        #expect(loadedB.count == 1)
        #expect(loadedB[0].question == "QB")
    }

    @Test("loadAllDecisions aggregates across sessions")
    func loadAll() async throws {
        let journal = makeJournal()

        try await journal.record(makeDecision(sessionId: "sess-a", question: "QA"))
        try await journal.record(makeDecision(sessionId: "sess-b", question: "QB"))

        let all = try await journal.loadAllDecisions()
        #expect(all.count == 2)
    }

    @Test("Query filters by category")
    func queryByCategory() async throws {
        let journal = makeJournal()

        try await journal.record(DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "Arch Q", choice: "c", rationale: "r",
            impact: .architecture
        ))
        try await journal.record(DecisionEvent(
            sessionId: "test", category: .process,
            question: "Process Q", choice: "c", rationale: "r",
            impact: .process
        ))

        let archOnly = try await journal.query(DecisionQuery(category: .architecture))
        #expect(archOnly.count == 1)
        #expect(archOnly[0].question == "Arch Q")
    }

    @Test("buildChain finds root and direct children")
    func buildChain() async throws {
        let journal = makeJournal()
        let root = DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "Root", choice: "c", rationale: "r",
            impact: .architecture
        )
        let child = DecisionEvent(
            sessionId: "test", category: .implementation,
            question: "Child", choice: "c", rationale: "r",
            impact: .implementation, parentDecisionId: root.id
        )

        try await journal.record(root)
        try await journal.record(child)

        let chain = try await journal.buildChain(rootId: root.id)
        #expect(chain != nil)
        #expect(chain?.root.question == "Root")
        #expect(chain?.children.count == 1)
        #expect(chain?.children[0].question == "Child")
    }

    @Test("buildFullChain walks up from child to root")
    func buildFullChain() async throws {
        let journal = makeJournal()
        let root = DecisionEvent(
            sessionId: "test", category: .architecture,
            question: "Root", choice: "c", rationale: "r",
            impact: .architecture
        )
        let child = DecisionEvent(
            sessionId: "test", category: .implementation,
            question: "Child", choice: "c", rationale: "r",
            impact: .implementation, parentDecisionId: root.id
        )

        try await journal.record(root)
        try await journal.record(child)

        let chain = try await journal.buildFullChain(from: child.id)
        #expect(chain != nil)
        #expect(chain?.root.question == "Root")
    }

    @Test("Empty session returns empty array")
    func emptySession() async throws {
        let journal = makeJournal()
        let loaded = try await journal.loadDecisions(sessionId: "nonexistent")
        #expect(loaded.isEmpty)
    }

    @Test("clearCache forces reload from disk")
    func clearCacheReloads() async throws {
        let journal = makeJournal()
        try await journal.record(makeDecision(sessionId: "sess-1", question: "Q1"))

        let first = try await journal.loadDecisions(sessionId: "sess-1")
        #expect(first.count == 1)

        await journal.clearCache()

        let second = try await journal.loadDecisions(sessionId: "sess-1")
        #expect(second.count == 1)
    }

    // MARK: - Helpers

    private func makeJournal() -> DecisionJournal {
        let path = NSTemporaryDirectory() + "decision-journal-test-\(UUID().uuidString)"
        return DecisionJournal(basePath: path)
    }

    private func makeDecision(sessionId: String, question: String) -> DecisionEvent {
        DecisionEvent(
            sessionId: sessionId,
            category: .architecture,
            question: question,
            choice: "Yes",
            rationale: "Because",
            impact: .architecture
        )
    }
}

// MARK: - EventClassifier Observatory Tests

@Suite("EventClassifier — Observatory Event Types")
struct ObservatoryEventClassifierTests {

    @Test("decisionMade classified as decision")
    func decisionMadeClassified() {
        let event = ShikkiEvent(source: .system, type: .decisionMade, scope: .global)
        #expect(EventClassifier.classify(event) == .decision)
    }

    @Test("architectureChoice classified as decision")
    func architectureChoiceClassified() {
        let event = ShikkiEvent(source: .system, type: .architectureChoice, scope: .global)
        #expect(EventClassifier.classify(event) == .decision)
    }

    @Test("tradeOffEvaluated classified as decision")
    func tradeOffClassified() {
        let event = ShikkiEvent(source: .system, type: .tradeOffEvaluated, scope: .global)
        #expect(EventClassifier.classify(event) == .decision)
    }

    @Test("blockerHit classified as alert")
    func blockerHitClassified() {
        let event = ShikkiEvent(source: .system, type: .blockerHit, scope: .global)
        #expect(EventClassifier.classify(event) == .alert)
    }

    @Test("blockerResolved classified as milestone")
    func blockerResolvedClassified() {
        let event = ShikkiEvent(source: .system, type: .blockerResolved, scope: .global)
        #expect(EventClassifier.classify(event) == .milestone)
    }

    @Test("milestoneReached classified as milestone")
    func milestoneReachedClassified() {
        let event = ShikkiEvent(source: .system, type: .milestoneReached, scope: .global)
        #expect(EventClassifier.classify(event) == .milestone)
    }

    @Test("redFlag classified as critical")
    func redFlagClassified() {
        let event = ShikkiEvent(source: .system, type: .redFlag, scope: .global)
        #expect(EventClassifier.classify(event) == .critical)
    }

    @Test("contextSaved classified as alert")
    func contextSavedClassified() {
        let event = ShikkiEvent(source: .system, type: .contextSaved, scope: .global)
        #expect(EventClassifier.classify(event) == .alert)
    }

    @Test("agentReportGenerated classified as progress")
    func agentReportGeneratedClassified() {
        let event = ShikkiEvent(source: .system, type: .agentReportGenerated, scope: .global)
        #expect(EventClassifier.classify(event) == .progress)
    }
}
