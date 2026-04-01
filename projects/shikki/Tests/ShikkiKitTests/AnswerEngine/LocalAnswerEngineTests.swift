import Foundation
import Testing
@testable import ShikkiKit

@Suite("LocalAnswerEngine")
struct LocalAnswerEngineTests {

    // MARK: - Index Building

    @Test("Build index from chunks returns correct count")
    func buildIndexFromChunks() {
        let engine = LocalAnswerEngine()
        let chunks = makeTestChunks()
        let count = engine.buildIndex(from: chunks)
        #expect(count == chunks.count)
        #expect(engine.indexedChunkCount == chunks.count)
    }

    @Test("Build index from empty chunks returns zero")
    func buildIndexEmpty() {
        let engine = LocalAnswerEngine()
        let count = engine.buildIndex(from: [])
        #expect(count == 0)
        #expect(engine.indexedChunkCount == 0)
    }

    // MARK: - Ask (BM25 only, no cache)

    @Test("Ask returns relevant results for matching query")
    func askMatchingQuery() async throws {
        let engine = LocalAnswerEngine()
        engine.buildIndex(from: makeTestChunks())

        let context = AnswerContext(projectPath: "/tmp/test")
        let result = try await engine.ask("event bus publish subscribe", context: context)

        #expect(!result.answer.isEmpty)
        #expect(!result.citations.isEmpty)
        #expect(result.latency > 0)
        #expect(result.confidence >= 0)
        #expect(result.confidence <= 1)
    }

