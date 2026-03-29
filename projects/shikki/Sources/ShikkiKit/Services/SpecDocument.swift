import Foundation

// MARK: - SpecDocument

/// A living spec document for a dispatched task.
/// Generated on dispatch, updated as agents work, serves as recovery point after context resets.
/// Stored at `.shiki/specs/{task-id}.md`.
public struct SpecDocument: Codable, Sendable {
    public let taskId: String
    public let title: String
    public let companySlug: String
    public let branch: String
    public let createdAt: Date
    public var requirements: [Requirement] = []
    public var phases: [Phase] = []
    public var decisions: [Decision] = []
    public var notes: [String] = []

    public init(
        taskId: String, title: String,
        companySlug: String, branch: String,
        createdAt: Date = Date()
    ) {
        self.taskId = taskId
        self.title = title
        self.companySlug = companySlug
        self.branch = branch
        self.createdAt = createdAt
    }

    // MARK: - Requirements

    public mutating func addRequirement(_ text: String) {
        requirements.append(Requirement(text: text))
    }

    public mutating func completeRequirement(at index: Int) {
        guard requirements.indices.contains(index) else { return }
        requirements[index].completed = true
    }

    // MARK: - Phases

    public mutating func addPhase(name: String, status: PhaseStatus = .pending) {
        phases.append(Phase(name: name, status: status))
    }

    public mutating func updatePhase(at index: Int, status: PhaseStatus) {
        guard phases.indices.contains(index) else { return }
        phases[index].status = status
    }

    // MARK: - Decisions

    public mutating func addDecision(question: String, answer: String, rationale: String? = nil) {
        decisions.append(Decision(question: question, answer: answer, rationale: rationale))
    }

    // MARK: - Render

    /// Render the spec as markdown.
    public func render() -> String {
        var lines: [String] = []

        lines.append("# \(title)")
        lines.append("")
        lines.append("> Task: \(taskId)")
        lines.append("> Company: \(companySlug)")
        lines.append("> Branch: \(branch)")
        lines.append("")

        // Requirements
        lines.append("## Requirements")
        lines.append("")
        if requirements.isEmpty {
            lines.append("_No requirements yet._")
        } else {
            for req in requirements {
                let check = req.completed ? "x" : " "
                lines.append("- [\(check)] \(req.text)")
            }
        }
        lines.append("")

        // Implementation Plan
        lines.append("## Implementation Plan")
        lines.append("")
        if phases.isEmpty {
            lines.append("_No phases defined yet._")
        } else {
            for phase in phases {
                lines.append("- \(phase.name) [\(phase.status.label)]")
            }
        }
        lines.append("")

        // Decisions
        lines.append("## Decisions")
        lines.append("")
        if decisions.isEmpty {
            lines.append("_No decisions recorded yet._")
        } else {
            for (i, d) in decisions.enumerated() {
                if i > 0 { lines.append("") }
                lines.append("**Q:** \(d.question)")
                lines.append("**A:** \(d.answer)")
                if let rationale = d.rationale {
                    lines.append("_Rationale:_ \(rationale)")
                }
            }
        }
        lines.append("")

        // Notes
        if !notes.isEmpty {
            lines.append("## Notes")
            lines.append("")
            for note in notes {
                lines.append("- \(note)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - File I/O

    /// Write the rendered markdown to a file.
    public func write(to path: String) throws {
        let content = render()
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Read a spec from a JSON file (not markdown — for state persistence).
    public static func load(from path: String) throws -> SpecDocument {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(SpecDocument.self, from: data)
    }

    /// Save the spec as JSON for state persistence.
    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Sub-types

extension SpecDocument {
    public struct Requirement: Codable, Sendable {
        public var text: String
        public var completed: Bool

        public init(text: String, completed: Bool = false) {
            self.text = text
            self.completed = completed
        }
    }

    public struct Phase: Codable, Sendable {
        public var name: String
        public var status: PhaseStatus

        public init(name: String, status: PhaseStatus = .pending) {
            self.name = name
            self.status = status
        }
    }

    public struct Decision: Codable, Sendable {
        public let question: String
        public let answer: String
        public let rationale: String?

        public init(question: String, answer: String, rationale: String? = nil) {
            self.question = question
            self.answer = answer
            self.rationale = rationale
        }
    }
}

public enum PhaseStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case blocked

    public var label: String {
        switch self {
        case .pending: "PENDING"
        case .inProgress: "IN PROGRESS"
        case .completed: "COMPLETED"
        case .blocked: "BLOCKED"
        }
    }
}
