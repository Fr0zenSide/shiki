import Foundation

/// Types of events a sub-agent emits during execution.
/// Maps 1:1 to ShikkiDB event types in the orchestrator DNA.
public enum DispatchEventType: String, Codable, Sendable, CaseIterable {
    case taskStarted
    case waveStarted
    case testPassed
    case testFailed
    case blockerHit
    case prCreated
    case taskCompleted
}

/// An event emitted by a sub-agent during dispatch execution.
/// The orchestrator monitors these to track progress and detect blockers.
public struct DispatchEvent: Codable, Sendable {
    public let agentId: String
    public let type: DispatchEventType
    public let timestamp: Date
    public let data: [String: String]

    public init(
        agentId: String,
        type: DispatchEventType,
        timestamp: Date = Date(),
        data: [String: String] = [:]
    ) {
        self.agentId = agentId
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }
}
