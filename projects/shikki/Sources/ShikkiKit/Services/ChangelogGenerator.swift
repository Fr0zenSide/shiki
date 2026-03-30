import Foundation

// MARK: - Changelog Types

/// A section in the changelog (e.g. "Added", "Fixed").
public struct ChangelogSection: Sendable {
    public let title: String
    public let entries: [String]

    public init(title: String, entries: [String]) {
        self.title = title
        self.entries = entries
    }
}

/// A complete changelog with grouped sections.
public struct Changelog: Sendable {
    public let sections: [ChangelogSection]

    public init(sections: [ChangelogSection]) {
        self.sections = sections
    }

    /// Render as markdown string.
    public var markdown: String {
        sections.map { section in
            var lines = ["### \(section.title)"]
            for entry in section.entries {
                lines.append("- \(entry)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

// MARK: - ChangelogGenerator

/// Groups conventional commits by prefix into changelog sections.
/// feat: -> Added, fix: -> Fixed, refactor: -> Changed, chore: -> Maintenance.
/// Falls back to raw "Changes" section if no conventional prefixes found.
public struct ChangelogGenerator: Sendable {

    public init() {}

    /// Generate a structured changelog from commit subject lines.
    public func generate(from commits: [String]) -> Changelog {
        var added: [String] = []
        var changed: [String] = []
        var fixed: [String] = []
        var maintenance: [String] = []
        var uncategorized: [String] = []

        for commit in commits {
            if let (category, message) = parseConventionalCommit(commit) {
                switch category {
                case "feat":
                    added.append(message)
                case "fix":
                    fixed.append(message)
                case "refactor":
                    changed.append(message)
                case "build", "chore", "ci", "docs", "perf", "style", "test":
                    maintenance.append(message)
                default:
                    uncategorized.append(commit)
                }
            } else {
                uncategorized.append(commit)
            }
        }

        let hasConventional = !added.isEmpty || !changed.isEmpty || !fixed.isEmpty || !maintenance.isEmpty
        if !hasConventional {
            return Changelog(sections: [
                ChangelogSection(title: "Changes", entries: uncategorized),
            ])
        }

        var sections: [ChangelogSection] = []
        if !added.isEmpty { sections.append(ChangelogSection(title: "Added", entries: added)) }
        if !fixed.isEmpty { sections.append(ChangelogSection(title: "Fixed", entries: fixed)) }
        if !changed.isEmpty { sections.append(ChangelogSection(title: "Changed", entries: changed)) }
        if !maintenance.isEmpty { sections.append(ChangelogSection(title: "Maintenance", entries: maintenance)) }
        if !uncategorized.isEmpty { sections.append(ChangelogSection(title: "Other", entries: uncategorized)) }

        return Changelog(sections: sections)
    }

    // MARK: - Private

    /// Parse a conventional commit: "type(scope): message" or "type: message"
    private func parseConventionalCommit(_ commit: String) -> (String, String)? {
        let pattern = /^(\w+)(?:\([^)]*\))?!?:\s*(.+)$/
        guard let match = commit.firstMatch(of: pattern) else {
            return nil
        }

        let type = String(match.1).lowercased()
        let message = String(match.2)

        let knownTypes: Set<String> = [
            "build", "chore", "ci", "docs", "feat", "fix",
            "perf", "refactor", "style", "test",
        ]
        guard knownTypes.contains(type) else {
            return nil
        }

        return (type, message)
    }
}
