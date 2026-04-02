import Foundation

public struct DailyReport: Codable, Sendable {
    public let date: String
    public let perCompany: [CompanyReport]
    public let blocked: [BlockedTask]
    public let prsCreated: [PullRequest]

    enum CodingKeys: String, CodingKey {
        case date
        case perCompany = "perCompany"
        case blocked
        case prsCreated = "prsCreated"
    }

    public struct CompanyReport: Codable, Sendable {
        public let slug: String
        public let displayName: String
        public let tasksCompleted: Int
        public let tasksFailed: Int
        public let decisionsAsked: Int
        public let decisionsAnswered: Int
        public let spendUsd: Double

        enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
            case tasksCompleted = "tasks_completed"
            case tasksFailed = "tasks_failed"
            case decisionsAsked = "decisions_asked"
            case decisionsAnswered = "decisions_answered"
            case spendUsd = "spend_usd"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slug = try container.decode(String.self, forKey: .slug)
            displayName = try container.decode(String.self, forKey: .displayName)
            tasksCompleted = try Self.intOrString(from: container, forKey: .tasksCompleted)
            tasksFailed = try Self.intOrString(from: container, forKey: .tasksFailed)
            decisionsAsked = try Self.intOrString(from: container, forKey: .decisionsAsked)
            decisionsAnswered = try Self.intOrString(from: container, forKey: .decisionsAnswered)
            if let d = try? container.decode(Double.self, forKey: .spendUsd) {
                spendUsd = d
            } else {
                let s = try container.decode(String.self, forKey: .spendUsd)
                spendUsd = Double(s) ?? 0
            }
        }

        private static func intOrString(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Int {
            if let v = try? container.decode(Int.self, forKey: key) { return v }
            let s = try container.decode(String.self, forKey: key)
            return Int(s) ?? 0
        }
    }

    public struct BlockedTask: Codable, Sendable {
        public let title: String
        public let status: String
        public let companySlug: String
        public let question: String?
        public let tier: Int?

        enum CodingKeys: String, CodingKey {
            case title, status, question, tier
            case companySlug = "company_slug"
        }
    }

    public struct PullRequest: Codable, Sendable {
        public let branch: String?
        public let title: String?
        public let prUrl: String?
        public let projectSlug: String?

        enum CodingKeys: String, CodingKey {
            case branch, title
            case prUrl = "pr_url"
            case projectSlug = "project_slug"
        }
    }
}
