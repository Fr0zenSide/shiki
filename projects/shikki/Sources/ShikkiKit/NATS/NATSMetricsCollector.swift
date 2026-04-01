import Foundation

// MARK: - MetricsWindow

/// Predefined time windows for sliding-window counters.
public enum MetricsWindow: String, Sendable, CaseIterable, Codable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case oneHour = "1h"
    case twentyFourHours = "24h"

    /// Duration in seconds for each window.
    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .oneHour: return 3_600
        case .twentyFourHours: return 86_400
        }
    }
}

// MARK: - WindowedCounter

/// A counter that tracks timestamped entries and can report counts
/// within a sliding time window. Entries older than the window are pruned
/// on access.
public struct WindowedCounter: Sendable {
    private var timestamps: [Date]

    public init() {
        self.timestamps = []
    }

    /// Record an event at the given time.
    public mutating func record(at date: Date = Date()) {
        timestamps.append(date)
    }

    /// Count of events within the window ending at `now`.
    public func count(window: MetricsWindow, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-window.seconds)
        return timestamps.filter { $0 >= cutoff }.count
    }

    /// Rate (events per second) within the window.
    public func rate(window: MetricsWindow, now: Date = Date()) -> Double {
        let c = count(window: window, now: now)
        return Double(c) / window.seconds
    }

    /// Prune entries older than the largest window (24h).
    public mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-MetricsWindow.twentyFourHours.seconds)
        timestamps.removeAll { $0 < cutoff }
    }

    /// Total entries (before pruning).
    public var total: Int { timestamps.count }
}

// MARK: - SubjectMetrics

/// Per-subject message rate metrics across all time windows.
public struct SubjectMetrics: Sendable, Codable {
    public let subject: String
    public let rates: [String: Double]  // window label -> events/sec
    public let counts: [String: Int]    // window label -> event count

    public init(subject: String, rates: [String: Double], counts: [String: Int]) {
        self.subject = subject
        self.rates = rates
        self.counts = counts
    }
}

// MARK: - AgentUtilization

/// Tracks agent activity for utilization reporting.
public struct AgentUtilization: Sendable, Codable, Equatable {
    public let agentId: String
    public let company: String
    public var dispatched: Int
    public var completed: Int
    public var failed: Int
    public var totalDurationSeconds: Double
    public var lastSeen: Date

    public init(
        agentId: String,
        company: String,
        dispatched: Int = 0,
        completed: Int = 0,
        failed: Int = 0,
        totalDurationSeconds: Double = 0,
        lastSeen: Date = Date()
    ) {
        self.agentId = agentId
        self.company = company
        self.dispatched = dispatched
        self.completed = completed
        self.failed = failed
        self.totalDurationSeconds = totalDurationSeconds
        self.lastSeen = lastSeen
    }

    /// Completion rate as a percentage (0-100).
    public var completionRate: Int {
        guard dispatched > 0 else { return 0 }
        return (completed * 100) / dispatched
    }
}

// MARK: - NATSMetricsCollector

