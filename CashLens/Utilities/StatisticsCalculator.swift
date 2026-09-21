import Foundation
import SwiftUI

struct StatisticsCalculator {
    static func previousPeriodExpenses(
        allExpenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Expense] {
        var startDate: Date
        var endDate: Date
        
        switch timeFrame {
        case .day:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            startDate = calendar.startOfDay(for: yesterday)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? now
        case .week:
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            endDate = currentWeekStart
            startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) ?? now
        case .month:
            let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            endDate = currentMonthStart
            startDate = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? now
        case .year:
            let currentYearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            endDate = currentYearStart
            startDate = calendar.date(byAdding: .year, value: -1, to: currentYearStart) ?? now
        case .all:
            return []
        }
        
        return allExpenses.filter { $0.date >= startDate && $0.date < endDate }
    }
    
    static func insights(
        filteredExpenses: [Expense],
        previousPeriodExpenses: [Expense],
        periodLabel: String,
        includeHighSpendingDay: Bool,
        formattedAmount: (Double) -> String
    ) -> [StatInsight] {
        var insights: [StatInsight] = []
        
        // Refund-aware totals: refunds subtract from the period total, so a
        // big return reads as a real reduction in spending.
        let totalCurrent = filteredExpenses.netTotal()
        let totalPrevious = previousPeriodExpenses.netTotal()
        let expenseCount = filteredExpenses.count
        let avgExpense = expenseCount > 0 ? totalCurrent / Double(expenseCount) : 0
        
        // Spending comparison
        if totalPrevious > 0 {
            let changePercent = ((totalCurrent - totalPrevious) / totalPrevious) * 100
            if abs(changePercent) > 5 {
                let trend = changePercent > 0 ? "increased" : "decreased"
                let icon = changePercent > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                let color = changePercent > 0 ? Color.red : Color.green
                insights.append(
                    StatInsight(
                        title: "Spending Trend",
                        description: "Your spending has \(trend) by \(String(format: "%.1f", abs(changePercent)))% vs. previous \(periodLabel)",
                        icon: icon,
                        color: color
                    )
                )
            }
        }
        
        // Top category insight
        if totalCurrent > 0, !filteredExpenses.isEmpty {
            let categorySpending = Dictionary(grouping: filteredExpenses) { expense in
                expense.category == .custom ? "Custom" : expense.category.rawValue
            }.mapValues { $0.netTotal() }
            
            if let topCategory = categorySpending.max(by: { $0.value < $1.value }) {
                let percentage = (topCategory.value / totalCurrent) * 100
                if percentage > 30 {
                    insights.append(
                        StatInsight(
                            title: "Top Category",
                            description: "\(topCategory.key) accounts for \(String(format: "%.0f", percentage))% of your spending",
                            icon: "chart.pie.fill",
                            color: .orange
                        )
                    )
                }
            }
        }
        
        // High spending day
        if includeHighSpendingDay {
            let dailySpending = Dictionary(grouping: filteredExpenses) { expense in
                Calendar.current.startOfDay(for: expense.date)
            }.mapValues { $0.netTotal() }
            
            if let maxDay = dailySpending.max(by: { $0.value < $1.value }),
               maxDay.value > avgExpense * 2 {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                insights.append(
                    StatInsight(
                        title: "High Spending Day",
                        description: "You spent \(formattedAmount(maxDay.value)) on \(formatter.string(from: maxDay.key))",
                        icon: "calendar.badge.exclamationmark",
                        color: .red
                    )
                )
            }
        }
        
        return insights
    }
    
    static func categoryBreakdown(
        filteredExpenses: [Expense],
        defaultCategories: [Expense.Category],
        customCategories: [CustomCategory]
    ) -> [CategoryExpenseData] {
        var categoryData: [CategoryExpenseData] = []
        // Net (refund-adjusted) totals so a category with a big refund shows
        // its true contribution. Categories whose net is non-positive are
        // hidden from the breakdown rather than rendered as a 0% wedge.
        let total = filteredExpenses.netTotal()
        
        for category in defaultCategories {
            let amount = filteredExpenses.filter { $0.category == category }.netTotal()
            if amount > 0 {
                let count = filteredExpenses.filter { $0.category == category }.count
                categoryData.append(
                    CategoryExpenseData(
                        name: category.rawValue,
                        amount: amount,
                        percentage: total > 0 ? (amount / total) * 100 : 0,
                        icon: category.icon,
                        color: Color.forCategory(category.color),
                        count: count
                    )
                )
            }
        }
        
        for customCategory in customCategories {
            let amount = filteredExpenses
                .filter { $0.category == .custom && $0.customCategoryId == customCategory.id }
                .netTotal()
            if amount > 0 {
                let count = filteredExpenses.filter { $0.category == .custom && $0.customCategoryId == customCategory.id }.count
                categoryData.append(
                    CategoryExpenseData(
                        name: customCategory.name,
                        amount: amount,
                        percentage: total > 0 ? (amount / total) * 100 : 0,
                        icon: customCategory.icon,
                        color: Color.forCategory(customCategory.colorName),
                        count: count
                    )
                )
            }
        }
        
        return categoryData.sorted { $0.amount > $1.amount }
    }

    // MARK: - Payment method breakdown (Pro)
    //
    // Aggregates the filtered set into per-payment-method slices so the
    // Statistics screen can render a donut + breakdown identical in shape
    // to the category breakdown. Refund-adjusted (`netTotal()`) so a chargeback
    // on a credit card actually reduces the credit slice rather than inflating
    // it. Slices with non-positive net are dropped, and we surface a separate
    // `unspecifiedAmount` so users see how much data is *missing* a method —
    // that nudges them to start tagging without polluting the donut.

    static func paymentMethodBreakdown(
        filteredExpenses: [Expense]
    ) -> PaymentMethodBreakdown {
        // Net spend per method, plus unspecified bucket for items with no
        // payment method set. We total only the non-negative bucket sums to
        // form the percentage denominator so refunds don't blow up shares.
        var totals: [PaymentMethod: Double] = [:]
        var counts: [PaymentMethod: Int] = [:]
        var unspecified: Double = 0
        var unspecifiedCount: Int = 0

        for expense in filteredExpenses {
            let signed = expense.signedAmount
            if let method = expense.paymentMethod {
                totals[method, default: 0] += signed
                counts[method, default: 0] += 1
            } else {
                unspecified += signed
                unspecifiedCount += 1
            }
        }

        let positiveTotal = totals.values.reduce(0) { $0 + max($1, 0) }
            + max(unspecified, 0)

        var slices: [PaymentMethodSlice] = []
        for method in PaymentMethod.allCases {
            let amount = totals[method] ?? 0
            guard amount > 0 else { continue }
            slices.append(
                PaymentMethodSlice(
                    method: method,
                    amount: amount,
                    percentage: positiveTotal > 0 ? (amount / positiveTotal) * 100 : 0,
                    count: counts[method] ?? 0
                )
            )
        }

        return PaymentMethodBreakdown(
            slices: slices.sorted { $0.amount > $1.amount },
            unspecifiedAmount: max(unspecified, 0),
            unspecifiedCount: unspecifiedCount,
            total: positiveTotal
        )
    }

    // MARK: - Weekday + top-day aggregation (used by the swipeable Trend pager)
    //
    // Both helpers are pure, O(n) over the filtered set, and safe to call from the
    // detached task that drives the Statistics screen's background recomputation.

    /// Computes the seven-row weekday breakdown (Sun → Sat) for the filtered set.
    ///
    /// `average` is the **per-weekday** mean — total spent on all Mondays divided
    /// by the number of Mondays that actually appear in `[rangeStart, rangeEnd]`.
    /// That normalisation means a 3-month range and a 1-week range stay comparable.
    static func weekdayAverages(
        filteredExpenses: [Expense],
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar = .current
    ) -> [WeekdayAveragePoint] {
        var totals: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for expense in filteredExpenses {
            let weekday = calendar.component(.weekday, from: expense.date)
            totals[weekday, default: 0] += expense.signedAmount
            counts[weekday, default: 0] += 1
        }

        // Count how many times each weekday appears inside the range, capped to a
        // sane loop length to avoid runaway iteration when someone selects `.all`.
        var occurrences: [Int: Int] = [:]
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        let maxDays = 366 * 5
        var day = start
        var iterations = 0
        while day <= end, iterations < maxDays {
            let weekday = calendar.component(.weekday, from: day)
            occurrences[weekday, default: 0] += 1
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(86_400)
            iterations += 1
        }

        var points: [WeekdayAveragePoint] = (1...7).map { wd in
            let total = totals[wd] ?? 0
            let appearances = max(1, occurrences[wd] ?? 1)
            return WeekdayAveragePoint(
                weekday: wd,
                average: total / Double(appearances),
                total: total,
                count: counts[wd] ?? 0,
                isHighest: false
            )
        }

        if let maxAverage = points.map(\.average).max(), maxAverage > 0 {
            for i in points.indices where points[i].average == maxAverage {
                points[i].isHighest = true
            }
        }
        return points
    }

    /// Returns the top N days (by aggregated spend) within the filtered set.
    /// Small `limit` values keep this effectively free even for very large inputs.
    static func topSpendingDays(
        filteredExpenses: [Expense],
        limit: Int = 5,
        calendar: Calendar = .current
    ) -> [TopDayPoint] {
        var totals: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for expense in filteredExpenses {
            let day = calendar.startOfDay(for: expense.date)
            totals[day, default: 0] += expense.signedAmount
            counts[day, default: 0] += 1
        }

        return totals
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { TopDayPoint(date: $0.key, amount: $0.value, count: counts[$0.key] ?? 0) }
    }
}


