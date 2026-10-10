import Foundation

enum WrappedPeriod: String, CaseIterable, Identifiable {
    case thisMonth
    case festiveSeason

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .thisMonth: return "This month"
        case .festiveSeason: return "Diwali season"
        }
    }
}

struct WrappedWindow: Equatable {
    var kind: WrappedPeriod
    /// Inclusive.
    var start: Date
    /// Exclusive.
    var end: Date
    var title: String
    /// Diwali night for a festive window, or the first of the month.
    var anchor: Date
}

/// Calendar math for Wrapped periods.
///
/// Diwali 2026 (Lakshmi Puja) is 8 Nov 2026. The festive window is 21 days
/// before that night through 4 days after, which covers the shopping lead-up,
/// Dhanteras, Diwali, and Bhai Dooj. Other years use published Gregorian
/// dates. Years that are not listed are not guessed.
enum WrappedCalendar {
    static let diwaliAnchors: [Int: (month: Int, day: Int)] = [
        2024: (11, 1),
        2025: (10, 20),
        2026: (11, 8),
        2027: (10, 29),
        2028: (10, 17),
        2029: (11, 5),
        2030: (10, 26)
    ]

    static let leadUpDays = 21
    static let tailDays = 4

    static func window(for period: WrappedPeriod, now: Date, calendar: Calendar) -> WrappedWindow? {
        switch period {
        case .thisMonth:
            return monthWindow(containing: now, calendar: calendar)
        case .festiveSeason:
            return festiveWindow(relevantTo: now, calendar: calendar)
        }
    }

    static func monthWindow(containing date: Date, calendar: Calendar) -> WrappedWindow {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return WrappedWindow(
            kind: .thisMonth,
            start: start,
            end: end,
            title: formatted(start, calendar: calendar, format: "MMMM yyyy"),
            anchor: start
        )
    }

    static func festiveWindow(year: Int, calendar: Calendar) -> WrappedWindow? {
        guard let parts = diwaliAnchors[year] else { return nil }
        guard let anchor = calendar.date(from: DateComponents(year: year, month: parts.month, day: parts.day)) else {
            return nil
        }
        let anchorDay = calendar.startOfDay(for: anchor)
        guard
            let start = calendar.date(byAdding: .day, value: -leadUpDays, to: anchorDay),
            let end = calendar.date(byAdding: .day, value: tailDays + 1, to: anchorDay)
        else { return nil }

        return WrappedWindow(
            kind: .festiveSeason,
            start: calendar.startOfDay(for: start),
            end: calendar.startOfDay(for: end),
            title: "Diwali \(year)",
            anchor: anchorDay
        )
    }

    /// This year's season once it is under way or within `leadUpDays` of starting.
    /// Earlier than that, the previous completed season, when we know its date.
    static func festiveWindow(relevantTo now: Date, calendar: Calendar) -> WrappedWindow? {
        let year = calendar.component(.year, from: now)
        guard let thisYear = festiveWindow(year: year, calendar: calendar) else {
            return festiveWindow(year: year - 1, calendar: calendar)
        }
        if now >= thisYear.start {
            return thisYear
        }
        let daysUntil = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: thisYear.start
        ).day ?? 0
        if daysUntil > leadUpDays, let previous = festiveWindow(year: year - 1, calendar: calendar) {
            return previous
        }
        return thisYear
    }

    static func previousWindow(for window: WrappedWindow, calendar: Calendar) -> WrappedWindow? {
        switch window.kind {
        case .thisMonth:
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: window.start) ?? window.start
            return monthWindow(containing: dayBefore, calendar: calendar)
        case .festiveSeason:
            let year = calendar.component(.year, from: window.anchor)
            return festiveWindow(year: year - 1, calendar: calendar)
        }
    }

    static func formatted(_ date: Date, calendar: Calendar, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func dayLabel(for date: Date, calendar: Calendar) -> String {
        formatted(date, calendar: calendar, format: "EEE, d MMM")
    }

    static func shortDayLabel(for date: Date, calendar: Calendar) -> String {
        formatted(date, calendar: calendar, format: "d MMM")
    }
}
