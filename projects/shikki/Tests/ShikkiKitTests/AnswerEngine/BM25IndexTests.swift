import Testing
@testable import ShikkiKit

@Suite("BM25Index")
struct BM25IndexTests {

    // MARK: - Tokenization

    @Test("Tokenize splits camelCase")
    func tokenizeCamelCase() {
        let tokens = BM25Index.tokenize("EventBusManager")
        #expect(tokens.contains("event"))
        #expect(tokens.contains("bus"))
        #expect(tokens.contains("manager"))
    }

    @Test("Tokenize splits snake_case")
    func tokenizeSnakeCase() {
        let tokens = BM25Index.tokenize("event_bus_manager")
        #expect(tokens.contains("event"))
        #expect(tokens.contains("bus"))
        #expect(tokens.contains("manager"))
    }

    @Test("Tokenize lowercases and filters short tokens")
    func tokenizeLowerAndFilter() {
        let tokens = BM25Index.tokenize("A Big test OF things")
        // "a" (1 char) should be filtered out, "of" (2 chars) kept
        #expect(!tokens.contains("a"))
        #expect(tokens.contains("big"))
        #expect(tokens.contains("test"))
        #expect(tokens.contains("of"))
        #expect(tokens.contains("things"))
    }

    @Test("Tokenize handles Swift code")
    func tokenizeSwiftCode() {
        let tokens = BM25Index.tokenize("func askQuestion(_ query: String) async throws -> AnswerResult")
        #expect(tokens.contains("func"))
        #expect(tokens.contains("ask"))
        #expect(tokens.contains("question"))
        #expect(tokens.contains("query"))
        #expect(tokens.contains("string"))
        #expect(tokens.contains("answer"))
        #expect(tokens.contains("result"))
    }

    @Test("Tokenize empty string returns empty")
    func tokenizeEmpty() {
        let tokens = BM25Index.tokenize("")
        #expect(tokens.isEmpty)
    }

    // MARK: - Index Building

    @Test("Empty corpus builds empty index")
    func emptyCorpus() {
        let index = BM25Index.build(from: [])
        #expect(index.count == 0)
    }

    @Test("Single chunk indexes correctly")
    func singleChunk() {
        let chunk = SourceChunk(
            file: "test.swift",
            startLine: 1,
            endLine: 5,
            content: "func hello() { return 42 }",
            symbols: ["hello"]
        )
        let index = BM25Index.build(from: [chunk])
        #expect(index.count == 1)

        let results = index.search(query: "hello")
        #expect(results.count == 1)
        #expect(results[0].chunk.file == "test.swift")
        #expect(results[0].score > 0)
    }

    @Test("Multiple chunks with distinct content")
    func multipleDistinctChunks() {
        let chunks = [
            SourceChunk(file: "bus.swift", startLine: 1, endLine: 10,
                       content: "EventBus dispatches events to subscribers",
                       symbols: ["EventBus"]),
            SourceChunk(file: "cache.swift", startLine: 1, endLine: 10,
                       content: "ArchitectureCache stores project structure",
                       symbols: ["ArchitectureCache"]),
            SourceChunk(file: "parser.swift", startLine: 1, endLine: 10,
                       content: "ProjectAnalyzer parses Swift source files",
                       symbols: ["ProjectAnalyzer"]),
        ]

        let index = BM25Index.build(from: chunks)
        #expect(index.count == 3)

        // Query for events should rank bus.swift highest
        let eventResults = index.search(query: "event bus dispatch")
        #expect(!eventResults.isEmpty)
        #expect(eventResults[0].chunk.file == "bus.swift")

        // Query for cache should rank cache.swift highest
        let cacheResults = index.search(query: "architecture cache project")
        #expect(!cacheResults.isEmpty)
        #expect(cacheResults[0].chunk.file == "cache.swift")

        // Query for Swift parsing should rank parser.swift highest
        let parseResults = index.search(query: "parse Swift source")
        #expect(!parseResults.isEmpty)
        #expect(parseResults[0].chunk.file == "parser.swift")
    }

