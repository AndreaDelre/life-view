@testable import DesignSystem
import XCTest

final class QuickDatePresetsTests: XCTestCase {
    private var monFirstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }

    private var sunFirstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    func testTodayStripsTimeComponent() {
        // 2026-05-15 14:32 in Paris → 2026-05-15 00:00 in Paris.
        let calendar = monFirstCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 14, minute: 32)) ?? Date()

        let today = QuickDatePresets.today(calendar: calendar, now: now)

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: today)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func testTomorrowIsExactlyOneDayAfterToday() {
        let calendar = monFirstCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)) ?? Date()

        let today = QuickDatePresets.today(calendar: calendar, now: now)
        let tomorrow = QuickDatePresets.tomorrow(calendar: calendar, now: now)

        let delta = calendar.dateComponents([.day], from: today, to: tomorrow).day
        XCTAssertEqual(delta, 1)
    }

    func testEndOfWeekIsNextSundayWhenWeekStartsMonday() {
        let calendar = monFirstCalendar
        // 2026-05-15 is a Friday (year=2026, month=5, day=15 → ISO Fri).
        let friday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)) ?? Date()

        let endOfWeek = QuickDatePresets.endOfWeek(calendar: calendar, now: friday)
        // Expected: Sunday 2026-05-17.
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: endOfWeek)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 17)
        XCTAssertEqual(components.weekday, 1) // Sunday
    }

    func testEndOfWeekReturnsTodayWhenAlreadyAtWeekend() {
        let calendar = monFirstCalendar
        // 2026-05-17 is the next Sunday.
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)) ?? Date()

        let endOfWeek = QuickDatePresets.endOfWeek(calendar: calendar, now: sunday)
        let today = QuickDatePresets.today(calendar: calendar, now: sunday)
        XCTAssertEqual(endOfWeek, today)
    }

    func testEndOfWeekIsNextSaturdayWhenWeekStartsSunday() {
        let calendar = sunFirstCalendar
        // Pick a Thursday — 2026-05-14 in New York.
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 14)) ?? Date()

        let endOfWeek = QuickDatePresets.endOfWeek(calendar: calendar, now: thursday)
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: endOfWeek)
        // Next Saturday is 2026-05-16.
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.weekday, 7)
    }
}
