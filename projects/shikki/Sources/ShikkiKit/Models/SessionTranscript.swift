import Foundation

/// Structured capture of a completed Claude task session.
///
/// Stored in `session_transcripts` table. Contains the session's plan output,
/// files changed, test results, PRs created, decisions made, and optionally
/// the raw terminal log. Queryable by company, task, or phase.
public struct SessionTranscript: Codable, Sendable {
    public let id: String
    public let companyId: String
    public let taskId: String?
    public let sessionId: String
    public let companySlug: String
    public let taskTitle: String
    public let projectPath: String?

    public let summary: String?
    public let planOutput: String?
    public let filesChanged: [String]
    public let testResults: String?
    public let prsCreated: [String]
    public let decisions: [AnyCodable]
    public let errors: [String]

    public let phase: String
    public let durationMinutes: Int?
    public let contextPct: Int?
    public let compactionCount: Int

    public let rawLog: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, summary, phase, errors, decisions
        case companyId = "company_id"
        case taskId = "task_id"
        case sessionId = "session_id"
        case companySlug = "company_slug"
        case taskTitle = "task_title"
        case projectPath = "project_path"
        case planOutput = "plan_output"
        case filesChanged = "files_changed"
        case testResults = "test_results"
        case prsCreated = "prs_created"
        case durationMinutes = "duration_minutes"
        case contextPct = "context_pct"
        case compactionCount = "compaction_count"
        case rawLog = "raw_log"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        companyId = try container.decode(String.self, forKey: .companyId)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        companySlug = try container.decode(String.self, forKey: .companySlug)
        taskTitle = try container.decode(String.self, forKey: .taskTitle)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        planOutput = try container.decodeIfPresent(String.self, forKey: .planOutput)
        filesChanged = (try? container.decode([String].self, forKey: .filesChanged)) ?? []
        testResults = try container.decodeIfPresent(String.self, forKey: .testResults)
        prsCreated = (try? container.decode([String].self, forKey: .prsCreated)) ?? []
        decisions = (try? container.decode([AnyCodable].self, forKey: .decisions)) ?? []
        errors = (try? container.decode([String].self, forKey: .errors)) ?? []
        phase = try container.decode(String.self, forKey: .phase)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        contextPct = try container.decodeIfPresent(Int.self, forKey: .contextPct)
        compactionCount = (try? container.decode(Int.self, forKey: .compactionCount)) ?? 0
        rawLog = try container.decodeIfPresent(String.self, forKey: .rawLog)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}
