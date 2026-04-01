import Foundation
import Testing
@testable import ShikkiKit

@Suite("Answer Engine Models")
struct AnswerModelTests {

    // MARK: - SourceChunk

    @Test("SourceChunk lineCount is accurate")
    func sourceChunkLineCount() {
        let chunk = SourceChunk(file: "test.swift", startLine: 5, endLine: 15,
                               content: "code", symbols: [])
        #expect(chunk.lineCount == 11)
    }

    @Test("SourceChunk single line has lineCount 1")
    func sourceChunkSingleLine() {
        let chunk = SourceChunk(file: "test.swift", startLine: 3, endLine: 3,
                               content: "one line", symbols: [])
        #expect(chunk.lineCount == 1)
    }

    @Test("SourceChunk is Equatable")
    func sourceChunkEquatable() {
        let a = SourceChunk(file: "a.swift", startLine: 1, endLine: 5,
                           content: "code", symbols: ["Foo"])
        let b = SourceChunk(file: "a.swift", startLine: 1, endLine: 5,
                           content: "code", symbols: ["Foo"])
        #expect(a == b)
    }

    @Test("SourceChunk default symbols is empty")
    func sourceChunkDefaultSymbols() {
        let chunk = SourceChunk(file: "test.swift", startLine: 1, endLine: 1,
                               content: "let x = 1")
        #expect(chunk.symbols.isEmpty)
    }

    // MARK: - Citation

    @Test("Citation is Equatable")
    func citationEquatable() {
        let a = Citation(sourceType: .sourceCode, file: "Foo.swift",
                        startLine: 1, endLine: 10)
        let b = Citation(sourceType: .sourceCode, file: "Foo.swift",
                        startLine: 1, endLine: 10)
        #expect(a == b)
    }

    @Test("Citation is Codable roundtrip")
    func citationCodable() throws {
        let original = Citation(sourceType: .sourceCode, file: "Foo.swift",
                               startLine: 1, endLine: 10, snippet: "struct Foo")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Citation.self, from: data)

        #expect(decoded == original)
    }

    @Test("CitationSourceType raw values")
    func citationSourceTypeRawValues() {
        #expect(CitationSourceType.sourceCode.rawValue == "source")
        #expect(CitationSourceType.specDocument.rawValue == "spec")
        #expect(CitationSourceType.architectureCache.rawValue == "cache")
        #expect(CitationSourceType.database.rawValue == "db")
    }

    // MARK: - AnswerResult

    @Test("AnswerResult is Codable roundtrip")
    func answerResultCodable() throws {
        let original = AnswerResult(
            answer: "EventBus handles events",
            citations: [
                Citation(sourceType: .sourceCode, file: "Bus.swift",
                        startLine: 1, endLine: 10),
            ],
            confidence: 0.85,
            latency: 0.042
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnswerResult.self, from: data)

        #expect(decoded.answer == original.answer)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.citations.count == 1)
        #expect(decoded.fromCache == false)
    }

    @Test("AnswerResult fromCache flag")
    func answerResultFromCache() {
        let cached = AnswerResult(
            answer: "cached", citations: [], confidence: 1.0,
            latency: 0.001, fromCache: true
        )
        #expect(cached.fromCache == true)

        let fresh = AnswerResult(
            answer: "fresh", citations: [], confidence: 0.5,
            latency: 0.1
        )
        #expect(fresh.fromCache == false)
    }

    // MARK: - AnswerContext

    @Test("AnswerContext defaults")
    func answerContextDefaults() {
        let ctx = AnswerContext(projectPath: "/tmp/test")
        #expect(ctx.projectPath == "/tmp/test")
        #expect(ctx.architectureCache == nil)
        #expect(ctx.maxResults == 10)
    }

    @Test("AnswerContext with custom maxResults")
    func answerContextCustomMaxResults() {
        let ctx = AnswerContext(projectPath: "/tmp/test", maxResults: 25)
        #expect(ctx.maxResults == 25)
    }

    // MARK: - AnswerEngineError

    @Test("AnswerEngineError descriptions")
    func errorDescriptions() {
        let noResults = AnswerEngineError.noResults("test query")
        #expect(noResults.localizedDescription.contains("test query"))

        let indexEmpty = AnswerEngineError.indexEmpty
        #expect(indexEmpty.localizedDescription.contains("empty"))

        let notFound = AnswerEngineError.projectNotFound("/bad/path")
        #expect(notFound.localizedDescription.contains("/bad/path"))
    }
}
