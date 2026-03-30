import Foundation

// MARK: - CalibrationRecord

/// A single calibration data point: predicted risk vs actual outcome.
/// Used to train/validate risk scoring weights over time.
public struct CalibrationRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let predictedScore: Double
    public let predictedTier: RiskTier
    public let actualOutcome: OutcomeType
    public let fileExtension: String
    public let linesChanged: Int
    public let taskType: String?
    public let language: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        predictedScore: Double,
        predictedTier: RiskTier,
        actualOutcome: OutcomeType,
        fileExtension: String,
        linesChanged: Int,
        taskType: String? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.predictedScore = predictedScore
        self.predictedTier = predictedTier
        self.actualOutcome = actualOutcome
        self.fileExtension = fileExtension
        self.linesChanged = linesChanged
        self.taskType = taskType
        self.language = language
    }
}

// MARK: - OutcomeType

/// What actually happened after the change was merged.
public enum OutcomeType: String, Codable, Sendable, Equatable {
    case clean          // No issues found post-merge
    case minorBug       // Non-blocking bug discovered
    case majorBug       // Blocking bug requiring hotfix
    case reverted       // Change was reverted
    case testFailure    // CI tests broke on merge target
}

// MARK: - CalibrationStats

/// Aggregate statistics from calibration data.
public struct CalibrationStats: Codable, Sendable, Equatable {
    public let totalRecords: Int
    public let accuracy: Double         // % predictions in correct tier
    public let meanAbsoluteError: Double // average |predicted - actual_score|
    public let tierDistribution: [String: Int]
    public let outcomeDistribution: [String: Int]

    public init(
        totalRecords: Int,
        accuracy: Double,
        meanAbsoluteError: Double,
        tierDistribution: [String: Int],
        outcomeDistribution: [String: Int]
    ) {
        self.totalRecords = totalRecords
        self.accuracy = accuracy
        self.meanAbsoluteError = meanAbsoluteError
        self.tierDistribution = tierDistribution
        self.outcomeDistribution = outcomeDistribution
    }
}

// MARK: - CalibrationStore

/// Persistent JSONL store for calibration records.
/// Each line is a JSON-encoded CalibrationRecord.
/// Append-only for performance; rotate/compact periodically.
public actor CalibrationStore {
    private let filePath: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(filePath: String? = nil) {
        self.filePath = filePath ?? Self.defaultPath()
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/share/shikki/calibration.jsonl"
    }

    // MARK: - Write

    /// Append a single calibration record.
    public func append(_ record: CalibrationRecord) throws {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try encoder.encode(record)
        guard var line = String(data: data, encoding: .utf8) else {
            return
        }
        line += "\n"

        if FileManager.default.fileExists(atPath: filePath) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) {
                handle.write(lineData)
            }
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Append multiple records in a batch.
    public func appendBatch(_ records: [CalibrationRecord]) throws {
        for record in records {
            try append(record)
        }
    }

    // MARK: - Read

    /// Load all calibration records.
    public func loadAll() throws -> [CalibrationRecord] {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return []
        }

        let url = URL(fileURLWithPath: filePath)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        return lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(CalibrationRecord.self, from: data)
        }
    }

    /// Load records within a date range.
    public func load(from: Date, to: Date) throws -> [CalibrationRecord] {
        try loadAll().filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    /// Count total records without loading all into memory.
    public func count() throws -> Int {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return 0
        }
        let url = URL(fileURLWithPath: filePath)
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    // MARK: - Analysis

    /// Compute calibration statistics from stored records.
    public func computeStats() throws -> CalibrationStats {
        let records = try loadAll()
        guard !records.isEmpty else {
            return CalibrationStats(
                totalRecords: 0,
                accuracy: 0,
                meanAbsoluteError: 0,
                tierDistribution: [:],
                outcomeDistribution: [:]
            )
        }

        // Tier distribution
        var tierDist: [String: Int] = [:]
        for record in records {
            tierDist[record.predictedTier.rawValue, default: 0] += 1
        }

        // Outcome distribution
        var outcomeDist: [String: Int] = [:]
        for record in records {
            outcomeDist[record.actualOutcome.rawValue, default: 0] += 1
        }

        // Accuracy: predicted tier matches expected tier from outcome
        let correctPredictions = records.filter { record in
            let expectedTier = Self.expectedTier(for: record.actualOutcome)
            return record.predictedTier == expectedTier
        }
        let accuracy = Double(correctPredictions.count) / Double(records.count)

        // MAE: |predicted_score - outcome_score|
        let totalError = records.reduce(0.0) { acc, record in
            let actualScore = Self.outcomeScore(record.actualOutcome)
            return acc + abs(record.predictedScore - actualScore)
        }
        let mae = totalError / Double(records.count)

        return CalibrationStats(
            totalRecords: records.count,
            accuracy: accuracy,
            meanAbsoluteError: mae,
            tierDistribution: tierDist,
            outcomeDistribution: outcomeDist
        )
    }

    // MARK: - Rotation

    /// Rotate the store: keep only records from the last N days.
    public func rotate(keepDays: Int = 90) throws -> Int {
        let records = try loadAll()
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
        let kept = records.filter { $0.timestamp >= cutoff }
        let removed = records.count - kept.count

        // Rewrite file with kept records
        let url = URL(fileURLWithPath: filePath)
        let lines = try kept.map { record -> String in
            let data = try encoder.encode(record)
            return String(data: data, encoding: .utf8) ?? ""
        }
        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)

        return removed
    }

    // MARK: - Outcome Mapping

    /// Map an outcome to the expected risk tier.
    static func expectedTier(for outcome: OutcomeType) -> RiskTier {
        switch outcome {
        case .clean: return .low
        case .minorBug: return .medium
        case .majorBug: return .high
        case .reverted: return .critical
        case .testFailure: return .high
        }
    }

    /// Map an outcome to a numeric score (0.0–1.0) for error calculation.
    static func outcomeScore(_ outcome: OutcomeType) -> Double {
        switch outcome {
        case .clean: return 0.1
        case .minorBug: return 0.4
        case .majorBug: return 0.7
        case .reverted: return 0.95
        case .testFailure: return 0.75
        }
    }
}
