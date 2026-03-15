import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("ScheduleEvaluator")
struct ScheduleEvaluatorTests {

    private func makeSchedule(
        activeHours: [Int] = [8, 22],
        timezone: String = "Europe/Paris",
        days: [Int] = [1, 2, 3, 4, 5, 6, 7]
    ) -> Company.Schedule {
        Company.Schedule(activeHours: activeHours, timezone: timezone, days: days)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, timezone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Paris 14:00 weekday is within window")
    func parisWeekdayAfternoon() {
        // 2026-03-16 is a Monday
        let date = makeDate(year: 2026, month: 3, day: 16, hour: 14, timezone: "Europe/Paris")
        let schedule = makeSchedule()
        #expect(ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }

    @Test("Paris 03:00 is outside window")
    func parisNighttime() {
        let date = makeDate(year: 2026, month: 3, day: 16, hour: 3, timezone: "Europe/Paris")
        let schedule = makeSchedule()
        #expect(!ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }

    @Test("Sunday excluded when days = [1-5]")
    func sundayExcluded() {
        // 2026-03-15 is a Sunday
        let date = makeDate(year: 2026, month: 3, day: 15, hour: 14, timezone: "Europe/Paris")
        let schedule = makeSchedule(days: [1, 2, 3, 4, 5])
        #expect(!ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }

    @Test("Saturday included when days = [1-7]")
    func saturdayIncluded() {
        // 2026-03-14 is a Saturday
        let date = makeDate(year: 2026, month: 3, day: 14, hour: 10, timezone: "Europe/Paris")
        let schedule = makeSchedule()
        #expect(ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }

    @Test("Exact boundary: hour == start is inside")
    func startBoundary() {
        let date = makeDate(year: 2026, month: 3, day: 16, hour: 8, timezone: "Europe/Paris")
        let schedule = makeSchedule()
        #expect(ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }

    @Test("Exact boundary: hour == end is outside")
    func endBoundary() {
        let date = makeDate(year: 2026, month: 3, day: 16, hour: 22, timezone: "Europe/Paris")
        let schedule = makeSchedule()
        #expect(!ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }

    @Test("Different timezone: Tokyo 09:00 JST when Paris is 01:00 CET")
    func tokyoTimezone() {
        // 2026-03-16 09:00 JST
        let date = makeDate(year: 2026, month: 3, day: 16, hour: 9, timezone: "Asia/Tokyo")
        let schedule = makeSchedule(timezone: "Asia/Tokyo")
        #expect(ScheduleEvaluator.isWithinWindow(schedule: schedule, now: date))
    }
}
