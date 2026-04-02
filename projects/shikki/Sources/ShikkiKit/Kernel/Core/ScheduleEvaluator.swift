import Foundation

/// Timezone-aware schedule window checker.
public struct ScheduleEvaluator: Sendable {
    public init() {}

    /// Returns true if `now` falls within the company's active hours and days.
    /// - `activeHours`: [startHour, endHour] in the company's timezone (e.g. [8, 22])
    /// - `days`: ISO weekday numbers (1=Monday .. 7=Sunday)
    public static func isWithinWindow(schedule: Company.Schedule, now: Date = .now) -> Bool {
        let tz = TimeZone(identifier: schedule.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        // Calendar.weekday: 1=Sunday, 2=Monday ... 7=Saturday
        // ISO: 1=Monday ... 7=Sunday
        let isoWeekday = weekday == 1 ? 7 : weekday - 1

        guard schedule.activeHours.count >= 2 else { return true }
        let start = schedule.activeHours[0]
        let end = schedule.activeHours[1]

        let inHours: Bool
        if end > start {
            // Normal range: e.g. [8, 22] or [5, 24]
            inHours = hour >= start && hour < end
        } else if end == 0 || end == 24 {
            // Until midnight: e.g. [5, 0] or [5, 24]
            inHours = hour >= start
        } else {
            // Wrap-around: e.g. [22, 6] = 22:00 to 06:00
            inHours = hour >= start || hour < end
        }
        let inDays = schedule.days.contains(isoWeekday)

        return inHours && inDays
    }
}
