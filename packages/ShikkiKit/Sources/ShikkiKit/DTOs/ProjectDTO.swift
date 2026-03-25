import Foundation

/// Maps to the `projects` table in the PostgreSQL schema.
public struct ProjectDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let slug: String
    public let name: String
    public let description: String?
    public let repoUrl: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let metadata: [String: AnyCodable]

    public init(
        id: UUID,
        slug: String,
        name: String,
        description: String? = nil,
        repoUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.repoUrl = repoUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description
        case repoUrl = "repo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case metadata
    }
}
