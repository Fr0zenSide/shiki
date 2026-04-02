import Foundation

/// BM25-backed answer engine for local project Q&A.
///
/// Retrieval pipeline:
/// 1. BM25 full-text search over ``SourceChunk`` corpus
/// 2. ArchitectureCache lookup for structured type/protocol info
/// 3. Fusion: merge and rank results from both sources
/// 4. Synthesis: compose a cited answer from top-ranked results
///
/// No external dependencies (no LLM, no Tabby, no network).
/// Synthesis is extractive (selects and presents relevant chunks)
/// rather than generative (no LLM rewriting).
public final class LocalAnswerEngine: AnswerEngineProtocol, @unchecked Sendable {

    private var index: BM25Index
    private let chunker: SourceChunker
    private let eventBus: InProcessEventBus?

    public init(
        chunker: SourceChunker = SourceChunker(),
        eventBus: InProcessEventBus? = nil
    ) {
        self.index = .empty
        self.chunker = chunker
        self.eventBus = eventBus
    }

    /// Build or rebuild the BM25 index for a project.
    ///
    /// - Parameter projectPath: Absolute path to the project root.
    /// - Returns: Number of chunks indexed.
    @discardableResult
    public func buildIndex(projectPath: String) -> Int {
        let chunks = chunker.chunkProject(projectPath: projectPath)
        index = BM25Index.build(from: chunks)
        return chunks.count
    }

    /// Build the index from pre-computed chunks (useful for testing).
    @discardableResult
    public func buildIndex(from chunks: [SourceChunk]) -> Int {
        index = BM25Index.build(from: chunks)
        return chunks.count
    }

    /// Number of chunks in the current index.
    public var indexedChunkCount: Int {
        index.count
    }

    // MARK: - AnswerEngineProtocol

    public func ask(_ query: String, context: AnswerContext) async throws -> AnswerResult {
        let start = ContinuousClock.now

        // Ensure index is built
        if index.count == 0 {
            buildIndex(projectPath: context.projectPath)
        }

        guard index.count > 0 else {
            throw AnswerEngineError.indexEmpty
        }

        // Phase 1: BM25 retrieval
        let bm25Results = index.search(query: query, topK: context.maxResults)

        // Phase 2: Architecture cache lookup
        let cacheResults = lookupArchitectureCache(
            query: query,
            cache: context.architectureCache
        )

        // Phase 3: Fuse results
        let fusedCitations = fuseResults(
            bm25Results: bm25Results,
            cacheResults: cacheResults
        )

        guard !fusedCitations.isEmpty else {
            let elapsed = ContinuousClock.now - start
            let latency = elapsed.totalSeconds
            await emitEvent(query: query, citations: [], latency: latency, source: .system)
            throw AnswerEngineError.noResults(query)
        }

        // Phase 4: Synthesise answer
        let answer = synthesise(
            query: query,
            bm25Results: bm25Results,
            cacheResults: cacheResults,
            citations: fusedCitations
        )

        let elapsed = ContinuousClock.now - start
        let latency = elapsed.totalSeconds

        // Confidence: based on top BM25 score (normalized)
        let topScore = bm25Results.first?.score ?? 0
        let confidence = Float(min(topScore / 10.0, 1.0))

        let result = AnswerResult(
            answer: answer,
            citations: fusedCitations,
            confidence: confidence,
            latency: latency
        )

        // BR-5: Emit event for Observatory
        await emitEvent(query: query, citations: fusedCitations, latency: latency, source: .system)

        return result
    }

    // MARK: - Architecture Cache Lookup

    struct CacheResult {
        let citation: Citation
        let summary: String
    }

