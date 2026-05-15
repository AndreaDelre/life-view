import Foundation

/// Pure date math behind ``QuickDatePicker``'s preset buttons. Lifted
/// into its own file so the calendar logic is unit-testable without a
/// SwiftUI host.
public enum QuickDatePresets {
    /// Beginning of today in `calendar`. The Google Tasks `due` field
    /// is date-only at storage (any time component is stripped server-
    /// side), so all presets emit midnight in the user's calendar.
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> Date {
        calendar.startOfDay(for: now)
    }

    public static func tomorrow(calendar: Calendar = .current, now: Date = Date()) -> Date {
        // swiftlint:disable:next force_unwrapping
        calendar.date(byAdding: .day, value: 1, to: today(calendar: calendar, now: now))!
    }

    /// End of the user's current week — the next *weekend day*, ie.
    /// Sunday in a Mon-first calendar, Saturday in a Sun-first one.
    /// Today if today *is* the weekend day already.
    public static func endOfWeek(calendar: Calendar = .current, now: Date = Date()) -> Date {
        let start = today(calendar: calendar, now: now)
        let weekday = calendar.component(.weekday, from: start)
        let weekendWeekday = calendar.firstWeekday == 1 ? 7 : 1
        let diff = (weekendWeekday - weekday + 7) % 7
        // swiftlint:disable:next force_unwrapping
        return calendar.date(byAdding: .day, value: diff, to: start)!
    }
}
