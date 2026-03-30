import Foundation

/// A project linked to a company via the `company_projects` join table.
///
/// Enables the 1-company → N-projects relationship. Each link has a `role`:
/// - `"primary"`: the company's main project (migrated from the legacy 1:1 `companies.project_id`).
/// - `"member"`:  the company contributes to this project (e.g. shared SPM packages).
///
/// Decoded from the `company_projects` JSONB aggregate in the `company_status` view.
public struct CompanyProject: Codable, Sendable {
    /// UUID of the linked project.
    public let projectId: String
    /// URL-safe project identifier (e.g. `"wabisabi"`, `"kintsugi-ds"`).
    public let projectSlug: String
    /// Relationship role: `"primary"` or `"member"`.
    public let role: String
    /// Per-link configuration overrides (currently unused, reserved for future use).
    public let config: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case projectSlug = "project_slug"
        case role, config
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try container.decode(String.self, forKey: .projectId)
        projectSlug = try container.decode(String.self, forKey: .projectSlug)
        role = try container.decode(String.self, forKey: .role)
        config = (try? container.decode([String: AnyCodable].self, forKey: .config)) ?? [:]
    }
}
