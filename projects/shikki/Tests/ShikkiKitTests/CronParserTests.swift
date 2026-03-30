import Testing
import Foundation
@testable import ShikkiKit

@Suite("CronParser")
struct CronParserTests {

    let parser = CronParser()

    // Use a fixed calendar for deterministic tests
    var calendar: Calendar {
        Calendar.gregorian(timeZone: .gmt)
    }

    // MARK: - Parsing

    @Test func parsesStandardCron() throws {
        let expr = try parser.parse("0 5 * * *")
        #expect(expr.minute == .specific(0))
        #expect(expr.hour == .specific(5))
        #expect(expr.dayOfMonth == .wildcard)
        #expect(expr.month == .wildcard)
        #expect(expr.dayOfWeek == .wildcard)
    }

    @Test func wildcardMatchesAll() throws {
        let field = CronField.wildcard
        #expect(field.matches(0))
        #expect(field.matches(30))
        #expect(field.matches(59))
    }

    @Test func rangeExpression() throws {
        let expr = try parser.parse("0 1 * * 1-5")
        #expect(expr.dayOfWeek == .range(1, 5))

        let field = CronField.range(1, 5)
        #expect(field.matches(1))
        #expect(field.matches(3))
        #expect(field.matches(5))
        #expect(!field.matches(0))
        #expect(!field.matches(6))
    }

    @Test func stepExpression() throws {
        let expr = try parser.parse("0 */6 * * *")
        #expect(expr.hour == .step(6))

        let field = CronField.step(6)
        #expect(field.matches(0))
        #expect(field.matches(6))
        #expect(field.matches(12))
        #expect(field.matches(18))
        #expect(!field.matches(3))
        #expect(!field.matches(7))
    }

    @Test func listExpression() throws {
        let expr = try parser.parse("0 1 * * 1,3,5")
        #expect(expr.dayOfWeek == .list([1, 3, 5]))

        let field = CronField.list([1, 3, 5])
        #expect(field.matches(1))
        #expect(field.matches(3))
        #expect(field.matches(5))
        #expect(!field.matches(2))
        #expect(!field.matches(4))
    }

    @Test func invalidExpressionThrows() {
        // Wrong number of fields
        #expect(throws: CronParseError.self) {
            try parser.parse("0 5 *")
        }

        // Value out of range
        #expect(throws: CronParseError.self) {
            try parser.parse("0 25 * * *")
        }

        // Invalid range
        #expect(throws: CronParseError.self) {
            try parser.parse("0 5 * * 8")
        }
    }

    @Test func rejectsSubHourly() {
        // Every minute, every hour = sub-hourly
        #expect(throws: CronParseError.subHourlyInterval) {
            try parser.parse("* * * * *")
        }

        // Every 15 minutes, every hour = sub-hourly
        #expect(throws: CronParseError.subHourlyInterval) {
            try parser.parse("*/15 * * * *")
        }

        // Every minute, every 2 hours = sub-hourly (multiple minutes per hour window)
        #expect(throws: CronParseError.subHourlyInterval) {
            try parser.parse("* */2 * * *")
        }
    }

    // MARK: - Next Occurrence

    @Test func nextOccurrence_minuteField() throws {
        let expr = try parser.parse("30 5 * * *")
        // 2026-03-25 04:00:00 UTC → next should be 2026-03-25 05:30:00 UTC
        let date = makeDate(year: 2026, month: 3, day: 25, hour: 4, minute: 0)
        let next = expr.nextOccurrence(after: date, calendar: calendar)

        let comps = calendar.dateComponents([.hour, .minute, .day], from: next)
        #expect(comps.hour == 5)
        #expect(comps.minute == 30)
        #expect(comps.day == 25)
    }

    @Test func nextOccurrence_hourField() throws {
        let expr = try parser.parse("0 3 * * *")
        // 2026-03-25 04:00:00 UTC → next should be 2026-03-26 03:00:00 UTC (already past 03:00 today)
        let date = makeDate(year: 2026, month: 3, day: 25, hour: 4, minute: 0)
        let next = expr.nextOccurrence(after: date, calendar: calendar)

        let comps = calendar.dateComponents([.hour, .minute, .day], from: next)
        #expect(comps.hour == 3)
        #expect(comps.minute == 0)
        #expect(comps.day == 26)
    }

    @Test func nextOccurrence_dayOfWeek() throws {
        // Every Monday at 09:00 (day-of-week 1 = Monday in cron)
        let expr = try parser.parse("0 9 * * 1")
        // 2026-03-25 is a Wednesday → next Monday is 2026-03-30
        let date = makeDate(year: 2026, month: 3, day: 25, hour: 10, minute: 0)
        let next = expr.nextOccurrence(after: date, calendar: calendar)

        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: next)
        // Calendar weekday: Monday = 2
        #expect(comps.weekday == 2)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        comps.timeZone = .gmt
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
