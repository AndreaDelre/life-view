@testable import DesignSystem
import XCTest

final class QuickDatePresetsTests: XCTestCase {
    private var parisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }

    private var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Convenience: extract the date portion of the result as seen in
    /// UTC, since the contract is "midnight UTC of the local day".
    private func utcDay(of date: Date) -> DateComponents {
        utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - today

    func testTodayIsMidnightUTCOfLocalDay() {
        // 2026-05-15 14:32 in Paris is still May 15 UTC.
        let calendar = parisCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 14, minute: 32)) ?? Date()

        let today = QuickDatePresets.today(calendar: calendar, now: now)

        let components = utcDay(of: today)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func testTodayPreservesLocalDayAcrossTimeZoneBoundary() {
        // Regression: 2026-05-15 01:00 in Paris was emitted as midnight
        // local → 2026-05-14T23:00:00Z → Google read "hier". With the
        // fix, today returns 2026-05-15T00:00:00Z regardless of the
        // local hour.
        let calendar = parisCalendar
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 1)) ?? Date()

        let today = QuickDatePresets.today(calendar: calendar, now: earlyMorning)
        let components = utcDay(of: today)
        XCTAssertEqual(components.day, 15, "must reflect the local day, not the UTC day of midnight local")
    }

    // MARK: - tomorrow

    func testTomorrowIsOneLocalDayAfterToday() {
        let calendar = parisCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 9)) ?? Date()

        let tomorrow = QuickDatePresets.tomorrow(calendar: calendar, now: now)

        let components = utcDay(of: tomorrow)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.hour, 0)
    }

    // MARK: - endOfWeek

    func testEndOfWeekIsNextSundayWhenWeekStartsMonday() {
        let calendar = parisCalendar
        // 2026-05-15 is a Friday.
        let friday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12)) ?? Date()

        let endOfWeek = QuickDatePresets.endOfWeek(calendar: calendar, now: friday)

        let components = utcDay(of: endOfWeek)
        XCTAssertEqual(components.day, 17, "next Sunday after Friday 2026-05-15")
        XCTAssertEqual(components.hour, 0)
    }

    func testEndOfWeekReturnsTodayWhenAlreadyAtWeekend() {
        let calendar = parisCalendar
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 10)) ?? Date()

        let endOfWeek = QuickDatePresets.endOfWeek(calendar: calendar, now: sunday)
        XCTAssertEqual(endOfWeek, QuickDatePresets.today(calendar: calendar, now: sunday))
    }

    func testEndOfWeekIsNextSaturdayWhenWeekStartsSunday() {
        let calendar = newYorkCalendar
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 14, hour: 15)) ?? Date()

        let endOfWeek = QuickDatePresets.endOfWeek(calendar: calendar, now: thursday)

        let components = utcDay(of: endOfWeek)
        XCTAssertEqual(components.day, 16, "next Saturday after Thursday 2026-05-14 (NYC)")
    }

    // MARK: - normalizeForDueDate

    func testNormalizeForDueDateStripsTimeAndAnchorsAtMidnightUTC() {
        let calendar = parisCalendar
        let picked = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 45)) ?? Date()

        let normalised = QuickDatePresets.normalizeForDueDate(picked, calendar: calendar)

        let components = utcDay(of: normalised)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 1, "even at 23:45 local, the UTC day still matches the local day")
        XCTAssertEqual(components.hour, 0)
    }
}
