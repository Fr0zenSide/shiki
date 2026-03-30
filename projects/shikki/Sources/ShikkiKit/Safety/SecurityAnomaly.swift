import Foundation

// MARK: - SecurityAnomaly

/// A security-relevant anomaly detected by pattern analysis.
public enum SecurityAnomaly: Codable, Sendable, Hashable {
    /// 100+ queries in 5 min (normal: ~12/hour).
    case bulkExtraction
    /// User accessing 5+ projects they don't own.
    case crossProjectScan
    /// Queries at unusual hours for a user's normal pattern.
    case offHoursAccess
    /// Sequential scan of all memories in a project.
    case exportPattern
    /// Budget burn at midnight, 16h+ continuous usage.
    case burnoutSignal
    /// One user becomes single point of failure (knowledge hoarding).
    case knowledgeHoarding
}

// MARK: - SecurityAction

/// The response taken when an anomaly is detected.
public enum SecurityAction: Codable, Sendable, Hashable {
    /// Block further access and alert CODIR.
    case blockAndAlert
    /// Alert the manager and log the incident.
    case alertAndLog
    /// Throttle request rate and alert CODIR.
    case throttleAndAlert
    /// Log only (might be legitimate).
    case logOnly
}

// MARK: - SecurityIncident

/// A recorded security incident with full audit context (5W1H).
public struct SecurityIncident: Codable, Sendable, Identifiable {
    public let id: UUID
    public let anomaly: SecurityAnomaly
    public let action: SecurityAction
    public let userId: String
    public let workspaceId: String?
    public let description: String
    public let relatedEventIds: [UUID]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        anomaly: SecurityAnomaly,
        action: SecurityAction,
        userId: String,
        workspaceId: String? = nil,
        description: String,
        relatedEventIds: [UUID] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.anomaly = anomaly
        self.action = action
        self.userId = userId
        self.workspaceId = workspaceId
        self.description = description
        self.relatedEventIds = relatedEventIds
        self.timestamp = timestamp
    }
}

// MARK: - SecurityPolicyMap

/// Maps anomaly types to their default response actions.
/// "Shiki doesn't make security decisions. Shiki makes security visible."
public enum SecurityPolicyMap {

    public static func action(for anomaly: SecurityAnomaly) -> SecurityAction {
        switch anomaly {
        case .bulkExtraction:
            return .blockAndAlert
        case .crossProjectScan:
            return .alertAndLog
        case .offHoursAccess:
            return .logOnly
        case .exportPattern:
            return .throttleAndAlert
        case .burnoutSignal:
            return .logOnly
        case .knowledgeHoarding:
            return .alertAndLog
        }
    }
}