/// Actor that collects sliding-window metrics from NATS events.
///
/// Tracks:
/// - Per-subject message rates (1m, 5m, 1h, 24h windows)
/// - Per-company event counts
/// - Agent utilization (dispatch/complete/fail)
///
/// Used by `NATSReportAggregator` for live metrics overlay on reports.
public actor NATSMetricsCollector {
    /// Per-subject counters.
    private var subjectCounters: [String: WindowedCounter] = [:]

    /// Per-company counters (aggregated across all subjects for that company).
    private var companyCounters: [String: WindowedCounter] = [:]

    /// Agent utilization tracking.
    private var agents: [String: AgentUtilization] = [:]

    /// Global event counter.
    private var globalCounter = WindowedCounter()

    public init() {}

    // MARK: - Recording

    /// Record an event from a NATS subject.
    /// Extracts the company slug from the subject (e.g. `shikki.events.maya.agent` -> `maya`).
    public func record(subject: String, at date: Date = Date()) {
        // Global
        globalCounter.record(at: date)

        // Per-subject
        var counter = subjectCounters[subject] ?? WindowedCounter()
        counter.record(at: date)
        subjectCounters[subject] = counter

        // Per-company (extract from subject)
        if let company = Self.extractCompany(from: subject) {
            var companyCounter = companyCounters[company] ?? WindowedCounter()
            companyCounter.record(at: date)
            companyCounters[company] = companyCounter
        }
    }

    /// Record an agent event for utilization tracking.
    public func recordAgent(
        agentId: String,
        company: String,
        event: AgentEventKind,
        duration: Double? = nil,
        at date: Date = Date()
    ) {
        var util = agents[agentId] ?? AgentUtilization(agentId: agentId, company: company)
        util.lastSeen = date

        switch event {
        case .dispatched:
            util.dispatched += 1
        case .completed:
            util.completed += 1
            if let d = duration {
                util.totalDurationSeconds += d
            }
        case .failed:
            util.failed += 1
        }

        agents[agentId] = util
    }

    /// Agent event kinds for utilization tracking.
    public enum AgentEventKind: Sendable {
        case dispatched
        case completed
        case failed
    }

    // MARK: - Queries

    /// Get rates for all tracked subjects.
    public func allSubjectMetrics(now: Date = Date()) -> [SubjectMetrics] {
        subjectCounters.map { subject, counter in
            var rates: [String: Double] = [:]
            var counts: [String: Int] = [:]
            for window in MetricsWindow.allCases {
                rates[window.rawValue] = counter.rate(window: window, now: now)
                counts[window.rawValue] = counter.count(window: window, now: now)
            }
            return SubjectMetrics(subject: subject, rates: rates, counts: counts)
        }
        .sorted { $0.subject < $1.subject }
    }

    /// Get event count for a specific company in a specific window.
    public func companyCount(company: String, window: MetricsWindow, now: Date = Date()) -> Int {
        companyCounters[company]?.count(window: window, now: now) ?? 0
    }

    /// Get event counts for all companies in a specific window.
    public func allCompanyCounts(window: MetricsWindow, now: Date = Date()) -> [String: Int] {
        var result: [String: Int] = [:]
        for (company, counter) in companyCounters {
            result[company] = counter.count(window: window, now: now)
        }
        return result
    }

    /// Get global event rate for a window.
    public func globalRate(window: MetricsWindow, now: Date = Date()) -> Double {
        globalCounter.rate(window: window, now: now)
    }

    /// Get global event count for a window.
    public func globalCount(window: MetricsWindow, now: Date = Date()) -> Int {
        globalCounter.count(window: window, now: now)
    }

    /// Get all agent utilization records.
    public func allAgentUtilization() -> [AgentUtilization] {
        Array(agents.values).sorted { $0.agentId < $1.agentId }
    }

    /// Get agent utilization for a specific company.
    public func agentUtilization(company: String) -> [AgentUtilization] {
        agents.values
            .filter { $0.company == company }
            .sorted { $0.agentId < $1.agentId }
    }

    /// Total number of unique subjects tracked.
    public var trackedSubjectCount: Int { subjectCounters.count }

    /// Total number of unique companies tracked.
    public var trackedCompanyCount: Int { companyCounters.count }

    /// Total number of agents tracked.
    public var trackedAgentCount: Int { agents.count }

    // MARK: - Maintenance

    /// Prune all counters to remove entries older than 24h.
    public func prune(now: Date = Date()) {
        for key in subjectCounters.keys {
            subjectCounters[key]?.prune(now: now)
        }
        for key in companyCounters.keys {
            companyCounters[key]?.prune(now: now)
        }
        globalCounter.prune(now: now)
    }

    /// Reset all metrics.
    public func reset() {
        subjectCounters.removeAll()
        companyCounters.removeAll()
        agents.removeAll()
        globalCounter = WindowedCounter()
    }

    // MARK: - Subject Parsing

    /// Extract company slug from a NATS subject.
    /// `shikki.events.maya.agent` -> `maya`
    /// `shikki.events.shiki.lifecycle` -> `shiki`
    /// Returns nil for non-event subjects.
    nonisolated static func extractCompany(from subject: String) -> String? {
        let tokens = subject.split(separator: ".")
        // Expected format: shikki.events.{company}.{category}
        guard tokens.count >= 3,
              tokens[0] == "shikki",
              tokens[1] == "events" else {
            return nil
        }
        return String(tokens[2])
    }
}
