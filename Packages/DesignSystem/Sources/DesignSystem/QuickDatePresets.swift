import Foundation

/// Pure date math behind ``QuickDatePicker``'s preset buttons. Lifted
/// into its own file so the calendar logic is unit-testable without a
/// SwiftUI host.
///
/// Every preset returns midnight **UTC** of the user's intended local
/// day — not midnight local. The Google Tasks API stores `due` as
/// RFC3339 UTC but ignores the time component (date-only field), so if
/// we send `2026-05-16T00:00:00+02:00` (midnight in Paris) Google
/// records the *date portion of the UTC string* — `2026-05-15` — and
/// the user sees a task due "hier". Materialising at midnight UTC of
/// the local day keeps the date portion stable round-tripping.
public enum QuickDatePresets {
    /// Today, anchored at midnight UTC of the local calendar day.
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> Date {
        utcMidnight(of: now, in: calendar)
    }

    /// Tomorrow, anchored at midnight UTC of the local calendar day.
    public static func tomorrow(calendar: Calendar = .current, now: Date = Date()) -> Date {
        // swiftlint:disable:next force_unwrapping
        let local = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return utcMidnight(of: local, in: calendar)
    }

    /// End of the user's current week — the next *weekend day*, ie.
    /// Sunday in a Mon-first calendar, Saturday in a Sun-first one.
    /// Today if today *is* the weekend day already. Anchored at
    /// midnight UTC of that local day.
    public static func endOfWeek(calendar: Calendar = .current, now: Date = Date()) -> Date {
        let start = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: start)
        let weekendWeekday = calendar.firstWeekday == 1 ? 7 : 1
        let diff = (weekendWeekday - weekday + 7) % 7
        // swiftlint:disable:next force_unwrapping
        let local = calendar.date(byAdding: .day, value: diff, to: start)!
        return utcMidnight(of: local, in: calendar)
    }

    /// Normalises any `Date` (typically from a SwiftUI `DatePicker`) to
    /// midnight UTC of its local calendar day. Use at every entry
    /// point that produces a `due` value out of user input.
    public static func normalizeForDueDate(_ date: Date, calendar: Calendar = .current) -> Date {
        utcMidnight(of: date, in: calendar)
    }

    /// Builds a `Date` at midnight UTC carrying the same year/month/day
    /// that `local` falls on in `calendar`. Foundation has no built-in
    /// helper for this so we round-trip via `DateComponents`.
    private static func utcMidnight(of local: Date, in calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: local)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        // The fallback to `local` is theoretically unreachable —
        // `date(from:)` only returns nil for components that cannot
        // form a valid date, which year/month/day from a valid date
        // never can.
        return utc.date(from: components) ?? local
    }
}
