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

// MARK: - DurationParser Recovery Extension

extension DurationParser {
    /// Default recovery window: 1 hour.
    public static let defaultRecoveryDuration: TimeInterval = 3600
    /// Maximum: 7 days.
    private static let maxRecoveryDuration: TimeInterval = 7 * 24 * 3600

    /// Parse a duration string for recovery. Clamps to 7 days.
    public static func parseForRecovery(_ input: String) throws -> ParsedDuration {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { throw DurationParseError.invalidFormat(input) }

        guard let seconds = parse(trimmed) else {
            // Try with 'd' suffix (not in base parse)
            if trimmed.hasSuffix("d"), let value = Double(trimmed.dropLast()) {
                let secs = value * 86400
                return ParsedDuration(seconds: min(secs, maxRecoveryDuration), clamped: secs > maxRecoveryDuration)
            }
            throw DurationParseError.invalidFormat(input)
        }
        return ParsedDuration(seconds: min(seconds, maxRecoveryDuration), clamped: seconds > maxRecoveryDuration)
    }
}
