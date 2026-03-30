import Foundation

/// BM25 full-text search index over ``SourceChunk`` values.
///
/// Implements Okapi BM25 (Robertson & Walker, 1994) with standard parameters.
/// No external dependencies -- pure Swift implementation suitable for
/// project-scale corpora (hundreds to low thousands of chunks).
///
/// Thread-safe: all mutation happens during `build()`, queries are read-only.
public struct BM25Index: Sendable {

    /// BM25 tuning parameters.
    public struct Parameters: Sendable {
        /// Term frequency saturation. Standard default: 1.2
        public let k1: Double
        /// Document length normalization. Standard default: 0.75
        public let b: Double

        public init(k1: Double = 1.2, b: Double = 0.75) {
            self.k1 = k1
            self.b = b
        }
    }

    /// A scored search result.
    public struct ScoredChunk: Sendable {
        public let chunk: SourceChunk
        public let score: Double
    }

    // MARK: - Stored State

    private let chunks: [SourceChunk]
    /// Term -> document indices containing that term.
    private let invertedIndex: [String: Set<Int>]
    /// Per-document term frequency: [docIndex][term] -> count.
    private let termFrequencies: [[String: Int]]
    /// Per-document total token count.
    private let documentLengths: [Int]
    /// Average document length across the corpus.
    private let avgDocLength: Double
    /// Total number of documents.
    private let documentCount: Int
    /// BM25 parameters.
    private let params: Parameters

    // MARK: - Init (private, use `build()`)

    private init(
        chunks: [SourceChunk],
        invertedIndex: [String: Set<Int>],
        termFrequencies: [[String: Int]],
        documentLengths: [Int],
        avgDocLength: Double,
        params: Parameters
    ) {
        self.chunks = chunks
        self.invertedIndex = invertedIndex
        self.termFrequencies = termFrequencies
        self.documentLengths = documentLengths
        self.avgDocLength = avgDocLength
        self.documentCount = chunks.count
        self.params = params
    }

    /// Empty index.
    public static let empty = BM25Index(
        chunks: [],
        invertedIndex: [:],
        termFrequencies: [],
        documentLengths: [],
        avgDocLength: 0,
        params: Parameters()
    )

    // MARK: - Build

    /// Build an index from a collection of source chunks.
    ///
    /// - Parameters:
    ///   - chunks: The corpus to index.
    ///   - params: BM25 tuning parameters.
    /// - Returns: A ready-to-query index.
    public static func build(
        from chunks: [SourceChunk],
        params: Parameters = Parameters()
    ) -> BM25Index {
        guard !chunks.isEmpty else { return .empty }

        var invertedIndex: [String: Set<Int>] = [:]
        var termFrequencies: [[String: Int]] = []
        var documentLengths: [Int] = []

        for (docIndex, chunk) in chunks.enumerated() {
            let tokens = tokenize(chunk.content + " " + chunk.symbols.joined(separator: " "))
            var tf: [String: Int] = [:]

            for token in tokens {
                tf[token, default: 0] += 1
                invertedIndex[token, default: []].insert(docIndex)
            }

            termFrequencies.append(tf)
            documentLengths.append(tokens.count)
        }

        let totalLength = documentLengths.reduce(0, +)
        let avgDocLength = Double(totalLength) / Double(chunks.count)

        return BM25Index(
            chunks: chunks,
            invertedIndex: invertedIndex,
            termFrequencies: termFrequencies,
            documentLengths: documentLengths,
            avgDocLength: avgDocLength,
            params: params
        )
    }

    // MARK: - Query

    /// Search the index for chunks matching the query.
    ///
    /// - Parameters:
    ///   - query: Natural language search query.
    ///   - topK: Maximum results to return.
    /// - Returns: Scored chunks sorted by relevance (highest first).
    public func search(query: String, topK: Int = 10) -> [ScoredChunk] {
        guard documentCount > 0 else { return [] }

        let queryTokens = Self.tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        var scores = [Double](repeating: 0.0, count: documentCount)

        for token in queryTokens {
            guard let postings = invertedIndex[token] else { continue }

            // IDF: log((N - n + 0.5) / (n + 0.5) + 1)
            let n = Double(postings.count)
            let idf = log((Double(documentCount) - n + 0.5) / (n + 0.5) + 1.0)

            for docIndex in postings {
                let tf = Double(termFrequencies[docIndex][token] ?? 0)
                let dl = Double(documentLengths[docIndex])

                // BM25 score component
                let numerator = tf * (params.k1 + 1.0)
                let denominator = tf + params.k1 * (1.0 - params.b + params.b * dl / avgDocLength)
                scores[docIndex] += idf * numerator / denominator
            }
        }

        // Collect and sort
        let scored = scores.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(topK)
            .map { ScoredChunk(chunk: chunks[$0.offset], score: $0.element) }

        return Array(scored)
    }

    /// Number of indexed chunks.
    public var count: Int { chunks.count }

    /// All indexed chunks.
    public var allChunks: [SourceChunk] { chunks }

    // MARK: - Tokenization

    /// Tokenize text into lowercase terms, splitting on non-alphanumeric characters
    /// and camelCase/snake_case boundaries.
    static func tokenize(_ text: String) -> [String] {
        // Split camelCase: insert space before uppercase letters that follow lowercase
        var expanded = ""
        var prevWasLower = false
        for char in text {
            if char.isUppercase && prevWasLower {
                expanded.append(" ")
            }
            expanded.append(char)
            prevWasLower = char.isLowercase
        }

        // Split on non-alphanumeric, then lowercase and filter short tokens
        return expanded
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
