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

    enum Period: String, CaseIterable, Codable {
        case weekly = "Weekly"
        case monthly = "Monthly"

        var icon: String {
            switch self {
            case .weekly:  return "calendar.badge.clock"
            case .monthly: return "calendar"
            }
        }

        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .weekly:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
                return (start, end)
            case .monthly:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
                return (start, end)
            }
        }

        var daysRemaining: Int {
            let range = dateRange
            let cal = Calendar.current
            let todayStart = cal.startOfDay(for: Date())
            let lastInclusive = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: range.end) ?? range.end)
            if todayStart > lastInclusive { return 0 }
            let diff = cal.dateComponents([.day], from: todayStart, to: lastInclusive).day ?? 0
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