    func lookupArchitectureCache(query: String, cache: ArchitectureCache?) -> [CacheResult] {
        guard let cache else { return [] }

        var results: [CacheResult] = []
        let queryLower = query.lowercased()
        let queryTokens = Set(BM25Index.tokenize(query))

        // Search protocols
        for proto in cache.protocols {
            let nameTokens = Set(BM25Index.tokenize(proto.name))
            if !nameTokens.isDisjoint(with: queryTokens) || queryLower.contains(proto.name.lowercased()) {
                let methods = proto.methods.isEmpty ? "no methods" : proto.methods.joined(separator: ", ")
                let conformers = proto.conformers.isEmpty ? "no conformers" : proto.conformers.joined(separator: ", ")
                let summary = "Protocol \(proto.name): \(methods). Conformers: \(conformers)."

                results.append(CacheResult(
                    citation: Citation(
                        sourceType: .architectureCache,
                        file: proto.file,
                        snippet: "Protocol \(proto.name) [\(proto.module)]"
                    ),
                    summary: summary
                ))
            }
        }

        // Search types
        for type in cache.types {
            let nameTokens = Set(BM25Index.tokenize(type.name))
            if !nameTokens.isDisjoint(with: queryTokens) || queryLower.contains(type.name.lowercased()) {
                let fields = type.fields.isEmpty ? "no fields" : type.fields.joined(separator: ", ")
                let confs = type.conformances.isEmpty ? "" : " Conforms to: \(type.conformances.joined(separator: ", "))."
                let summary = "\(type.kind.rawValue.capitalized) \(type.name): fields [\(fields)].\(confs)"

                results.append(CacheResult(
                    citation: Citation(
                        sourceType: .architectureCache,
                        file: type.file,
                        snippet: "\(type.kind.rawValue.capitalized) \(type.name) [\(type.module)]"
                    ),
                    summary: summary
                ))
            }
        }

        return results
    }

    // MARK: - Fusion

    func fuseResults(
        bm25Results: [BM25Index.ScoredChunk],
        cacheResults: [CacheResult]
    ) -> [Citation] {
        var citations: [Citation] = []
        var seenFiles: Set<String> = []

        // BM25 results first (they have line ranges)
        for scored in bm25Results {
            let citation = Citation(
                sourceType: scored.chunk.file.hasSuffix(".md") ? .specDocument : .sourceCode,
                file: scored.chunk.file,
                startLine: scored.chunk.startLine,
                endLine: scored.chunk.endLine,
                snippet: scored.chunk.symbols.isEmpty
                    ? nil
                    : scored.chunk.symbols.joined(separator: ", ")
            )
            citations.append(citation)
            seenFiles.insert(scored.chunk.file)
        }

        // Cache results (deduplicate by file)
        for cacheResult in cacheResults {
            if !seenFiles.contains(cacheResult.citation.file) {
                citations.append(cacheResult.citation)
                seenFiles.insert(cacheResult.citation.file)
            }
        }

        return citations
    }

    // MARK: - Synthesis

    func synthesise(
        query: String,
        bm25Results: [BM25Index.ScoredChunk],
        cacheResults: [CacheResult],
        citations: [Citation]
    ) -> String {
        var sections: [String] = []

        // If we have cache results, lead with structured info
        if !cacheResults.isEmpty {
            for cacheResult in cacheResults.prefix(3) {
                sections.append(cacheResult.summary)
            }
        }

        // Add top BM25 chunks (extractive: show the actual code/text)
        for scored in bm25Results.prefix(3) {
            let preview = scored.chunk.content
                .components(separatedBy: "\n")
                .prefix(10)
                .joined(separator: "\n")

            let symbols = scored.chunk.symbols.isEmpty
                ? ""
                : " [\(scored.chunk.symbols.joined(separator: ", "))]"

            sections.append("\(scored.chunk.file):\(scored.chunk.startLine)\(symbols)\n\(preview)")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Event Emission (BR-5)

    private func emitEvent(
        query: String,
        citations: [Citation],
        latency: TimeInterval,
        source: EventSource
    ) async {
        guard let eventBus else { return }

        let event = ShikkiEvent(
            source: source,
            type: .custom("answer_engine_query"),
            scope: .global,
            payload: [
                "query": .string(query),
                "citation_count": .int(citations.count),
                "latency_ms": .int(Int(latency * 1000)),
            ],
            metadata: EventMetadata(
                duration: latency,
                tags: ["answer-engine"]
            )
        )

        await eventBus.publish(event)
    }
}
