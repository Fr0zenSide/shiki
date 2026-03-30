import Foundation

/// A semantic chunk of source code, suitable for BM25 indexing.
///
/// Each chunk represents a logical unit: a function, type declaration,
/// extension, or top-level block. Chunks carry enough metadata to produce
/// cited answers with file paths and line ranges.
public struct SourceChunk: Sendable, Codable, Equatable {
    /// Relative file path from the project root.
    public let file: String
    /// 1-based start line in the source file.
    public let startLine: Int
    /// 1-based end line (inclusive) in the source file.
    public let endLine: Int
    /// The raw source text of this chunk.
    public let content: String
    /// Symbol names found in this chunk (type names, function names).
    public let symbols: [String]

    public init(
        file: String,
        startLine: Int,
        endLine: Int,
        content: String,
        symbols: [String] = []
    ) {
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
        self.content = content
        self.symbols = symbols
    }

    /// Line count of this chunk.
    public var lineCount: Int {
        endLine - startLine + 1
    }
}
