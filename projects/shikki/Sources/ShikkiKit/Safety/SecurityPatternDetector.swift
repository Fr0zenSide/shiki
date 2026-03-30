import Foundation
import Logging

// MARK: - SecurityPatternDetector

/// Detects security-relevant anomalies from the event stream.
/// Sits alongside `stuck_agent` and `repeat_failure` in the EventRouter pattern pipeline.
///
/// Patterns detected:
/// - `bulkExtraction`: 100+ queries in 5 min (normal: ~12/hour)
/// - `crossProjectScan`: user accessing 5+ projects they don't own
/// - `offHoursAccess`: queries at unusual hours
/// - `exportPattern`: sequential scan of all memories in a project
/// - `burnoutSignal`: 16h+ continuous usage or midnight budget burn
/// - `knowledgeHoarding`: single user responsible for 80%+ of project queries
public actor SecurityPatternDetector {
    private var window: [SecurityEventRecord] = []
    private var incidents: [SecurityIncident] = []
    private let config: SecurityDetectorConfig
    private let logger: Logger

    /// Callback invoked when a new incident is created.
    public var onIncidentDetected: (@Sendable (SecurityIncident) async -> Void)?

    /// Set the incident-detected callback (actor-isolated setter for external callers).
    public func setOnIncidentDetected(_ handler: (@Sendable (SecurityIncident) async -> Void)?) {
        onIncidentDetected = handler
    }

    public init(
        config: SecurityDetectorConfig = .default,
        logger: Logger = Logger(label: "shikki.security-detector")
    ) {
        self.config = config
        self.logger = logger
    }

    // MARK: - Recording

    /// Record a tool call event for pattern analysis.
    public func record(_ record: SecurityEventRecord) {
        window.append(record)

        // Trim window to max size
        if window.count > config.maxWindowSize {
            let excess = window.count - config.maxWindowSize
            window.removeFirst(excess)
        }
    }

    // MARK: - Detection

    /// Run all pattern detectors and return any new incidents.
    public func detect() async -> [SecurityIncident] {
        var newIncidents: [SecurityIncident] = []

        newIncidents.append(contentsOf: detectBulkExtraction())
        newIncidents.append(contentsOf: detectCrossProjectScan())
        newIncidents.append(contentsOf: detectOffHoursAccess())
        newIncidents.append(contentsOf: detectExportPattern())
        newIncidents.append(contentsOf: detectBurnoutSignal())
        newIncidents.append(contentsOf: detectKnowledgeHoarding())

        for incident in newIncidents {
            incidents.append(incident)
            await onIncidentDetected?(incident)
        }

        return newIncidents
    }

    /// All recorded incidents.
    public func allIncidents() -> [SecurityIncident] {
        incidents
    }

    /// Current window size.
    public func windowSize() -> Int {
        window.count
    }

    /// Clear window and incidents (for testing).
    public func reset() {
        window.removeAll()
        incidents.removeAll()
    }

    // MARK: - Pattern: Bulk Extraction

    /// 100+ queries in 5 min from a single user.
    private func detectBulkExtraction() -> [SecurityIncident] {
        let fiveMinAgo = Date().addingTimeInterval(-config.bulkExtractionWindowSeconds)
        var countByUser: [String: [SecurityEventRecord]] = [:]

        for record in window where record.timestamp >= fiveMinAgo {
            countByUser[record.userId, default: []].append(record)
        }

        var results: [SecurityIncident] = []
        for (userId, records) in countByUser {
            if records.count >= config.bulkExtractionThreshold {
                // Avoid duplicate incidents for same user in same window
                let alreadyReported = incidents.contains { incident in
                    incident.anomaly == .bulkExtraction
                        && incident.userId == userId
                        && incident.timestamp >= fiveMinAgo
                }
                guard !alreadyReported else { continue }

                let action = SecurityPolicyMap.action(for: .bulkExtraction)
                results.append(SecurityIncident(
                    anomaly: .bulkExtraction,
                    action: action,
                    userId: userId,
                    description: "\(records.count) queries in 5 minutes (threshold: \(config.bulkExtractionThreshold))",
                    relatedEventIds: records.map(\.eventId)
                ))
            }
        }
        return results
    }

    // MARK: - Pattern: Cross-Project Scan

    /// User accessing 5+ distinct projects within the window.
    private func detectCrossProjectScan() -> [SecurityIncident] {
        var projectsByUser: [String: Set<String>] = [:]
        var eventIdsByUser: [String: [UUID]] = [:]

        for record in window {
            if let project = record.projectSlug {
                projectsByUser[record.userId, default: []].insert(project)
                eventIdsByUser[record.userId, default: []].append(record.eventId)
            }
        }

        var results: [SecurityIncident] = []
        for (userId, projects) in projectsByUser {
            if projects.count >= config.crossProjectThreshold {
                let alreadyReported = incidents.contains { $0.anomaly == .crossProjectScan && $0.userId == userId }
                guard !alreadyReported else { continue }

                let action = SecurityPolicyMap.action(for: .crossProjectScan)
                results.append(SecurityIncident(
                    anomaly: .crossProjectScan,
                    action: action,
                    userId: userId,
                    description: "Accessed \(projects.count) projects: \(projects.sorted().joined(separator: ", "))",
                    relatedEventIds: eventIdsByUser[userId] ?? []
                ))
            }
        }
        return results
    }

    // MARK: - Pattern: Off-Hours Access

    /// Queries outside the user's normal working hours (configurable).
    private func detectOffHoursAccess() -> [SecurityIncident] {
        let calendar = Calendar.current
        var results: [SecurityIncident] = []
        var reportedUsers: Set<String> = []

        for record in window {
            let hour = calendar.component(.hour, from: record.timestamp)
            let isOffHours = hour < config.workingHoursStart || hour >= config.workingHoursEnd

            if isOffHours && !reportedUsers.contains(record.userId) {
                let alreadyReported = incidents.contains { incident in
                    incident.anomaly == .offHoursAccess
                        && incident.userId == record.userId
                        && calendar.isDate(incident.timestamp, inSameDayAs: record.timestamp)
                }
                guard !alreadyReported else {
                    reportedUsers.insert(record.userId)
                    continue
                }

                let action = SecurityPolicyMap.action(for: .offHoursAccess)
                results.append(SecurityIncident(
                    anomaly: .offHoursAccess,
                    action: action,
                    userId: record.userId,
                    description: "Access at \(hour):00 (working hours: \(config.workingHoursStart)-\(config.workingHoursEnd))",
                    relatedEventIds: [record.eventId]
                ))
                reportedUsers.insert(record.userId)
            }
        }
        return results
    }

    // MARK: - Pattern: Export Pattern

    /// Sequential scan — many distinct memory reads from the same project in a short window.
    private func detectExportPattern() -> [SecurityIncident] {
        let windowStart = Date().addingTimeInterval(-config.exportPatternWindowSeconds)
        var readsByUserProject: [String: [SecurityEventRecord]] = [:]

        for record in window where record.timestamp >= windowStart && record.isMemoryRead {
            let key = "\(record.userId):\(record.projectSlug ?? "global")"
            readsByUserProject[key, default: []].append(record)
        }

        var results: [SecurityIncident] = []
        for (key, records) in readsByUserProject {
            if records.count >= config.exportPatternThreshold {
                let userId = String(key.split(separator: ":").first ?? "unknown")
                let alreadyReported = incidents.contains { $0.anomaly == .exportPattern && $0.userId == userId && $0.timestamp >= windowStart }
                guard !alreadyReported else { continue }

                let action = SecurityPolicyMap.action(for: .exportPattern)
                results.append(SecurityIncident(
                    anomaly: .exportPattern,
                    action: action,
                    userId: userId,
                    description: "\(records.count) memory reads in \(Int(config.exportPatternWindowSeconds))s window (threshold: \(config.exportPatternThreshold))",
                    relatedEventIds: records.map(\.eventId)
                ))
            }
        }
        return results
    }

    // MARK: - Pattern: Burnout Signal

    /// 16h+ continuous usage — first and last event in window span > threshold.
    private func detectBurnoutSignal() -> [SecurityIncident] {
        var eventsByUser: [String: [Date]] = [:]

        for record in window {
            eventsByUser[record.userId, default: []].append(record.timestamp)
        }

        var results: [SecurityIncident] = []
        for (userId, timestamps) in eventsByUser {
            guard let earliest = timestamps.min(), let latest = timestamps.max() else { continue }
            let span = latest.timeIntervalSince(earliest)

            if span >= config.burnoutThresholdSeconds {
                let alreadyReported = incidents.contains { $0.anomaly == .burnoutSignal && $0.userId == userId }
                guard !alreadyReported else { continue }

                let hours = Int(span / 3600)
                let action = SecurityPolicyMap.action(for: .burnoutSignal)
                results.append(SecurityIncident(
                    anomaly: .burnoutSignal,
                    action: action,
                    userId: userId,
                    description: "\(hours)h continuous activity detected (threshold: \(Int(config.burnoutThresholdSeconds / 3600))h)",
                    relatedEventIds: []
                ))
            }
        }
        return results
    }

    // MARK: - Pattern: Knowledge Hoarding

    /// One user responsible for 80%+ of queries in a project.
    private func detectKnowledgeHoarding() -> [SecurityIncident] {
        var queriesByProject: [String: [String: Int]] = [:] // project -> user -> count

        for record in window {
            guard let project = record.projectSlug else { continue }
            queriesByProject[project, default: [:]][record.userId, default: 0] += 1
        }

        var results: [SecurityIncident] = []
        for (project, userCounts) in queriesByProject {
            let total = userCounts.values.reduce(0, +)
            guard total >= config.knowledgeHoardingMinQueries else { continue }

            for (userId, count) in userCounts {
                let ratio = Double(count) / Double(total)
                if ratio >= config.knowledgeHoardingRatio {
                    let alreadyReported = incidents.contains {
                        $0.anomaly == .knowledgeHoarding && $0.userId == userId
                    }
                    guard !alreadyReported else { continue }

                    let action = SecurityPolicyMap.action(for: .knowledgeHoarding)
                    results.append(SecurityIncident(
                        anomaly: .knowledgeHoarding,
                        action: action,
                        userId: userId,
                        description: "User handles \(Int(ratio * 100))% of queries for project '\(project)' (\(count)/\(total))",
                        relatedEventIds: []
                    ))
                }
            }
        }
        return results
    }
}

