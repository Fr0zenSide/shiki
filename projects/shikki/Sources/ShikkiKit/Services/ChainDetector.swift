import Foundation

// CommandLogEntry defined in Kernel/Core/CommandLogger.swift

// MARK: - DetectedChain

/// A repeated command sequence detected from usage history.
public struct DetectedChain: Codable, Sendable, Equatable {
    /// The command names in order, e.g. `["shi spec", "shi review", "shi ship"]`.
    public let commands: [String]
    /// How many times this exact chain was executed.
    public let count: Int
    /// Timestamp of the last entry in the most recent occurrence.
    public let lastSeen: Date

    public init(commands: [String], count: Int, lastSeen: Date) {
        self.commands = commands
        self.count = count
        self.lastSeen = lastSeen
    }
}

// MARK: - ChainDetector

/// Detects repeated command sequences from command history.
///
/// Algorithm:
/// 1. Parse entries chronologically
/// 2. Group into sessions: consecutive commands where the gap < `maxGapSeconds`
/// 3. Extract all contiguous subsequences of length >= `minChainLength` from each session
/// 4. Count occurrences of each unique subsequence (by command names)
/// 5. Return chains with count >= `minOccurrences`, sorted by count descending
public enum ChainDetector {

    // MARK: - Public API

    /// Analyze command log entries and detect repeated chains.
    ///
    /// This is a pure function with no side effects.
    ///
    /// - Parameters:
    ///   - entries: Command log entries to analyze (need not be sorted).
    ///   - minChainLength: Minimum commands in a chain (default: 2).
    ///   - maxGapSeconds: Maximum gap between commands to belong to the same session (default: 5).
    ///   - minOccurrences: Minimum times a chain must repeat to be included (default: 3).
    /// - Returns: Detected chains sorted by count descending, then alphabetically by commands.
    public static func detect(
        entries: [CommandLogEntry],
        minChainLength: Int = 2,
        maxGapSeconds: TimeInterval = 5,
        minOccurrences: Int = 3
    ) -> [DetectedChain] {
        let parsed = parseAndSort(entries)
        guard parsed.count >= minChainLength else { return [] }

        let sessions = groupIntoSessions(parsed, maxGap: maxGapSeconds)
        var chainOccurrences: [String: ChainAccumulator] = [:]

        for session in sessions {
            let subsequences = extractSubsequences(
                session,
                minLength: minChainLength
            )
            // Deduplicate within the same session: each unique subsequence
            // counts at most once per session.
            var seenInSession: Set<String> = []
            for subseq in subsequences {
                let key = subseq.commands.joined(separator: " -> ")
                guard seenInSession.insert(key).inserted else { continue }
                if var acc = chainOccurrences[key] {
                    acc.count += 1
                    if subseq.lastDate > acc.lastSeen {
                        acc.lastSeen = subseq.lastDate
                    }
                    chainOccurrences[key] = acc
                } else {
                    chainOccurrences[key] = ChainAccumulator(
                        commands: subseq.commands,
                        count: 1,
                        lastSeen: subseq.lastDate
                    )
                }
            }
        }

        return chainOccurrences.values
            .filter { $0.count >= minOccurrences }
            .map { DetectedChain(commands: $0.commands, count: $0.count, lastSeen: $0.lastSeen) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.commands.joined() < rhs.commands.joined()
            }
    }

    /// Read command history from a JSONL file and detect chains.
    ///
    /// - Parameters:
    ///   - path: Path to the `.jsonl` file.
    ///   - minChainLength: Minimum commands in a chain (default: 2).
    ///   - maxGapSeconds: Maximum gap between commands in same session (default: 5).
    ///   - minOccurrences: Minimum repetitions to be detected (default: 3).
    /// - Returns: Detected chains sorted by count descending.
    public static func detectFromFile(
        at path: String,
        minChainLength: Int = 2,
        maxGapSeconds: TimeInterval = 5,
        minOccurrences: Int = 3
    ) throws -> [DetectedChain] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)

        let decoder = JSONDecoder()
        var entries: [CommandLogEntry] = []
        for line in lines {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let entry = try? decoder.decode(CommandLogEntry.self, from: lineData) {
                entries.append(entry)
            }
        }

        return detect(
            entries: entries,
            minChainLength: minChainLength,
            maxGapSeconds: maxGapSeconds,
            minOccurrences: minOccurrences
        )
    }

    // MARK: - Private Types

    private struct ParsedEntry: Sendable {
        let cmd: String
        let date: Date
    }

    private struct Subsequence {
        let commands: [String]
        let lastDate: Date
    }

    private struct ChainAccumulator {
        var commands: [String]
        var count: Int
        var lastSeen: Date
    }

    // MARK: - Private Helpers

    /// Parse ISO8601 timestamps and sort entries chronologically.
    private static func parseAndSort(_ entries: [CommandLogEntry]) -> [ParsedEntry] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return entries
            .compactMap { entry -> ParsedEntry? in
                guard let date = formatter.date(from: entry.ts) else { return nil }
                return ParsedEntry(cmd: entry.cmd, date: date)
            }
            .sorted { $0.date < $1.date }
    }

    /// Group parsed entries into sessions based on time gap.
    private static func groupIntoSessions(
        _ entries: [ParsedEntry],
        maxGap: TimeInterval
    ) -> [[ParsedEntry]] {
        guard let first = entries.first else { return [] }

        var sessions: [[ParsedEntry]] = []
        var current: [ParsedEntry] = [first]

        for entry in entries.dropFirst() {
            let gap = entry.date.timeIntervalSince(current.last!.date)
            if gap <= maxGap {
                current.append(entry)
            } else {
                sessions.append(current)
                current = [entry]
            }
        }
        sessions.append(current)

        return sessions
    }

    /// Extract all contiguous subsequences of length >= minLength from a session.
    private static func extractSubsequences(
        _ session: [ParsedEntry],
        minLength: Int
    ) -> [Subsequence] {
        var result: [Subsequence] = []
        let count = session.count
        guard count >= minLength else { return [] }

        for length in minLength...count {
            for start in 0...(count - length) {
                let slice = session[start..<(start + length)]
                let commands = slice.map(\.cmd)
                let lastDate = slice.last!.date
                result.append(Subsequence(commands: commands, lastDate: lastDate))
            }
        }

        return result
    }
}
