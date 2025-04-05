import SwiftUI

struct ExpenseTrendChart: View {
    let expenses: [Expense]
    let timeFrame: ExpenseViewModel.TimeFrame
    let categoryColor: Color
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    // Computed property to check for iPad
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // Computed properties for chart data
    private var dateRange: [Date] {
        let calendar = Calendar.current
        let now = Date()
        var dates: [Date] = []
        
        switch timeFrame {
        case .day:
            // For day, show hourly data
            let startOfDay = calendar.startOfDay(for: now)
            for hour in 0..<24 {
                if let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
                    dates.append(date)
                }
            }
        case .week:
            // For week, show daily data for the past 7 days
            for day in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: -day, to: now) {
                    dates.append(calendar.startOfDay(for: date))
                }
            }
            dates.reverse()
        case .month:
            // For month, show data for each day of the current month
            if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
               let range = calendar.range(of: .day, in: .month, for: now) {
                for day in 1...range.count {
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                        dates.append(date)
                    }
                }
            }
        case .year:
            // For year, show monthly data
            if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                for month in 0..<12 {
                    if let date = calendar.date(byAdding: .month, value: month, to: startOfYear) {
                        dates.append(date)
                    }
                }
            }
        case .all:
            // For all, group by months for the available data
            if let oldestExpense = expenses.min(by: { $0.date < $1.date })?.date {
                var current = calendar.startOfDay(for: oldestExpense)
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
        
        return dates
    }
    
    private var dataPoints: [Double] {
        let calendar = Calendar.current
        
        return dateRange.map { date in
            let filteredExpenses: [Expense]
            
            switch timeFrame {
            case .day:
                // Group by hour
                filteredExpenses = expenses.filter {
                    calendar.component(.day, from: $0.date) == calendar.component(.day, from: date) &&
                    calendar.component(.hour, from: $0.date) == calendar.component(.hour, from: date)
                }
            case .week:
                // Group by day
                filteredExpenses = expenses.filter {
                    calendar.isDate($0.date, inSameDayAs: date)
                }
            case .month:
                // Group by day
                filteredExpenses = expenses.filter {
                    calendar.isDate($0.date, inSameDayAs: date)
                }
            case .year:
                // Group by month
                filteredExpenses = expenses.filter {
                    calendar.component(.year, from: $0.date) == calendar.component(.year, from: date) &&
                    calendar.component(.month, from: $0.date) == calendar.component(.month, from: date)
                }
            case .all:
                // Group by month
                filteredExpenses = expenses.filter {
                    calendar.component(.year, from: $0.date) == calendar.component(.year, from: date) &&
                    calendar.component(.month, from: $0.date) == calendar.component(.month, from: date)
                }
            }
            
            return filteredExpenses.reduce(0) { $0 + $1.amount }
        }
    }
    
    private var maxValue: Double {
        dataPoints.max() ?? 0
    }
    
    private var hasData: Bool {
        return !expenses.isEmpty && dataPoints.contains { $0 > 0 }
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
                // Summary indicators at the top - with adaptive sizing for iPad
                HStack(spacing: isIPad ? 36 : 24) {
                    // Total expenses indicator
                    VStack(alignment: .leading) {
                        Text("Total")
                            .font(isIPad ? .subheadline : .caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatCurrency(dataPoints.reduce(0, +)))
                            .font(isIPad ? .headline : .subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    // Average indicator
                    VStack(alignment: .leading) {
                        Text("Avg")
                            .font(isIPad ? .subheadline : .caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatCurrency(average))
                            .font(isIPad ? .headline : .subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    // Max indicator
                    VStack(alignment: .leading) {
                        Text("Max")
                            .font(isIPad ? .subheadline : .caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatCurrency(maxValue))
                            .font(isIPad ? .headline : .subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Trend indicator - larger on iPad
                    HStack(spacing: 6) {
                        Image(systemName: trend.icon)
                            .font(.system(size: isIPad ? 12 : 10, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(trend.description)
                            .font(.system(size: isIPad ? 12 : 10, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, isIPad ? 12 : 8)
                    .padding(.vertical, isIPad ? 6 : 4)
                    .background(trend.color)
                    .cornerRadius(isIPad ? 8 : 6)
                }
                .padding(.horizontal, isIPad ? 16 : 8)
                
                // Chart
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // Background grid
                        VStack(spacing: 0) {
                            ForEach(0..<4) { i in
                                Divider()
                                    .background(Color.secondary.opacity(0.2))
                                
                                // Y-axis labels (right side)
                                if maxValue > 0 {
                                    HStack {
                                        // Add left-side labels for wider screens
                                        if isIPad {
                                            Text(formatCurrency(maxValue * Double(4 - i) / 4))
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary.opacity(0.8))
                                                .padding(.leading, 4)
                                                .frame(width: 80, alignment: .leading)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(formatCurrency(maxValue * Double(4 - i) / 4))
                                            .font(.system(size: isIPad ? 10 : 8))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                }
                                
                                Spacer()
                                    .frame(height: geometry.size.height / 4)
                            }
                            Divider()
                                .background(Color.secondary.opacity(0.2))
                        }
                        
                        // Average line - enhanced for iPad
                        if average > 0 {
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(height: isIPad ? 1.5 : 1)
                                .offset(y: -CGFloat(average) / CGFloat(maxValue) * geometry.size.height)
                                .overlay(
                                    Text("Average")
                                        .font(.system(size: isIPad ? 11 : 8, weight: .medium))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 4)
                                        .background(Color.white.opacity(0.7))
                                        .cornerRadius(2)
                                        .offset(x: -geometry.size.width / 2 + (isIPad ? 40 : 12), y: isIPad ? -14 : -10)
                                )
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
                            LinearGradient(
                                gradient: Gradient(colors: [categoryColor.opacity(0.7), categoryColor]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
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
                            
                            // Limit tooltip density on iPad - show fewer tooltips
                            let shouldShowTooltip = isIPad ? 
                                // On iPad, only show every other significant point to avoid overlap
                                (index % 2 == 0 || point == maxValue) : 
                                // On iPhone, use the original logic
                                true
                            
                            // Only show tooltip for points above average or max/min
                            let isSignificant = maxValue > 0 && (
                                point > average * 1.2 || 
                                point == maxValue ||
                                (point > 0 && index == dataPoints.count - 1) || // Last non-zero point
                                (index > 0 && point > dataPoints[index-1] * 1.5) // Significant jump
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
                .frame(height: 200)
                .padding(.top, 20)
                .padding(.bottom, 10)
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