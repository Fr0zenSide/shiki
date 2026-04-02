import Foundation

// MARK: - SpecLifecycleStatus

/// Lifecycle states for a spec file, per Spec Metadata v2.
/// Transition graph:
///   DRAFT -> REVIEW -> PARTIAL -> VALIDATED -> IMPLEMENTING -> SHIPPED -> ARCHIVED
///   VALIDATED -> REJECTED
///   ANY -> OUTDATED
public enum SpecLifecycleStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case review
    case partial
    case validated
    case implementing
    case shipped
    case archived
    case rejected
    case outdated

    /// Display marker for TUI output.
    /// SF Symbols: 􁁛 validated, 􀢄 partial/rework, 􀟈 draft, ◇ implementing, ◆ shipped.
    public var marker: String {
        switch self {
        case .validated:    return "\u{10C05B}"  // 􁁛
        case .partial:      return "\u{100904}"  // 􀢄
        case .draft:        return "\u{1007C8}"  // 􀟈
        case .implementing: return "\u{25C7}"    // ◇
        case .shipped:      return "\u{25C6}"    // ◆
        case .review:       return "\u{1007C8}"  // 􀟈
        case .archived:     return "\u{25C6}"    // ◆
        case .rejected:     return "\u{100904}"  // 􀢄
        case .outdated:     return "\u{100904}"  // 􀢄
        }
    }

    /// Valid forward transitions per the lifecycle graph.
    public var validTransitions: Set<SpecLifecycleStatus> {
        switch self {
        case .draft:        return [.review, .outdated]
        case .review:       return [.partial, .validated, .draft, .outdated]
        case .partial:      return [.review, .validated, .outdated]
        case .validated:    return [.implementing, .rejected, .outdated]
        case .implementing: return [.shipped, .validated, .outdated]
        case .shipped:      return [.archived, .outdated]
        case .archived:     return [.outdated]
        case .rejected:     return [.draft, .outdated]
        case .outdated:     return []
        }
    }

    /// Whether a transition to the given status is allowed.
    public func canTransition(to target: SpecLifecycleStatus) -> Bool {
        validTransitions.contains(target)
    }
}

// MARK: - SpecReviewerVerdict

/// Per-reviewer verdict on a spec.
public enum SpecReviewerVerdict: String, Codable, Sendable, CaseIterable {
    case pending
    case reading
    case partial
    case validated
    case rework
}

// MARK: - SpecReviewer

/// A reviewer entry in the spec frontmatter.
public struct SpecReviewer: Codable, Sendable, Equatable {
    public var who: String
    public var date: String?
    public var verdict: SpecReviewerVerdict
    public var anchor: String?
    public var sectionsValidated: [Int]?
    public var sectionsRework: [Int]?
    public var notes: String?

    public init(
        who: String,
        date: String? = nil,
        verdict: SpecReviewerVerdict = .pending,
        anchor: String? = nil,
        sectionsValidated: [Int]? = nil,
        sectionsRework: [Int]? = nil,
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

    enum CodingKeys: String, CodingKey {
        case who, date, verdict, anchor, notes
        case sectionsValidated = "sections_validated"
        case sectionsRework = "sections_rework"
    }
}

// MARK: - SpecFlshBlock

/// Flsh (voice AI) compatibility block.
public struct SpecFlshBlock: Codable, Sendable, Equatable {
    public var summary: String
    public var duration: String?
    public var sections: Int?

    public init(summary: String, duration: String? = nil, sections: Int? = nil) {
        self.summary = summary
        self.duration = duration
        self.sections = sections
    }
}

// MARK: - SpecMetadata

/// Enhanced frontmatter metadata for a spec file (Spec Metadata v2).
public struct SpecMetadata: Codable, Sendable, Equatable {
    public var title: String
    public var status: SpecLifecycleStatus
    public var progress: String?
    public var priority: String?
    public var project: String?
    public var created: String?
    public var updated: String?
    public var authors: String?
    public var reviewers: [SpecReviewer]
    public var dependsOn: [String]?
    public var relatesTo: [String]?
    public var tags: [String]?
    public var flsh: SpecFlshBlock?

    /// The git branch name for the epic this spec belongs to.
    public var epicBranch: String?
    /// The git commit hash at which this spec was validated.
    public var validatedCommit: String?
    /// The test run identifier that verified this spec's implementation.
    public var testRunId: String?

    /// The filename (not full path) of the spec, set during parsing.
    public var filename: String?

    /// Total `##` heading count computed from the markdown body.
    public var totalSections: Int

    public init(
        title: String,
        status: SpecLifecycleStatus = .draft,
        progress: String? = nil,
        priority: String? = nil,
        project: String? = nil,
        created: String? = nil,
        updated: String? = nil,
        authors: String? = nil,
        reviewers: [SpecReviewer] = [],
        dependsOn: [String]? = nil,
        relatesTo: [String]? = nil,
        tags: [String]? = nil,
        flsh: SpecFlshBlock? = nil,
        epicBranch: String? = nil,
        validatedCommit: String? = nil,
        testRunId: String? = nil,
        filename: String? = nil,
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
        self.epicBranch = epicBranch
        self.validatedCommit = validatedCommit
        self.testRunId = testRunId
        self.filename = filename
        self.totalSections = totalSections
    }

    enum CodingKeys: String, CodingKey {
        case title, status, progress, priority, project, created, updated
        case authors, reviewers, tags, flsh, filename, totalSections
        case dependsOn = "depends-on"
        case relatesTo = "relates-to"
        case epicBranch = "epic-branch"
        case validatedCommit = "validated-commit"
        case testRunId = "test-run-id"
    }

    // MARK: - Computed

    /// Parsed progress as (reviewed, total). Returns nil if progress format is invalid.
    public var progressParsed: (reviewed: Int, total: Int)? {
        guard let progress else { return nil }
        let parts = progress.split(separator: "/")
        guard parts.count == 2,
              let reviewed = Int(parts[0]),
              let total = Int(parts[1]) else { return nil }
        return (reviewed, total)
    }

    /// The primary reviewer (first one with a non-pending verdict, or first overall).
    public var primaryReviewer: SpecReviewer? {
        reviewers.first { $0.verdict != .pending } ?? reviewers.first
    }

    /// Latest reviewer date (for display).
    public var latestReviewDate: String? {
        reviewers.compactMap(\.date).sorted().last
    }
}
