import Foundation

// MARK: - ScheduledTask

/// A scheduled task managed by the TaskSchedulerService.
/// Stores all fields from BR-16 including retry policy, timing, and claim state.
public struct ScheduledTask: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var cronExpression: String
    public var command: String
    public var companyId: String?
    public var enabled: Bool
    public var retryPolicy: RetryPolicy
    public var estimatedDurationMs: Int
    public var avgDurationMs: Int?
    public var lastRunAt: Date?
    public var nextRunAt: Date?
    public var claimedBy: String?
    public var claimedAt: Date?
    public var isBuiltin: Bool
    public var speculative: Bool
    public var retryCount: Int
    public var maxRetries: Int

    public init(
        id: UUID = UUID(),
        name: String,
        cronExpression: String,
        command: String,
        companyId: String? = nil,
        enabled: Bool = true,
        retryPolicy: RetryPolicy = .linear,
        estimatedDurationMs: Int = 60_000,
        avgDurationMs: Int? = nil,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        claimedBy: String? = nil,
        claimedAt: Date? = nil,
        isBuiltin: Bool = false,
        speculative: Bool = false,
        retryCount: Int = 0,
        maxRetries: Int = 3
    ) {
        self.id = id
        self.name = name
        self.cronExpression = cronExpression
        self.command = command
        self.companyId = companyId
        self.enabled = enabled
        self.retryPolicy = retryPolicy
        self.estimatedDurationMs = estimatedDurationMs
        self.avgDurationMs = avgDurationMs
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.claimedBy = claimedBy
        self.claimedAt = claimedAt
        self.isBuiltin = isBuiltin
        self.speculative = speculative
        self.retryCount = retryCount
        self.maxRetries = maxRetries
    }

    /// Compute the next run time from the cron expression.
    /// Uses the provided `after` date (defaults to now).
    public func computeNextRun(after date: Date = .now) -> Date? {
        let parser = CronParser()
        guard let expr = try? parser.parse(cronExpression) else { return nil }
        return expr.nextOccurrence(after: date)
    }

    /// Update avg duration using exponential moving average (BR-21).
    /// avg = 0.8 * old_avg + 0.2 * actual
    public mutating func updateAvgDuration(actual: Int) {
        if let existing = avgDurationMs {
            avgDurationMs = Int(0.8 * Double(existing) + 0.2 * Double(actual))
        } else {
            avgDurationMs = actual
        }
    }
}

// MARK: - RetryPolicy

/// Retry backoff strategy for scheduled tasks.
public enum RetryPolicy: String, Codable, Sendable, Equatable {
    case linear
    case exponential
    case none
}

// MARK: - Built-in Tasks (BR-36)

extension ScheduledTask {
    /// Corroboration sweep — daily at 03:00, refreshes stale memories (freshness < 0.3).
    public static let corroborationSweep = ScheduledTask(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "corroboration-sweep",
        cronExpression: "0 3 * * *",
        command: "corroboration-sweep",
        enabled: true,
        estimatedDurationMs: 300_000,
        isBuiltin: true,
        maxRetries: 3
    )

    /// Radar scan — daily at 05:00, GitHub trending to ShikiDB.
    public static let radarScan = ScheduledTask(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "radar-scan",
        cronExpression: "0 5 * * *",
        command: "radar-scan",
        enabled: true,
        estimatedDurationMs: 180_000,
        isBuiltin: true,
        maxRetries: 3
    )

    /// All built-in tasks that should be seeded on first run.
    public static let builtinTasks: [ScheduledTask] = [
        .corroborationSweep,
        .radarScan,
    ]
}