// MARK: - SecurityEventRecord

/// A lightweight record extracted from a ShikkiEvent for security analysis.
public struct SecurityEventRecord: Sendable {
    public let eventId: UUID
    public let userId: String
    public let toolName: String
    public let projectSlug: String?
    public let timestamp: Date
    public let isMemoryRead: Bool

    public init(
        eventId: UUID = UUID(),
        userId: String,
        toolName: String,
        projectSlug: String? = nil,
        timestamp: Date = Date(),
        isMemoryRead: Bool = false
    ) {
        self.eventId = eventId
        self.userId = userId
        self.toolName = toolName
        self.projectSlug = projectSlug
        self.timestamp = timestamp
        self.isMemoryRead = isMemoryRead
    }
}

// MARK: - SecurityDetectorConfig

/// Tunable thresholds for the security pattern detector.
public struct SecurityDetectorConfig: Sendable {
    public let maxWindowSize: Int
    public let bulkExtractionThreshold: Int
    public let bulkExtractionWindowSeconds: TimeInterval
    public let crossProjectThreshold: Int
    public let workingHoursStart: Int
    public let workingHoursEnd: Int
    public let exportPatternThreshold: Int
    public let exportPatternWindowSeconds: TimeInterval
    public let burnoutThresholdSeconds: TimeInterval
    public let knowledgeHoardingRatio: Double
    public let knowledgeHoardingMinQueries: Int

