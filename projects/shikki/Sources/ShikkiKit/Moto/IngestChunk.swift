import Foundation

/// A lightweight chunk of content for ShikiDB ingest.
///
/// Each chunk represents a discrete piece of knowledge to store.
/// The `sourceType` and `sourceUri` fields enable provenance tracking,
/// while `category` supports filtering and retrieval.
public struct IngestChunk: Codable, Sendable, Equatable {
    /// The text content of this chunk.
    public let content: String
    /// Category for filtering (e.g. "moto_cache", "architecture", "spec").
    public let category: String
    /// The type of source that produced this chunk (e.g. "moto_cache").
    public let sourceType: String
    /// URI pointing to the original source (e.g. .moto cache endpoint).
    public let sourceUri: String

    public init(
        content: String,
        category: String,
        sourceType: String,
        sourceUri: String
    ) {
        self.content = content
        self.category = category
        self.sourceType = sourceType
        self.sourceUri = sourceUri
    }
}
