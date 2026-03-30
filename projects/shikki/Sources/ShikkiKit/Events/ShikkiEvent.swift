import Foundation

// MARK: - ShikkiEvent

/// A single observable event in the Shikki data stream.
/// Every action in the system produces one or more of these.
public struct ShikkiEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let type: EventType
    public let scope: EventScope
    public let payload: [String: EventValue]
    public let metadata: EventMetadata?

    public init(
        source: EventSource,
        type: EventType,
        scope: EventScope,
        payload: [String: EventValue] = [:],
        metadata: EventMetadata? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.type = type
        self.scope = scope
        self.payload = payload
        self.metadata = metadata
    }
}

// MARK: - EventSource

/// Who produced the event.
public enum EventSource: Codable, Sendable, Equatable {
    case agent(id: String, name: String?)
    case human(id: String?)
    case orchestrator
    case process(name: String)
    case system
}

// MARK: - EventType

/// What happened.
public enum EventType: Codable, Sendable, Hashable {
    // Lifecycle
    case sessionStart
    case sessionEnd

    // Ship
    case shipStarted
    case shipGateStarted
    case shipGatePassed
    case shipGateFailed
    case shipCompleted
    case shipAborted

    // TestFlight
    case testflightArchive
    case testflightExport
    case testflightUpload
    case testflightDistribute

    // Generic
    case custom(String)
}

// MARK: - EventScope

/// What context the event belongs to.
public enum EventScope: Codable, Sendable, Hashable {
    case global
    case session(id: String)
    case project(slug: String)
    case pr(number: Int)
    case file(path: String)
}

// MARK: - EventMetadata

/// Optional rich context for an event.
public struct EventMetadata: Codable, Sendable {
    public var branch: String?
    public var file: String?
    public var commitHash: String?
    public var duration: TimeInterval?
    public var tags: [String]?

    public init(
        branch: String? = nil,
        file: String? = nil,
        commitHash: String? = nil,
        duration: TimeInterval? = nil,
        tags: [String]? = nil
    ) {
        self.branch = branch
        self.file = file
        self.commitHash = commitHash
        self.duration = duration
        self.tags = tags
    }
}

// MARK: - EventValue

/// A type-safe, Codable value for event payloads.
public enum EventValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}
