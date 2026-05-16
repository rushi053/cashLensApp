import SwiftUI

struct ExpenseTrendChart: View {
    /// Pre-bucketed dates (one per chart x-tick).
    /// Built off-main in `recomputeStatsNow` and handed in here so the chart
    /// view body stays declarative — the audit caught the old in-body
    /// `chartData` recompute as a P1 hot path.
    let chartDates: [Date]
    /// Pre-bucketed values aligned to `chartDates`.
    let chartValues: [Double]
    let timeFrame: ExpenseViewModel.TimeFrame
    let categoryColor: Color
    @EnvironmentObject var viewModel: ExpenseViewModel

    // Computed property to check for iPad
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    private var dateRange: [Date] { chartDates }
    private var dataPoints: [Double] { chartValues }

    private var maxValue: Double {
        dataPoints.max() ?? 0
    }

    private var hasData: Bool {
        return dataPoints.contains { $0 > 0 }
    }

    private var average: Double {
        let nonZeroPoints = dataPoints.filter { $0 > 0 }
        return nonZeroPoints.isEmpty ? 0 : nonZeroPoints.reduce(0, +) / Double(nonZeroPoints.count)
    }

    private var trend: TrendDirection {
        if dataPoints.count < 2 {
            return .neutral
        }

        // Calculate a simple trend by comparing first and last points
        let nonZeroPoints = dataPoints.filter { $0 > 0 }
        if nonZeroPoints.count < 2 {
            return .neutral
        }

        let firstHalf = Array(nonZeroPoints.prefix(nonZeroPoints.count / 2))
        let secondHalf = Array(nonZeroPoints.suffix(nonZeroPoints.count / 2))

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        if secondAvg > firstAvg * 1.05 {
            return .increasing
        } else if secondAvg < firstAvg * 0.95 {
            return .decreasing
        } else {
            return .neutral
        }
    }
    
    enum TrendDirection {
        case increasing, decreasing, neutral
        
        var icon: String {
            switch self {
            case .increasing: return "arrow.up.right"
            case .decreasing: return "arrow.down.right"
            case .neutral: return "arrow.right"
            }
        }
        
        var color: Color {
            switch self {
            case .increasing: return .red
            case .decreasing: return .green
            case .neutral: return .orange
            }
        }
        
