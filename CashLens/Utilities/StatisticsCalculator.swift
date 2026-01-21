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
        
        let totalCurrent = filteredExpenses.reduce(0) { $0 + $1.amount }
        let totalPrevious = previousPeriodExpenses.reduce(0) { $0 + $1.amount }
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
            }.mapValues { $0.reduce(0) { $0 + $1.amount } }
            
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
            }.mapValues { $0.reduce(0) { $0 + $1.amount } }
            
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
        let total = filteredExpenses.reduce(0) { $0 + $1.amount }
        
        for category in defaultCategories {
            let amount = filteredExpenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
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
                .reduce(0) { $0 + $1.amount }
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
}