    // MARK: - Scoring

    @Test("More relevant documents score higher")
    func relevanceScoring() {
        let chunks = [
            SourceChunk(file: "relevant.swift", startLine: 1, endLine: 10,
                       content: "BM25 search index for full text retrieval scoring",
                       symbols: ["BM25Index"]),
            SourceChunk(file: "unrelated.swift", startLine: 1, endLine: 10,
                       content: "Network HTTP client for REST API calls",
                       symbols: ["HTTPClient"]),
        ]

        let index = BM25Index.build(from: chunks)
        let results = index.search(query: "BM25 search index")

        #expect(results.count >= 1)
        #expect(results[0].chunk.file == "relevant.swift")

        if results.count > 1 {
            #expect(results[0].score > results[1].score)
        }
    }

    @Test("TopK limits results")
    func topKLimit() {
        let chunks = (0..<20).map {
            SourceChunk(file: "file\($0).swift", startLine: 1, endLine: 5,
                       content: "common shared keyword term\($0)",
                       symbols: ["Type\($0)"])
        }

        let index = BM25Index.build(from: chunks)
        let results = index.search(query: "common shared keyword", topK: 5)

        #expect(results.count == 5)
    }

    @Test("Results are sorted by score descending")
    func resultsSortOrder() {
        let chunks = [
            SourceChunk(file: "a.swift", startLine: 1, endLine: 5,
                       content: "alpha bravo charlie",
                       symbols: []),
            SourceChunk(file: "b.swift", startLine: 1, endLine: 5,
                       content: "alpha alpha alpha bravo",
                       symbols: []),
            SourceChunk(file: "c.swift", startLine: 1, endLine: 5,
                       content: "delta echo foxtrot",
                       symbols: []),
        ]

        let index = BM25Index.build(from: chunks)
        let results = index.search(query: "alpha bravo")

        #expect(results.count >= 2)
        for i in 0..<(results.count - 1) {
            #expect(results[i].score >= results[i + 1].score)
        }
    }

    // MARK: - Edge Cases

    @Test("Query with no matching tokens returns empty")
    func noMatchingTokens() {
        let chunks = [
            SourceChunk(file: "test.swift", startLine: 1, endLine: 5,
                       content: "hello world", symbols: [])
        ]
        let index = BM25Index.build(from: chunks)
        let results = index.search(query: "zzzznotaword")
        #expect(results.isEmpty)
    }

    @Test("Empty query returns empty results")
    func emptyQuery() {
        let chunks = [
            SourceChunk(file: "test.swift", startLine: 1, endLine: 5,
                       content: "hello world", symbols: [])
        ]
        let index = BM25Index.build(from: chunks)
        let results = index.search(query: "")
        #expect(results.isEmpty)
    }

    @Test("Symbols boost matching")
    func symbolsBoostMatching() {
        let chunks = [
            SourceChunk(file: "a.swift", startLine: 1, endLine: 5,
                       content: "some generic code here",
                       symbols: ["EventBus"]),
            SourceChunk(file: "b.swift", startLine: 1, endLine: 5,
                       content: "some other code here",
                       symbols: ["NetworkClient"]),
        ]

        let index = BM25Index.build(from: chunks)
        let results = index.search(query: "EventBus")

        #expect(!results.isEmpty)
        #expect(results[0].chunk.file == "a.swift")
    }

    @Test("BM25 parameters can be customized")
    func customParameters() {
        let params = BM25Index.Parameters(k1: 2.0, b: 0.5)
        let chunks = [
            SourceChunk(file: "test.swift", startLine: 1, endLine: 5,
                       content: "hello world", symbols: [])
        ]
        let index = BM25Index.build(from: chunks, params: params)
        let results = index.search(query: "hello")
        #expect(results.count == 1)
    }

    @Test("Static empty index returns no results")
    func staticEmptyIndex() {
        let results = BM25Index.empty.search(query: "anything")
        #expect(results.isEmpty)
        #expect(BM25Index.empty.count == 0)
    }
}
