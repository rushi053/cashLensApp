import Foundation

struct Budget: Identifiable, Codable {
    var id = UUID()
    var name: String
    var amount: Double
    var period: Period
    var categoryFilter: CategoryFilter
    var alertAtPercentages: [Double]
    var isActive: Bool = true
    var createdAt: Date = Date()

    /// Fixed date window for `.custom` period budgets (trips, events,
    /// a visit home). Both are `nil` for weekly/monthly budgets.
    /// `customEndDate` is *inclusive* — "Jul 20 to Jul 27" tracks
    /// spending through the end of the 27th. Only date components
    /// matter; times are normalized to start-of-day in `dateRange`.
    var customStartDate: Date? = nil
    var customEndDate: Date? = nil

    enum Period: String, CaseIterable, Codable, Sendable {
        case weekly = "Weekly"
        case monthly = "Monthly"
        /// Fixed start/end dates stored on the Budget itself.
        /// Unlike weekly/monthly this never rolls over — after the
        /// end date the budget simply reads as ended.
        case custom = "Custom"

        var icon: String {
            switch self {
            case .weekly:  return "calendar.badge.clock"
            case .monthly: return "calendar"
            case .custom:  return "airplane.departure"
            }
        }

        /// Rolling window for the *current* period. Only valid for
        /// the repeating cases — `.custom` ranges live on the Budget
        /// (they need the stored dates), so all shared code should
        /// go through `Budget.dateRange` instead.
        var standardDateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .weekly:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
                return (start, end)
            case .monthly, .custom:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
                return (start, end)
            }
        }
    }

    // MARK: - Period window (budget-level)
    //
    // All date math lives on the Budget (not the Period enum) because
    // `.custom` needs the stored start/end dates. `end` is exclusive
    // (start of the day *after* the last tracked day) so the filter
    // `date >= start && date < end` works uniformly for all periods.

    var dateRange: (start: Date, end: Date) {
        switch period {
        case .weekly, .monthly:
            return period.standardDateRange
        case .custom:
            let cal = Calendar.current
            let start = cal.startOfDay(for: customStartDate ?? createdAt)
            let lastDay = cal.startOfDay(for: customEndDate ?? (customStartDate ?? createdAt))
            let end = cal.date(byAdding: .day, value: 1, to: max(start, lastDay)) ?? lastDay
            return (start, end)
        }
    }

    /// Days left in the window, counting today (≥ 0). For a custom
    /// budget that hasn't started yet this is the full length; after
    /// the end date it's 0.
    var daysRemaining: Int {
        let range = dateRange
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let lastInclusive = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: range.end) ?? range.end)
        if todayStart > lastInclusive { return 0 }
        let anchor = max(todayStart, cal.startOfDay(for: range.start))
        let diff = cal.dateComponents([.day], from: anchor, to: lastInclusive).day ?? 0
        return max(0, diff + 1)
    }

    /// Full period length in calendar days (for pace / projection).
    var totalDays: Int {
        let range = dateRange
        let cal = Calendar.current
        let start = cal.startOfDay(for: range.start)
        let lastInclusive = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: range.end) ?? range.end)
        return max(1, cal.dateComponents([.day], from: start, to: lastInclusive).day.map { $0 + 1 } ?? 1)
    }

    /// True for a custom-window budget whose end date is behind us.
    /// Weekly/monthly budgets never end — they roll over.
    var hasEnded: Bool {
        guard period == .custom else { return false }
        return Date() >= dateRange.end
    }

    enum CategoryFilter: Codable, Equatable, Hashable {
        case overall
        case defaultCategory(String)
        case customCategory(UUID)

        var displayName: String {
            switch self {
            case .overall:
                return "All Spending"
            case .defaultCategory(let rawValue):
                return Expense.Category(rawValue: rawValue)?.displayName ?? rawValue
            case .customCategory:
                return "Custom"
            }
        }

        var icon: String {
            switch self {
            case .overall:
                return "creditcard.fill"
            case .defaultCategory(let rawValue):
                return Expense.Category(rawValue: rawValue)?.icon ?? "tag.fill"
            case .customCategory:
                return "tag.fill"
            }
        }

        var isOverall: Bool {
            if case .overall = self { return true }
            return false
        }
    }

    static let defaultAlertPercentages: [Double] = [0.8, 1.0]
}
