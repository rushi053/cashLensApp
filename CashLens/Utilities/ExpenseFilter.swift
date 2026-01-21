import Foundation

struct ExpenseFilter {
    static func apply(
        expenses: [Expense],
        category: Expense.Category?,
        customCategoryId: UUID?,
        timeFrame: ExpenseViewModel.TimeFrame,
        referenceDate: Date = Date(),
        dateRangeStart: Date? = nil,
        dateRangeEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> [Expense] {
        var filtered = expenses
        
        // Category filter
        if let category = category {
            if category == .custom {
                if let customCategoryId = customCategoryId {
                    filtered = filtered.filter { $0.category == .custom && $0.customCategoryId == customCategoryId }
                } else {
                    filtered = filtered.filter { $0.category == .custom }
                }
            } else {
                filtered = filtered.filter { $0.category == category }
            }
        }
        
        // Date filter (half-open interval [start, end))
        // If an explicit date range is provided, it takes precedence over timeFrame.
        if let dateRangeStart, let dateRangeEnd {
            let start = calendar.startOfDay(for: dateRangeStart)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dateRangeEnd)) ?? dateRangeEnd
            filtered = filtered.filter { $0.date >= start && $0.date < endExclusive }
        } else if timeFrame != .all {
            let range = timeFrame.dateRange(referenceDate: referenceDate, calendar: calendar)
            filtered = filtered.filter { $0.date >= range.start && $0.date < range.end }
        }
        
        // Sort newest-first
        return filtered.sorted { $0.date > $1.date }
    }
}


