import Foundation

// MARK: - CronParser

/// Pure cron expression parser — no side effects, no I/O, just date math.
/// Supports 5-field POSIX syntax: minute hour day-of-month month day-of-week.
/// Enforces minimum interval of 1 hour (BR-17).
public struct CronParser: Sendable {

    public init() {}

    /// Parse a 5-field POSIX cron expression string into a CronExpression.
    /// Throws `CronParseError` if the expression is invalid or too frequent.
    public func parse(_ expression: String) throws -> CronExpression {
        let fields = expression.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard fields.count == 5 else {
            throw CronParseError.invalidFieldCount(fields.count)
        }

        let minute = try parseField(String(fields[0]), range: 0...59, name: "minute")
        let hour = try parseField(String(fields[1]), range: 0...23, name: "hour")
        let dayOfMonth = try parseField(String(fields[2]), range: 1...31, name: "day-of-month")
        let month = try parseField(String(fields[3]), range: 1...12, name: "month")
        let dayOfWeek = try parseField(String(fields[4]), range: 0...6, name: "day-of-week")

        let expr = CronExpression(
            raw: expression,
            minute: minute,
            hour: hour,
            dayOfMonth: dayOfMonth,
            month: month,
            dayOfWeek: dayOfWeek
        )

        // BR-17: Minimum interval enforcement — reject anything more frequent than hourly
        try enforceMinimumInterval(expr)

        return expr
    }

    /// Validate whether a cron expression string is valid.
    public func isValid(_ expression: String) -> Bool {
        (try? parse(expression)) != nil
    }

    // MARK: - Field Parsing

    func parseField(_ field: String, range: ClosedRange<Int>, name: String) throws -> CronField {
        // Wildcard
        if field == "*" {
            return .wildcard
        }

        // Step on wildcard: */N
        if field.hasPrefix("*/") {
            let stepStr = String(field.dropFirst(2))
            guard let step = Int(stepStr), step > 0, step <= range.upperBound else {
                throw CronParseError.invalidStep(name, field)
            }
            return .step(step)
        }

        // List: 1,3,5
        if field.contains(",") {
            let parts = field.split(separator: ",")
            var values: [Int] = []
            for part in parts {
                guard let v = Int(part), range.contains(v) else {
                    throw CronParseError.valueOutOfRange(name, String(part), range)
                }
                values.append(v)
            }
            return .list(values.sorted())
        }

        // Range: 1-5
        if field.contains("-") {
            let parts = field.split(separator: "-")
            guard parts.count == 2,
                  let low = Int(parts[0]), let high = Int(parts[1]),
                  range.contains(low), range.contains(high), low <= high else {
                throw CronParseError.invalidRange(name, field)
            }
            return .range(low, high)
        }

        // Specific value
        guard let value = Int(field), range.contains(value) else {
            throw CronParseError.valueOutOfRange(name, field, range)
        }
        return .specific(value)
    }

    // MARK: - Minimum Interval Enforcement (BR-17)

    func enforceMinimumInterval(_ expr: CronExpression) throws {
        // If hour is wildcard or step < 1, the expression fires more than once per hour
        let minuteFiresMultiple: Bool
        switch expr.minute {
        case .wildcard:
            minuteFiresMultiple = true
        case .step(let s):
            minuteFiresMultiple = s < 60
        case .list(let vals):
            minuteFiresMultiple = vals.count > 1
        case .range(let low, let high):
            minuteFiresMultiple = high > low
        case .specific:
            minuteFiresMultiple = false
        }

        let hourIsEvery: Bool
        switch expr.hour {
        case .wildcard, .step:
            hourIsEvery = true
        case .list(let vals):
            hourIsEvery = vals.count > 1
        case .range(let low, let high):
            hourIsEvery = high > low
        case .specific:
            hourIsEvery = false
        }

        // Sub-hourly: minute fires multiple times AND hour fires every hour
        if minuteFiresMultiple && hourIsEvery {
            throw CronParseError.subHourlyInterval
        }
    }
}

// MARK: - CronExpression

/// A parsed 5-field POSIX cron expression.
public struct CronExpression: Codable, Sendable, Equatable {
    public let raw: String
    public let minute: CronField
    public let hour: CronField
    public let dayOfMonth: CronField
    public let month: CronField
    public let dayOfWeek: CronField

    /// Compute the next occurrence after the given date.
    public func nextOccurrence(after date: Date, calendar: Calendar = .gregorian(timeZone: .gmt)) -> Date {
        var cal = calendar

        // Start from the next minute
        var components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0

        // Advance by 1 minute to avoid matching the current time
        guard let startDate = cal.date(from: components),
              let seed = cal.date(byAdding: .minute, value: 1, to: startDate) else {
            return date
        }

        var candidate = seed
        // Safety: limit iterations to avoid infinite loops (covers ~4 years)
        let maxIterations = 525_960
        for _ in 0..<maxIterations {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: candidate)
            guard let cMonth = comps.month,
                  let cDay = comps.day,
                  let cHour = comps.hour,
                  let cMinute = comps.minute,
                  let cWeekday = comps.weekday else {
                return date
            }

            // Convert Calendar weekday (1=Sunday) to cron weekday (0=Sunday)
            let cronWeekday = cWeekday - 1

            if !month.matches(cMonth) {
                // Advance to first day of next month
                candidate = advanceToNextMonth(candidate, cal: cal)
                continue
            }

            if !dayOfMonth.matches(cDay) || !dayOfWeek.matches(cronWeekday) {
                candidate = advanceToNextDay(candidate, cal: cal)
                continue
            }

            if !hour.matches(cHour) {
                candidate = advanceToNextHour(candidate, cal: cal)
                continue
            }

            if !minute.matches(cMinute) {
                candidate = cal.date(byAdding: .minute, value: 1, to: candidate) ?? date
                continue
            }

            return candidate
        }

        return date
    }

    /// Human-readable summary of the cron expression.
    public var humanReadable: String {
        raw
    }

    // MARK: - Advance Helpers

    private func advanceToNextMonth(_ date: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let startOfMonth = cal.date(from: comps) else { return date }
        return cal.date(byAdding: .month, value: 1, to: startOfMonth) ?? date
    }

    private func advanceToNextDay(_ date: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let startOfDay = cal.date(from: comps) else { return date }
        return cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    }

    private func advanceToNextHour(_ date: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        comps.minute = 0
        comps.second = 0
        guard let startOfHour = cal.date(from: comps) else { return date }
        return cal.date(byAdding: .hour, value: 1, to: startOfHour) ?? date
    }
}

// MARK: - Calendar Extension

extension Calendar {
    public static func gregorian(timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}

// MARK: - CronField

/// A single field in a cron expression.
public enum CronField: Codable, Sendable, Equatable {
    case wildcard
    case specific(Int)
    case range(Int, Int)
    case list([Int])
    case step(Int)

    /// Check if a value matches this field.
    public func matches(_ value: Int) -> Bool {
        switch self {
        case .wildcard:
            return true
        case .specific(let v):
            return value == v
        case .range(let low, let high):
            return value >= low && value <= high
        case .list(let values):
            return values.contains(value)
        case .step(let s):
            return s > 0 && value % s == 0
        }
    }
}

// MARK: - CronParseError

/// Errors thrown during cron expression parsing.
public enum CronParseError: Error, Equatable, Sendable {
    case invalidFieldCount(Int)
    case invalidStep(String, String)
    case valueOutOfRange(String, String, ClosedRange<Int>)
    case invalidRange(String, String)
    case subHourlyInterval
}
