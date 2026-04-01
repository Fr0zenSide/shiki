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

// MARK: - DurationParser Recovery Extensions

extension DurationParser {

    /// Default recovery window: 2 hours.
    public static let defaultRecoveryDuration: TimeInterval = 7200

    /// Maximum allowed recovery duration: 7 days.
    public static let maxRecoveryDuration: TimeInterval = 604_800

    /// Parse a duration string like "2h", "30m", "3600s", "7d".
    /// Clamps to 7d maximum. Returns a ParsedDuration with clamping info.
    public static func parseForRecovery(_ input: String) throws -> ParsedDuration {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            throw DurationParseError.invalidFormat(input)
        }

        let suffix = trimmed.last!
        let numberPart = String(trimmed.dropLast())

        guard let value = Double(numberPart), value > 0 else {
            throw DurationParseError.invalidFormat(input)
        }

        let seconds: TimeInterval
        switch suffix {
        case "s": seconds = value
        case "m": seconds = value * 60
        case "h": seconds = value * 3600
        case "d": seconds = value * 86400
        default:
            throw DurationParseError.invalidFormat(input)
        }

        if seconds > maxRecoveryDuration {
            return ParsedDuration(seconds: maxRecoveryDuration, clamped: true)
        }
        return ParsedDuration(seconds: seconds, clamped: false)
    }
}
