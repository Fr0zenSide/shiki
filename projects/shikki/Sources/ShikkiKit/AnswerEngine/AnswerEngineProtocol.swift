import Foundation

// MARK: - AnswerEngineProtocol

/// Protocol for answer engines that synthesise codebase knowledge.
///
/// Conformers resolve natural language questions into cited answers
/// by fusing multiple retrieval sources (BM25, ArchitectureCache, ShikkiMCP).
///
/// Designed for pluggable backends: ``LocalAnswerEngine`` uses BM25,
/// a future ``TabbyAdapter`` routes to a Tabby HTTP API.
public protocol AnswerEngineProtocol: Sendable {
    /// Ask a question about the codebase.
    ///
    /// - Parameters:
    ///   - query: Natural language question (e.g. "how does the event bus work?").
    ///   - context: Project context for scoping the search.
    /// - Returns: A cited answer with confidence and latency metrics.
    func ask(_ query: String, context: AnswerContext) async throws -> AnswerResult
}

// MARK: - AnswerContext

/// Context for scoping an answer query to a project.
public struct AnswerContext: Sendable {
    /// Absolute path to the project root.
    public let projectPath: String
    /// Optional architecture cache for structured lookups.
    public let architectureCache: ArchitectureCache?
    /// Maximum results to consider from each source.
    public let maxResults: Int

    public init(
        projectPath: String,
        architectureCache: ArchitectureCache? = nil,
        maxResults: Int = 10
    ) {
        self.projectPath = projectPath
        self.architectureCache = architectureCache
        self.maxResults = maxResults
    }
}

// MARK: - AnswerResult

/// The result of an answer engine query.
public struct AnswerResult: Sendable, Codable {
    /// The synthesised answer text.
    public let answer: String
    /// Source citations backing the answer.
    public let citations: [Citation]
    /// Confidence score (0.0 to 1.0).
    public let confidence: Float
    /// Query-to-answer latency.
    public let latency: TimeInterval
    /// Whether the query was resolved from the cache or required a full search.
    public let fromCache: Bool

    public init(
        answer: String,
        citations: [Citation],
        confidence: Float,
        latency: TimeInterval,
        fromCache: Bool = false
    ) {
        self.answer = answer
        self.citations = citations
        self.confidence = confidence
        self.latency = latency
        self.fromCache = fromCache
    }
}

// MARK: - Citation

/// A source citation linking part of an answer to its origin.
public struct Citation: Sendable, Codable, Equatable {
    /// The source type (source code, spec document, architecture cache, DB).
    public let sourceType: CitationSourceType
    /// File path relative to the project root.
    public let file: String
    /// Start line (1-based), if applicable.
    public let startLine: Int?
    /// End line (1-based, inclusive), if applicable.
    public let endLine: Int?
    /// Brief description of what this citation provides.
    public let snippet: String?

    public init(
        sourceType: CitationSourceType,
        file: String,
        startLine: Int? = nil,
        endLine: Int? = nil,
        snippet: String? = nil
    ) {
        self.sourceType = sourceType
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
        self.snippet = snippet
    }

    /// Human-readable location string (e.g. "Sources/Foo.swift (lines 12-45)").
    public var location: String {
        if let start = startLine, let end = endLine {
            return "\(file) (lines \(start)-\(end))"
        } else if let start = startLine {
            return "\(file) (line \(start))"
        }
        return file
    }
}

// MARK: - CitationSourceType

/// The type of source a citation refers to.
public enum CitationSourceType: String, Sendable, Codable {
    case sourceCode = "source"
    case specDocument = "spec"
    case architectureCache = "cache"
    case database = "db"
}

// MARK: - AnswerEngineError

/// Errors from answer engine operations.
public enum AnswerEngineError: Error, LocalizedError, Sendable {
    case noResults(String)
    case indexEmpty
    case projectNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noResults(let query):
            return "No results found for query: \(query)"
        case .indexEmpty:
            return "BM25 index is empty. Run indexing first."
        case .projectNotFound(let path):
            return "Project not found at: \(path)"
        }
    }
}
