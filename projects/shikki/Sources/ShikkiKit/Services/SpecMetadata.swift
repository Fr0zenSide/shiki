import Foundation

// MARK: - Spec Lifecycle

/// All lifecycle states a spec can be in.
///
/// ```
/// DRAFT -> REVIEW -> PARTIAL -> VALIDATED -> IMPLEMENTING -> SHIPPED -> ARCHIVED
///   |        |        |           |             |              |
///   |        |        |           +-> REJECTED  |              |
///   +--------+--------+-----------+-> OUTDATED  +--------------+-> OUTDATED
/// ```
public enum SpecLifecycle: String, Sendable, Codable, CaseIterable {
    case draft
    case review
    case partial
    case validated
    case implementing
    case shipped
    case archived
    case rejected
    case outdated

    /// Valid forward transitions from this state.
    public var validTransitions: Set<SpecLifecycle> {
        switch self {
        case .draft:
            return [.review, .outdated]
        case .review:
            return [.partial, .validated, .outdated]
        case .partial:
            return [.review, .validated, .outdated]
        case .validated:
            return [.implementing, .rejected, .outdated]
        case .implementing:
            return [.shipped, .outdated]
        case .shipped:
            return [.archived, .outdated]
        case .archived:
            return [.outdated]
        case .rejected:
            return [.outdated]
        case .outdated:
            return []
        }
    }

    /// Whether a transition to the given state is allowed.
    public func canTransition(to target: SpecLifecycle) -> Bool {
        validTransitions.contains(target)
    }
}

// MARK: - Reviewer Verdict

/// Verdict a reviewer can give to a spec (or part of it).
public enum ReviewerVerdict: String, Sendable, Codable, CaseIterable {
    case pending
    case reading
    case partial
    case validated
    case rework
}

// MARK: - Reviewer Entry

/// A single reviewer's status for a spec.
public struct ReviewerEntry: Sendable, Equatable {
    /// Who reviewed (e.g. "@Daimyo").
    public let who: String
    /// Date of the review (nil if not yet reviewed).
    public let date: String?
    /// Current verdict.
    public let verdict: ReviewerVerdict
    /// Anchor bookmark where the reviewer stopped (nil = reviewed everything).
    public let anchor: String?
    /// Section numbers that passed validation.
    public let sectionsValidated: [Int]
    /// Section numbers that need rework.
    public let sectionsRework: [Int]
    /// Free-form notes.
    public let notes: String?

    public init(
        who: String,
        date: String? = nil,
        verdict: ReviewerVerdict = .pending,
        anchor: String? = nil,
        sectionsValidated: [Int] = [],
        sectionsRework: [Int] = [],
        notes: String? = nil
    ) {
        self.who = who
        self.date = date
        self.verdict = verdict
        self.anchor = anchor
        self.sectionsValidated = sectionsValidated
        self.sectionsRework = sectionsRework
        self.notes = notes
    }
}

// MARK: - Flsh Block

/// Voice-compatibility metadata for Flsh integration.
public struct FlshBlock: Sendable, Equatable {
    /// One-sentence TTS-friendly summary.
    public let summary: String?
    /// Estimated read-aloud duration (e.g. "8m").
    public let duration: String?
    /// Section count for voice navigation.
    public let sections: Int?

    public init(summary: String? = nil, duration: String? = nil, sections: Int? = nil) {
        self.summary = summary
        self.duration = duration
        self.sections = sections
    }
}

// MARK: - Spec Metadata

/// Parsed metadata from an enhanced spec frontmatter.
///
/// Captures all fields from the Spec Metadata v2 enhanced YAML frontmatter:
/// title, status, progress, priority, project, dates, authors, reviewers,
/// dependencies, relations, tags, and the flsh voice-compatibility block.
public struct SpecMetadata: Sendable, Equatable {
    public let title: String
    public let status: SpecLifecycle
    /// Progress in "N/M" format (sections reviewed / total sections).
    public let progress: String?
    public let priority: String?
    public let project: String?
    public let created: String?
    public let updated: String?
    public let authors: String?
    public let reviewers: [ReviewerEntry]
    public let dependsOn: [String]
    public let relatesTo: [String]
    public let tags: [String]
    public let flsh: FlshBlock?
    /// Total `##` heading count computed from the markdown body.
    public let totalSections: Int

    public init(
        title: String,
        status: SpecLifecycle = .draft,
        progress: String? = nil,
        priority: String? = nil,
        project: String? = nil,
        created: String? = nil,
        updated: String? = nil,
        authors: String? = nil,
        reviewers: [ReviewerEntry] = [],
        dependsOn: [String] = [],
        relatesTo: [String] = [],
        tags: [String] = [],
        flsh: FlshBlock? = nil,
        totalSections: Int = 0
    ) {
        self.title = title
        self.status = status
        self.progress = progress
        self.priority = priority
        self.project = project
        self.created = created
        self.updated = updated
        self.authors = authors
        self.reviewers = reviewers
        self.dependsOn = dependsOn
        self.relatesTo = relatesTo
        self.tags = tags
        self.flsh = flsh
        self.totalSections = totalSections
    }
}
