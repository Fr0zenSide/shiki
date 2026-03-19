import Foundation

// MARK: - Observatory Tab

public enum ObservatoryTab: String, Sendable, CaseIterable {
    case timeline
    case decisions
    case questions
    case reports
}

// MARK: - Timeline Entry

public struct ObservatoryEntry: Sendable {
    public let timestamp: Date
    public let icon: String
    public let significance: EventSignificance
    public let title: String
    public let detail: String

    public init(timestamp: Date, icon: String, significance: EventSignificance, title: String, detail: String) {
        self.timestamp = timestamp
        self.icon = icon
        self.significance = significance
        self.title = title
        self.detail = detail
    }

    /// Create a timeline entry from a router envelope.
    public static func from(envelope: RouterEnvelope) -> ObservatoryEntry {
        let icon: String
        switch envelope.significance {
        case .critical: icon = "▲▲"
        case .alert: icon = "▲"
        case .decision: icon = "◆"
        case .milestone: icon = "★"
        case .progress: icon = "●"
        case .background: icon = "○"
        case .noise: icon = "·"
        }

        return ObservatoryEntry(
            timestamp: envelope.event.timestamp,
            icon: icon,
            significance: envelope.significance,
            title: "\(envelope.event.type)",
            detail: envelope.context.companySlug ?? ""
        )
    }
}

// MARK: - Agent Report Card

public struct AgentReportCard: Sendable {
    public let sessionId: String
    public let persona: AgentPersona
    public let companySlug: String
    public let taskTitle: String
    public let duration: TimeInterval
    public let beforeState: String
    public let afterState: String
    public let filesChanged: Int
    public let testsAdded: Int
    public let keyDecisions: [String]
    public let redFlags: [String]
    public let status: AgentReportStatus

    public init(
        sessionId: String, persona: AgentPersona, companySlug: String,
        taskTitle: String, duration: TimeInterval, beforeState: String,
        afterState: String, filesChanged: Int, testsAdded: Int,
        keyDecisions: [String], redFlags: [String], status: AgentReportStatus
    ) {
        self.sessionId = sessionId
        self.persona = persona
        self.companySlug = companySlug
        self.taskTitle = taskTitle
        self.duration = duration
        self.beforeState = beforeState
        self.afterState = afterState
        self.filesChanged = filesChanged
        self.testsAdded = testsAdded
        self.keyDecisions = keyDecisions
        self.redFlags = redFlags
        self.status = status
    }
}

public enum AgentReportStatus: Int, Sendable, Comparable {
    case running = 0
    case blocked = 1
    case completed = 2
    case failed = 3

    public static func < (lhs: AgentReportStatus, rhs: AgentReportStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Pending Question

public struct PendingQuestion: Sendable {
    public let sessionId: String
    public let question: String
    public let context: String
    public let askedAt: Date
    public var answer: String?

    public init(sessionId: String, question: String, context: String, askedAt: Date, answer: String? = nil) {
        self.sessionId = sessionId
        self.question = question
        self.context = context
        self.askedAt = askedAt
        self.answer = answer
    }
}

// MARK: - Heatmap

public enum ObservatoryHeatmap {

    public static func icon(for significance: EventSignificance) -> String {
        switch significance {
        case .critical: "▲▲"
        case .alert: "▲"
        case .decision, .milestone: "●"
        case .progress: "○"
        case .background, .noise: "·"
        }
    }

    public static func color(for significance: EventSignificance) -> String {
        switch significance {
        case .critical: "\u{1B}[1m\u{1B}[31m"    // bold red
        case .alert: "\u{1B}[31m"                  // red
        case .decision: "\u{1B}[1m\u{1B}[33m"     // bold yellow
        case .milestone: "\u{1B}[1m\u{1B}[32m"    // bold green
        case .progress: "\u{1B}[36m"               // cyan
        case .background: "\u{1B}[2m"              // dim
        case .noise: "\u{1B}[2m"                   // dim
        }
    }
}

// MARK: - Observatory Engine

/// State machine for the Observatory TUI.
public struct ObservatoryEngine {
    public private(set) var currentTab: ObservatoryTab = .timeline
    public private(set) var selectedIndex: Int = 0

    private var allEntries: [ObservatoryEntry] = []
    public private(set) var reports: [AgentReportCard] = []
    public private(set) var pendingQuestions: [PendingQuestion] = []
    public private(set) var answeredQuestions: [PendingQuestion] = []

    public init() {}

    // MARK: - Tab Navigation

    public mutating func nextTab() {
        let tabs = ObservatoryTab.allCases
        let idx = tabs.firstIndex(of: currentTab)!
        currentTab = tabs[(idx + 1) % tabs.count]
        selectedIndex = 0
    }

    public mutating func previousTab() {
        let tabs = ObservatoryTab.allCases
        let idx = tabs.firstIndex(of: currentTab)!
        currentTab = tabs[(idx - 1 + tabs.count) % tabs.count]
        selectedIndex = 0
    }

    // MARK: - Selection Navigation

    public mutating func moveDown() {
        let maxIndex = currentListCount - 1
        if selectedIndex < maxIndex { selectedIndex += 1 }
    }

    public mutating func moveUp() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    private var currentListCount: Int {
        switch currentTab {
        case .timeline: timelineEntries.count
        case .decisions: timelineEntries.filter { $0.significance == .decision }.count
        case .questions: pendingQuestions.count
        case .reports: reports.count
        }
    }

    // MARK: - Timeline

    /// Filtered timeline: only significant events (no noise, no background).
    public var timelineEntries: [ObservatoryEntry] {
        allEntries
            .filter { $0.significance >= .progress }
            .sorted { $0.timestamp > $1.timestamp }
    }

    public mutating func addTimelineEntry(_ entry: ObservatoryEntry) {
        allEntries.append(entry)
    }

    // MARK: - Reports

    public mutating func addReport(_ report: AgentReportCard) {
        reports.append(report)
        reports.sort { $0.status < $1.status } // running first
    }

    // MARK: - Questions

    public mutating func addQuestion(_ question: PendingQuestion) {
        pendingQuestions.append(question)
    }

    public mutating func answerQuestion(at index: Int, answer: String) {
        guard pendingQuestions.indices.contains(index) else { return }
        var q = pendingQuestions.remove(at: index)
        q.answer = answer
        answeredQuestions.append(q)
    }
}