    @Test("Ask throws noResults for completely unmatched query")
    func askNoResults() async {
        let engine = LocalAnswerEngine()
        engine.buildIndex(from: makeTestChunks())

        let context = AnswerContext(projectPath: "/tmp/test")
        do {
            _ = try await engine.ask("xyzzyplugh", context: context)
            Issue.record("Expected AnswerEngineError.noResults")
        } catch let error as AnswerEngineError {
            switch error {
            case .noResults:
                break  // Expected
            default:
                Issue.record("Wrong AnswerEngineError variant: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Ask throws indexEmpty when no index is built and path is invalid")
    func askIndexEmpty() async {
        let engine = LocalAnswerEngine()
        let context = AnswerContext(projectPath: "/nonexistent/path")

        do {
            _ = try await engine.ask("anything", context: context)
            Issue.record("Expected AnswerEngineError.indexEmpty")
        } catch let error as AnswerEngineError {
            switch error {
            case .indexEmpty:
                break  // Expected
            default:
                Issue.record("Wrong AnswerEngineError variant: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Ask with Architecture Cache

    @Test("Ask integrates architecture cache results")
    func askWithCache() async throws {
        let engine = LocalAnswerEngine()
        engine.buildIndex(from: makeTestChunks())

        let cache = makeTestCache()
        let context = AnswerContext(
            projectPath: "/tmp/test",
            architectureCache: cache
        )

        let result = try await engine.ask("EventBus", context: context)

        #expect(!result.answer.isEmpty)
        // Should have citations from both BM25 and cache
        let sourceTypes = Set(result.citations.map(\.sourceType))
        #expect(sourceTypes.contains(.sourceCode) || sourceTypes.contains(.architectureCache))
    }

    @Test("Architecture cache lookup finds protocols by name")
    func cacheLookupProtocol() {
        let engine = LocalAnswerEngine()
        let cache = makeTestCache()

        let results = engine.lookupArchitectureCache(query: "EventBus protocol", cache: cache)
        #expect(!results.isEmpty)

        let hasEventBus = results.contains { $0.summary.contains("EventBusProtocol") }
        #expect(hasEventBus)
    }

    @Test("Architecture cache lookup finds types by name")
    func cacheLookupType() {
        let engine = LocalAnswerEngine()
        let cache = makeTestCache()

        let results = engine.lookupArchitectureCache(query: "SourceChunk", cache: cache)
        #expect(!results.isEmpty)
    }

    @Test("Architecture cache lookup returns empty for unmatched query")
    func cacheLookupNoMatch() {
        let engine = LocalAnswerEngine()
        let cache = makeTestCache()

        let results = engine.lookupArchitectureCache(query: "xyzzyplugh", cache: cache)
        #expect(results.isEmpty)
    }

    @Test("Architecture cache lookup returns empty when cache is nil")
    func cacheLookupNil() {
        let engine = LocalAnswerEngine()
        let results = engine.lookupArchitectureCache(query: "anything", cache: nil)
        #expect(results.isEmpty)
    }

    // MARK: - Fusion

    @Test("Fusion merges BM25 and cache results without duplicates")
    func fusionDeduplicates() {
        let engine = LocalAnswerEngine()

        let bm25Results: [BM25Index.ScoredChunk] = [
            .init(chunk: SourceChunk(file: "EventBus.swift", startLine: 1, endLine: 10,
                                     content: "event bus code", symbols: ["EventBus"]),
                  score: 5.0),
        ]

        let cacheResults: [LocalAnswerEngine.CacheResult] = [
            .init(
                citation: Citation(sourceType: .architectureCache, file: "EventBus.swift",
                                   snippet: "Protocol EventBusProtocol"),
                summary: "Protocol EventBusProtocol"
            ),
            .init(
                citation: Citation(sourceType: .architectureCache, file: "Other.swift",
                                   snippet: "Struct Something"),
                summary: "Struct Something"
            ),
        ]

        let citations = engine.fuseResults(bm25Results: bm25Results, cacheResults: cacheResults)

        // EventBus.swift should appear only once (from BM25, not duplicated from cache)
        let eventBusCount = citations.filter { $0.file == "EventBus.swift" }.count
        #expect(eventBusCount == 1)

        // Other.swift should be present from cache
        let otherCount = citations.filter { $0.file == "Other.swift" }.count
        #expect(otherCount == 1)
    }

    @Test("Fusion produces correct citation source types")
    func fusionSourceTypes() {
        let engine = LocalAnswerEngine()

        let bm25Results: [BM25Index.ScoredChunk] = [
            .init(chunk: SourceChunk(file: "code.swift", startLine: 1, endLine: 5,
                                     content: "swift code", symbols: []),
                  score: 3.0),
            .init(chunk: SourceChunk(file: "spec.md", startLine: 1, endLine: 5,
                                     content: "spec content", symbols: []),
                  score: 2.0),
        ]

        let citations = engine.fuseResults(bm25Results: bm25Results, cacheResults: [])

        #expect(citations[0].sourceType == .sourceCode)
        #expect(citations[1].sourceType == .specDocument)
    }

    // MARK: - Event Emission

    @Test("Ask emits event to event bus")
    func askEmitsEvent() async throws {
        let eventBus = InProcessEventBus()
        let engine = LocalAnswerEngine(eventBus: eventBus)
        engine.buildIndex(from: makeTestChunks())

        // Subscribe before asking
        let stream = await eventBus.subscribe(
            filter: EventFilter(types: [.custom("answer_engine_query")])
        )

        let context = AnswerContext(projectPath: "/tmp/test")
        _ = try await engine.ask("event bus", context: context)

        // Check that an event was emitted
        var receivedEvent: ShikkiEvent?
        for await event in stream {
            receivedEvent = event
            break
        }

        #expect(receivedEvent != nil)
        #expect(receivedEvent?.type == .custom("answer_engine_query"))
        #expect(receivedEvent?.payload["query"] == .string("event bus"))
    }

    // MARK: - Synthesis

    @Test("Synthesise produces non-empty answer from BM25 results")
    func synthesiseFromBM25() {
        let engine = LocalAnswerEngine()

        let bm25Results: [BM25Index.ScoredChunk] = [
            .init(chunk: SourceChunk(file: "Bus.swift", startLine: 1, endLine: 5,
                                     content: "EventBus dispatches events", symbols: ["EventBus"]),
                  score: 5.0),
        ]

        let citations = [Citation(sourceType: .sourceCode, file: "Bus.swift",
                                  startLine: 1, endLine: 5)]

        let answer = engine.synthesise(
            query: "event bus",
            bm25Results: bm25Results,
            cacheResults: [],
            citations: citations
        )

        #expect(!answer.isEmpty)
        #expect(answer.contains("EventBus"))
    }

    @Test("Synthesise includes cache summaries before BM25 chunks")
    func synthesiseWithCacheFirst() {
        let engine = LocalAnswerEngine()

        let cacheResults: [LocalAnswerEngine.CacheResult] = [
            .init(
                citation: Citation(sourceType: .architectureCache, file: "proto.swift"),
                summary: "Protocol MyProto: 3 methods."
            ),
        ]

        let answer = engine.synthesise(
            query: "MyProto",
            bm25Results: [],
            cacheResults: cacheResults,
            citations: []
        )

        #expect(answer.contains("Protocol MyProto"))
    }

    // MARK: - Helpers

    func makeTestChunks() -> [SourceChunk] {
        [
            SourceChunk(
                file: "Sources/ShikkiKit/Events/EventBus.swift",
                startLine: 1, endLine: 30,
                content: """
                public actor InProcessEventBus {
                    private var subscribers: [SubscriptionID: Subscriber] = [:]
                    public func publish(_ event: ShikkiEvent) {
                        for (_, sub) in subscribers {
                            if sub.filter.matches(event) {
                                sub.continuation.yield(event)
                            }
                        }
                    }
                    public func subscribe(filter: EventFilter) -> AsyncStream<ShikkiEvent> {
                        let (stream, _) = subscribeWithId(filter: filter)
                        return stream
                    }
                }
                """,
                symbols: ["InProcessEventBus", "publish", "subscribe"]
            ),
            SourceChunk(
                file: "Sources/ShikkiKit/CodeGen/ProjectAnalyzer.swift",
                startLine: 1, endLine: 20,
                content: """
                public struct ProjectAnalyzer: Sendable {
                    public func analyze(projectPath: String) async throws -> ArchitectureCache {
                        let swiftFiles = collectSwiftFiles(at: projectPath)
                        // Parse all files for declarations
                    }
                }
                """,
                symbols: ["ProjectAnalyzer", "analyze"]
            ),
            SourceChunk(
                file: "Sources/ShikkiKit/AnswerEngine/BM25Index.swift",
                startLine: 1, endLine: 15,
                content: """
                public struct BM25Index: Sendable {
                    public static func build(from chunks: [SourceChunk]) -> BM25Index {
                        // Build inverted index
                    }
                    public func search(query: String, topK: Int) -> [ScoredChunk] {
                        // BM25 scoring
                    }
                }
                """,
                symbols: ["BM25Index", "build", "search"]
            ),
            SourceChunk(
                file: "features/shikki-answer-engine.md",
                startLine: 1, endLine: 10,
                content: """
                # Shikki Answer Engine
                Natural language Q&A over the codebase.
                BM25 full-text search + ArchitectureCache lookup.
                """,
                symbols: ["Shikki Answer Engine"]
            ),
        ]
    }

    func makeTestCache() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "shikki",
            projectPath: "/tmp/test",
            gitHash: "abc123",
            builtAt: Date(),
            packageInfo: PackageInfo(name: "shikki"),
            protocols: [
                ProtocolDescriptor(
                    name: "EventBusProtocol",
                    file: "Sources/Events/EventBus.swift",
                    methods: ["func publish(_ event: ShikkiEvent)", "func subscribe(filter: EventFilter) -> AsyncStream<ShikkiEvent>"],
                    conformers: ["InProcessEventBus"],
                    module: "ShikkiKit"
                ),
                ProtocolDescriptor(
                    name: "AnswerEngineProtocol",
                    file: "Sources/AnswerEngine/AnswerEngineProtocol.swift",
                    methods: ["func ask(_ query: String, context: AnswerContext) async throws -> AnswerResult"],
                    conformers: ["LocalAnswerEngine"],
                    module: "ShikkiKit"
                ),
            ],
            types: [
                TypeDescriptor(
                    name: "SourceChunk",
                    kind: .struct,
                    file: "Sources/AnswerEngine/SourceChunk.swift",
                    module: "ShikkiKit",
                    fields: ["file", "startLine", "endLine", "content", "symbols"],
                    conformances: ["Sendable", "Codable"],
                    isPublic: true
                ),
                TypeDescriptor(
                    name: "BM25Index",
                    kind: .struct,
                    file: "Sources/AnswerEngine/BM25Index.swift",
                    module: "ShikkiKit",
                    fields: [],
                    conformances: ["Sendable"],
                    isPublic: true
                ),
            ],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo(framework: "swift-testing", testFiles: 3, testCount: 30)
        )
    }
}
