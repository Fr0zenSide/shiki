import Foundation

/// Fetches open PRs from GitHub via `gh pr list` CLI.
/// Company detection: parses branch name prefix (e.g. "maya/feature-x" = maya).
public struct PRInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .pr }

    private let shellRunner: ShellRunner

    public init(shellRunner: ShellRunner = DefaultShellRunner()) {
        self.shellRunner = shellRunner
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        // Skip if type filter excludes PRs
        if let types = filters.types, !types.contains(.pr) { return [] }

        let json = try shellRunner.run(
            "/usr/bin/env",
            arguments: [
                "gh", "pr", "list",
                "--json", "number,title,createdAt,headRefName,author,additions,deletions,files",
                "--limit", "50",
            ]
        )

        guard let data = json.data(using: .utf8) else { return [] }
        let prs = try JSONDecoder.iso8601Flexible.decode([GitHubPR].self, from: data)

        return prs.compactMap { pr in
            let company = detectCompany(branch: pr.headRefName)

            // Apply company filter
            if let slugFilter = filters.companySlug, company != slugFilter {
                return nil
            }

            let age = pr.age
            let filesChanged = pr.files?.count ?? (pr.additions + pr.deletions > 0 ? 1 : 0)
            let priorityWeight = UrgencyCalculator.prPriorityWeight(filesChanged: filesChanged)
            let urgency = UrgencyCalculator.score(age: age, priorityWeight: priorityWeight, isBlocking: false)

            return InboxItem(
                id: "pr:\(pr.number)",
                type: .pr,
                title: pr.title,
                subtitle: pr.headRefName,
                age: age,
                companySlug: company,
                urgencyScore: urgency,
                metadata: [
                    "number": "\(pr.number)",
                    "branch": pr.headRefName,
                    "author": pr.author?.login ?? "unknown",
                    "additions": "\(pr.additions)",
                    "deletions": "\(pr.deletions)",
                    "filesChanged": "\(filesChanged)",
                ]
            )
        }
    }

    /// Detect company from branch name prefix.
    /// Examples: "maya/feature-x" -> "maya", "shiki/fix-bug" -> "shiki"
    func detectCompany(branch: String) -> String? {
        let parts = branch.split(separator: "/", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let prefix = String(parts[0]).lowercased()
        // Common branch prefixes that are NOT company names
        let nonCompanyPrefixes: Set<String> = [
            "feature", "fix", "bugfix", "hotfix", "release",
            "chore", "docs", "test", "refactor", "story",
            "dependabot", "renovate",
        ]
        return nonCompanyPrefixes.contains(prefix) ? nil : prefix
    }
}

// MARK: - GitHub PR JSON Model

struct GitHubPR: Codable, Sendable {
    let number: Int
    let title: String
    let createdAt: String
    let headRefName: String
    let author: GitHubAuthor?
    let additions: Int
    let deletions: Int
    let files: [GitHubFile]?

    var age: TimeInterval {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt) else { return 0 }
        return Date().timeIntervalSince(date)
    }
}

struct GitHubAuthor: Codable, Sendable {
    let login: String
}

struct GitHubFile: Codable, Sendable {
    let path: String
    let additions: Int
    let deletions: Int
}

// MARK: - Shell Runner Protocol (for testability)

public protocol ShellRunner: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> String
}

public struct DefaultShellRunner: ShellRunner, Sendable {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InboxError.shellCommandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: Int(process.terminationStatus)
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Flexible ISO8601 Decoder

extension JSONDecoder {
    static let iso8601Flexible: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()
}

// MARK: - Inbox Errors

public enum InboxError: Error, LocalizedError {
    case shellCommandFailed(command: String, exitCode: Int)
    case noSourcesConfigured

    public var errorDescription: String? {
        switch self {
        case .shellCommandFailed(let cmd, let code):
            return "Shell command failed (exit \(code)): \(cmd)"
        case .noSourcesConfigured:
            return "No inbox data sources configured"
        }
    }
}
