import Foundation

// MARK: - ParsedDuration

/// Result of duration parsing with clamping information.
/// BR-01: Clamped flag indicates value was reduced to max 7d.
public struct ParsedDuration: Sendable, Equatable {
    public let seconds: TimeInterval
    public let clamped: Bool

    public init(seconds: TimeInterval, clamped: Bool) {
        self.seconds = seconds
        self.clamped = clamped
    }
}

// MARK: - DurationParseError

/// Error thrown when a duration string cannot be parsed.
/// BR-06: Clear error message with format examples.
public enum DurationParseError: Error, CustomStringConvertible, Equatable {
    case invalidFormat(String)

    public var description: String {
        switch self {
        case .invalidFormat(let input):
            "Invalid duration '\(input)'. Expected format: 2h, 30m, 3600s, 7d"
        }
    }
}
