import Foundation

/// Source type for ingestion (maps to IngestRequestSchema.sourceType).
public enum IngestSourceType: String, Codable, Sendable {
    case githubRepo = "github_repo"
    case localPath = "local_path"
    case url
    case rawText = "raw_text"
}

/// A single chunk within an ingest request (maps to IngestChunkSchema).
public struct IngestChunk: Codable, Equatable, Sendable, Validatable {
    public let content: String
    public let category: String?
    public let importance: Double?
    public let filePath: String?
    public let chunkIndex: Int?

    public init(
        content: String,
        category: String? = nil,
        importance: Double? = nil,
        filePath: String? = nil,
        chunkIndex: Int? = nil
    ) {
        self.content = content
        self.category = category
        self.importance = importance
        self.filePath = filePath
        self.chunkIndex = chunkIndex
    }

    public func validate() throws {
        try Validators.requireNonEmpty(content, field: "content")
        if let importance {
            try Validators.requireRange(importance, min: 0, max: 10, field: "importance")
        }
        if let chunkIndex, chunkIndex < 0 {
            throw ShikiValidationError.fieldMustBeNonNegative("chunkIndex")
        }
    }

    enum CodingKeys: String, CodingKey {
        case content, category, importance
        case filePath = "file_path"
        case chunkIndex = "chunk_index"
    }
}

/// Ingestion dedup configuration.
public struct IngestConfig: Codable, Equatable, Sendable {
    public let dedupThreshold: Double
    public let autoCategory: Bool

    public init(dedupThreshold: Double = 0.92, autoCategory: Bool = true) {
        self.dedupThreshold = dedupThreshold
        self.autoCategory = autoCategory
    }

    enum CodingKeys: String, CodingKey {
        case dedupThreshold = "dedup_threshold"
        case autoCategory = "auto_category"
    }
}

/// Input for posting an ingestion request (maps to IngestRequestSchema).
public struct IngestRequestInput: Codable, Equatable, Sendable, Validatable {
    public let projectId: UUID
    public let sourceType: IngestSourceType
    public let sourceUri: String
    public let displayName: String?
    public let contentHash: String?
    public let chunks: [IngestChunk]
    public let totalChunks: Int?
    public let config: IngestConfig

    public init(
        projectId: UUID,
        sourceType: IngestSourceType,
        sourceUri: String,
        displayName: String? = nil,
        contentHash: String? = nil,
        chunks: [IngestChunk],
        totalChunks: Int? = nil,
        config: IngestConfig = IngestConfig()
    ) {
        self.projectId = projectId
        self.sourceType = sourceType
        self.sourceUri = sourceUri
        self.displayName = displayName
        self.contentHash = contentHash
        self.chunks = chunks
        self.totalChunks = totalChunks
        self.config = config
    }

    public func validate() throws {
        try Validators.requireNonEmpty(sourceUri, field: "sourceUri")
        if chunks.isEmpty {
            throw ShikiValidationError.custom("chunks must contain at least 1 element")
        }
        if chunks.count > 500 {
            throw ShikiValidationError.custom("chunks must contain at most 500 elements")
        }
        for chunk in chunks {
            try chunk.validate()
        }
    }

    enum CodingKeys: String, CodingKey {
        case chunks, config
        case projectId = "project_id"
        case sourceType = "source_type"
        case sourceUri = "source_uri"
        case displayName = "display_name"
        case contentHash = "content_hash"
        case totalChunks = "total_chunks"
    }
}

/// Ingestion source as stored in ingestion_sources table.
public struct IngestionSourceDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public let sourceType: IngestSourceType
    public let sourceUri: String
    public let displayName: String?
    public let contentHash: String?
    public let status: String
    public let chunksStored: Int
    public let totalChunks: Int?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        projectId: UUID,
        sourceType: IngestSourceType,
        sourceUri: String,
        displayName: String? = nil,
        contentHash: String? = nil,
        status: String = "completed",
        chunksStored: Int = 0,
        totalChunks: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.sourceType = sourceType
        self.sourceUri = sourceUri
        self.displayName = displayName
        self.contentHash = contentHash
        self.status = status
        self.chunksStored = chunksStored
        self.totalChunks = totalChunks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case projectId = "project_id"
        case sourceType = "source_type"
        case sourceUri = "source_uri"
        case displayName = "display_name"
        case contentHash = "content_hash"
        case chunksStored = "chunks_stored"
        case totalChunks = "total_chunks"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response from POST /api/ingest.
public struct IngestResponse: Codable, Equatable, Sendable {
    public let sourceId: UUID
    public let stored: Int
    public let skippedDuplicates: Int

    public init(sourceId: UUID, stored: Int, skippedDuplicates: Int) {
        self.sourceId = sourceId
        self.stored = stored
        self.skippedDuplicates = skippedDuplicates
    }

    enum CodingKeys: String, CodingKey {
        case stored
        case sourceId = "source_id"
        case skippedDuplicates = "skipped_duplicates"
    }
}