    public static let `default` = SecurityDetectorConfig(
        maxWindowSize: 1000,
        bulkExtractionThreshold: 100,
        bulkExtractionWindowSeconds: 300,
        crossProjectThreshold: 5,
        workingHoursStart: 9,
        workingHoursEnd: 18,
        exportPatternThreshold: 50,
        exportPatternWindowSeconds: 600,
        burnoutThresholdSeconds: 57600, // 16h
        knowledgeHoardingRatio: 0.8,
        knowledgeHoardingMinQueries: 10
    )

    /// Permissive config for testing with low thresholds.
    public static let testing = SecurityDetectorConfig(
        maxWindowSize: 100,
        bulkExtractionThreshold: 5,
        bulkExtractionWindowSeconds: 300,
        crossProjectThreshold: 3,
        workingHoursStart: 9,
        workingHoursEnd: 18,
        exportPatternThreshold: 5,
        exportPatternWindowSeconds: 600,
        burnoutThresholdSeconds: 3600, // 1h for tests
        knowledgeHoardingRatio: 0.8,
        knowledgeHoardingMinQueries: 5
    )

    public init(
        maxWindowSize: Int = 1000,
        bulkExtractionThreshold: Int = 100,
        bulkExtractionWindowSeconds: TimeInterval = 300,
        crossProjectThreshold: Int = 5,
        workingHoursStart: Int = 9,
        workingHoursEnd: Int = 18,
        exportPatternThreshold: Int = 50,
        exportPatternWindowSeconds: TimeInterval = 600,
        burnoutThresholdSeconds: TimeInterval = 57600,
        knowledgeHoardingRatio: Double = 0.8,
        knowledgeHoardingMinQueries: Int = 10
    ) {
        self.maxWindowSize = maxWindowSize
        self.bulkExtractionThreshold = bulkExtractionThreshold
        self.bulkExtractionWindowSeconds = bulkExtractionWindowSeconds
        self.crossProjectThreshold = crossProjectThreshold
        self.workingHoursStart = workingHoursStart
        self.workingHoursEnd = workingHoursEnd
        self.exportPatternThreshold = exportPatternThreshold
        self.exportPatternWindowSeconds = exportPatternWindowSeconds
        self.burnoutThresholdSeconds = burnoutThresholdSeconds
        self.knowledgeHoardingRatio = knowledgeHoardingRatio
        self.knowledgeHoardingMinQueries = knowledgeHoardingMinQueries
    }
}