        var description: String {
            switch self {
            case .increasing: return "Up"
            case .decreasing: return "Down"
            case .neutral: return "Stable"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasData {
                // Chart
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // Background grid
                        VStack(spacing: 0) {
                            ForEach(0..<3) { i in
                                Divider()
                                    .background(Color.secondary.opacity(0.2))
                                
                                Spacer()
                                    .frame(height: geometry.size.height / 3)
                            }
                            Divider()
                                .background(Color.secondary.opacity(0.2))
                        }
                        
                        // Fill area under the curve
                        Path { path in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let stepWidth = width / CGFloat(dataPoints.count - 1)
                            
                            // Start at the bottom left
                            path.move(to: CGPoint(x: 0, y: height))
                            
                            // Add first data point connecting to bottom
                            let firstX = 0
                            let firstY = height - (CGFloat(dataPoints.first ?? 0) / CGFloat(maxValue) * height)
                            path.addLine(to: CGPoint(x: CGFloat(firstX), y: firstY))
                            
                            // Add lines for each data point
                            for i in 1..<dataPoints.count {
                                let x = stepWidth * CGFloat(i)
                                let y = height - (CGFloat(dataPoints[i]) / CGFloat(maxValue) * height)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            
                            // Close the path by adding a line to the bottom right and then bottom left
                            path.addLine(to: CGPoint(x: width, y: height))
                            path.addLine(to: CGPoint(x: 0, y: height))
                        }
                        .fill(categoryColor.opacity(0.15))
                        
                        // Line chart
                        Path { path in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let stepWidth = width / CGFloat(dataPoints.count - 1)
                            
                            for (index, point) in dataPoints.enumerated() {
                                let x = stepWidth * CGFloat(index)
                                let y = height - (CGFloat(point) / CGFloat(maxValue) * height)
                                
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .trim(from: 0, to: 1)
                        .stroke(
                            categoryColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: categoryColor.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        // Data points with value indicators for significant points - enhanced for iPad
                        ForEach(0..<dataPoints.count, id: \.self) { index in
                            let point = dataPoints[index]
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let stepWidth = width / CGFloat(dataPoints.count - 1)
                            let x = stepWidth * CGFloat(index)
                            let y = height - (CGFloat(point) / CGFloat(maxValue) * height)
                            
                            // Limit tooltip density to prevent overlap
                            let shouldShowTooltip: Bool = {
                                if isIPad {
                                    // On iPad, show fewer tooltips - only max, min, and every 3rd significant point
                                    return (point == maxValue || 
                                           (point > 0 && index == dataPoints.count - 1) || 
                                           index % 3 == 0) && point > average * 0.8
                                } else {
                                    // On iPhone, be even more restrictive
                                    let dataPointCount = dataPoints.count
                                    if dataPointCount <= 7 {
                                        // For small datasets, show max and last non-zero
                                        return point == maxValue || (point > 0 && index == dataPoints.count - 1)
                                    } else {
                                        // For larger datasets, only show max value and a few key points
                                        return point == maxValue || 
                                               (index == dataPoints.count - 1 && point > 0) ||
                                               (index % (dataPointCount / 3) == 0 && point > average * 1.5)
                                    }
                                }
                            }()
                            
                            // Only show tooltip for significant points that meet spacing requirements
                            let isSignificant = maxValue > 0 && (
                                point == maxValue || 
                                (point > 0 && index == dataPoints.count - 1) || // Last non-zero point
                                point > average * 1.5 // Only very high points
                            )
                            
                            ZStack {
                                // Point - larger on iPad
                                Circle()
                                    .fill(categoryColor)
                                    .frame(width: isIPad ? (isSignificant ? 10 : 8) : (isSignificant ? 8 : 6), 
                                           height: isIPad ? (isSignificant ? 10 : 8) : (isSignificant ? 8 : 6))
                                
                                // Only show tooltip for significant points with density control
                                if isSignificant && shouldShowTooltip {
                                    // Tooltip - larger and more readable on iPad
                                    Text(formatCurrency(point))
                                        .font(.system(size: isIPad ? 10 : 8))
                                        .padding(.horizontal, isIPad ? 6 : 4)
                                        .padding(.vertical, isIPad ? 4 : 2)
                                        .background(Color.white.opacity(0.95))
                                        .cornerRadius(isIPad ? 6 : 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: isIPad ? 6 : 4)
                                                .stroke(categoryColor, lineWidth: isIPad ? 1.5 : 1)
                                        )
                                        .offset(y: isIPad ? -22 : -16) // Move higher on iPad for better spacing
                                        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                                }
                            }
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: isIPad ? 300 : 200)
                
                // X-axis labels with adaptive spacing for different screen sizes
                HStack(spacing: 0) {
                    // Show more labels on iPad
                    let maxLabels = isIPad ? 12 : 7
                    let step = max(1, dateRange.count / maxLabels)
                    
                    ForEach(0..<min(dateRange.count, maxLabels), id: \.self) { index in
                        let labelIndex = index * step
                        
                        if labelIndex < dateRange.count {
                            Text(formatDate(dateRange[labelIndex]))
                                .font(isIPad ? .caption : .caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, isIPad ? 16 : 8)
                .padding(.top, 8) // Extra space between chart and labels
            } else {
                // No data view with more informative message - enhanced for iPad
                VStack(spacing: isIPad ? 24 : 16) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: isIPad ? 60 : 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: isIPad ? 8 : 4) {
                        Text("No trend data available")
                            .font(isIPad ? .title3 : .headline)
                            .foregroundColor(.secondary)
                        
                        Text("Add more expenses to see your spending trends")
                            .font(isIPad ? .subheadline : .caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, isIPad ? 24 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: isIPad ? 300 : 200)
                .background(Color.secondarySystemBackground.opacity(0.5))
                .cornerRadius(16)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        switch timeFrame {
        case .day:
            formatter.dateFormat = "ha"
        case .week, .month:
            formatter.dateFormat = "d MMM"
        case .year, .all:
            formatter.dateFormat = "MMM"
        }
        
        return formatter.string(from: date)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = viewModel.currencySymbol
        formatter.maximumFractionDigits = 0 // No decimal places for better readability in small space
        
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Pre-aggregation helper
//
// Static helper that does the bucket math the view body used to do per
// redraw. `nonisolated` so the StatisticsView recompute can call it from
// `Task.detached` and hand the result into the new pre-built initializer.

extension ExpenseTrendChart {
    /// Convenience initializer that pre-builds the chart series eagerly.
    /// Use this in previews and any path where the caller doesn't have
    /// pre-aggregated data — production paths in StatisticsView should
    /// compute the series off-main and use the primary initializer.
    init(
        expenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        categoryColor: Color
    ) {
        let series = ExpenseTrendChart.buildChartData(
            expenses: expenses,
            timeFrame: timeFrame,
            referenceDate: Date()
        )
        self.init(
            chartDates: series.dates,
            chartValues: series.values,
            timeFrame: timeFrame,
            categoryColor: categoryColor
        )
    }

    /// Pure value-type bucket-builder. Safe to call from any context — the
    /// audit flagged the old body-side computation as P1 because it ran
    /// every time the parent invalidated. Now `recomputeStatsNow` calls
    /// this once per recompute on the background task.
    nonisolated static func buildChartData(
        expenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        referenceDate: Date
    ) -> (dates: [Date], values: [Double]) {
        let calendar = Calendar.current
        let now = referenceDate

        // Single-pass bucket aggregation.
        var groupedAmounts: [String: Double] = [:]
        for expense in expenses {
            let key = bucketKey(for: expense.date, timeFrame: timeFrame, calendar: calendar)
            groupedAmounts[key, default: 0] += expense.signedAmount
        }

        var dates: [Date] = []
        switch timeFrame {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            for hour in 0..<24 {
                if let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
                    dates.append(date)
                }
            }
        case .week:
            for day in (0..<7).reversed() {
                if let date = calendar.date(byAdding: .day, value: -day, to: now) {
                    dates.append(calendar.startOfDay(for: date))
                }
            }
        case .month:
            if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
               let range = calendar.range(of: .day, in: .month, for: now) {
                for day in 1...range.count {
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                        dates.append(date)
                    }
                }
            }
        case .year:
            if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                for month in 0..<12 {
                    if let date = calendar.date(byAdding: .month, value: month, to: startOfYear) {
                        dates.append(date)
                    }
                }
            }
        case .all:
            if let oldestExpense = expenses.min(by: { $0.date < $1.date })?.date {
                var current = calendar.date(from: calendar.dateComponents([.year, .month], from: oldestExpense)) ?? calendar.startOfDay(for: oldestExpense)
                let endDate = calendar.startOfDay(for: now)

                while current <= endDate {
                    dates.append(current)
                    if let nextMonth = calendar.date(byAdding: .month, value: 1, to: current) {
                        current = nextMonth
                    } else {
                        break
                    }
                }
            }
        }

        let values = dates.map { date -> Double in
            let key = bucketKey(for: date, timeFrame: timeFrame, calendar: calendar)
            return groupedAmounts[key, default: 0]
        }
        return (dates, values)
    }

    /// Generate a unique bucket key for grouping expenses.
    nonisolated private static func bucketKey(
        for date: Date,
        timeFrame: ExpenseViewModel.TimeFrame,
        calendar: Calendar
    ) -> String {
        switch timeFrame {
        case .day:
            let day = calendar.component(.day, from: date)
            let hour = calendar.component(.hour, from: date)
            return "\(day)-\(hour)"
        case .week, .month:
            let year = calendar.component(.year, from: date)
            let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
            return "\(year)-\(day)"
        case .year, .all:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return "\(year)-\(month)"
        }
    }
}

struct ExpenseTrendChart_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ExpenseTrendChart(
                expenses: Expense.sampleData,
                timeFrame: .month,
                categoryColor: .appPrimary
            )
            .padding()
            .background(Color.systemBackground)
            .cornerRadius(16)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .previewLayout(.sizeThatFits)
    }
} 