import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var selectedTimeFrame: ExpenseViewModel.TimeFrame = .month
    @State private var showingAddExpense = false
    @State private var selectedCategory: Expense.Category? = nil
    @State private var animateCards = false
    
    // MARK: - Computed Properties
    private var filteredExpenses: [Expense] {
        var filtered = viewModel.expenses
        
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeFrame {
        case .day:
            filtered = filtered.filter { calendar.isDateInToday($0.date) }
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            filtered = filtered.filter { $0.date >= startOfWeek }
        case .month:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            filtered = filtered.filter { $0.date >= startOfMonth }
        case .year:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now))!
            filtered = filtered.filter { $0.date >= startOfYear }
        case .all:
            break
        }
        
        if let category = selectedCategory {
            if category == .custom {
                if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId {
                    filtered = filtered.filter { 
                        $0.category == .custom && $0.customCategoryId == selectedCustomCategoryId 
                    }
                } else {
                    filtered = filtered.filter { $0.category == .custom }
                }
            } else {
                filtered = filtered.filter { $0.category == category }
            }
        }
        
        return filtered.sorted { $0.date > $1.date }
    }
    
    private var previousPeriodExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        var startDate: Date
        var endDate: Date
        
        switch selectedTimeFrame {
        case .day:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            startDate = calendar.startOfDay(for: yesterday)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        case .week:
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            endDate = currentWeekStart
            startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
        case .month:
            let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            endDate = currentMonthStart
            startDate = calendar.date(byAdding: .month, value: -1, to: currentMonthStart)!
        case .year:
            let currentYearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!
            endDate = currentYearStart
            startDate = calendar.date(byAdding: .year, value: -1, to: currentYearStart)!
        case .all:
            return []
        }
        
        return viewModel.expenses.filter { expense in
            expense.date >= startDate && expense.date < endDate
        }
    }
    
    private var insights: [StatInsight] {
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
                insights.append(StatInsight(
                    title: "Spending Trend",
                    description: "Your spending has \(trend) by \(String(format: "%.1f", abs(changePercent)))% vs. previous \(selectedTimeFrame.rawValue.lowercased())",
                    icon: icon,
                    color: color
                ))
            }
        }
        
        // Top category insight
        if !filteredExpenses.isEmpty {
            let categorySpending = Dictionary(grouping: filteredExpenses) { expense in
                expense.category == .custom ? "Custom" : expense.category.rawValue
            }.mapValues { $0.reduce(0) { $0 + $1.amount } }
            
            if let topCategory = categorySpending.max(by: { $0.value < $1.value }) {
                let percentage = (topCategory.value / totalCurrent) * 100
                if percentage > 30 {
                    insights.append(StatInsight(
                        title: "Top Category",
                        description: "\(topCategory.key) accounts for \(String(format: "%.0f", percentage))% of your spending",
                        icon: "chart.pie.fill",
                        color: .orange
                    ))
                }
            }
        }
        
        // High spending days
        if selectedTimeFrame == .month || selectedTimeFrame == .week {
            let dailySpending = Dictionary(grouping: filteredExpenses) { expense in
                Calendar.current.startOfDay(for: expense.date)
            }.mapValues { $0.reduce(0) { $0 + $1.amount } }
            
            if let maxDay = dailySpending.max(by: { $0.value < $1.value }),
               maxDay.value > avgExpense * 2 {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                insights.append(StatInsight(
                    title: "High Spending Day",
                    description: "You spent \(viewModel.formattedAmount(maxDay.value)) on \(formatter.string(from: maxDay.key))",
                    icon: "calendar.badge.exclamationmark",
                    color: .red
                ))
            }
        }
        
        return insights
    }
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // MARK: - Main Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection
                    
                    // Control Section
                    controlSection
                    
                    if viewModel.expenses.isEmpty {
                        emptyStateView
                    } else {
                        // Statistics Content
                        statisticsContent
                    }
                }
                .padding(.horizontal, isIPad ? 32 : 20)
                .padding(.bottom, 120)
            }
            .background(Color.systemBackground)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                    animateCards = true
                }
            }
        }
        .if(isIPad) { view in
            view.navigationViewStyle(StackNavigationViewStyle())
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Top padding
            Rectangle()
                .fill(Color.clear)
                .frame(height: 20)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Statistics")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(getHeaderSubtitle())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Control Section
    private var controlSection: some View {
        VStack(spacing: 20) {
            // Time Frame Selector
            VStack(spacing: 12) {
                HStack {
                    Text("Time Period")
                        .font(isIPad ? .title3 : .headline)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                            timeFrameButton(timeFrame)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Category Filter
            VStack(spacing: 12) {
                HStack {
                    Text("Filter by Category")
                        .font(isIPad ? .title3 : .headline)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if selectedCategory != nil {
                        Button("Clear") {
                            HapticManager.shared.selectionChanged()
                            withAnimation(.spring()) {
                                selectedCategory = nil
                                viewModel.selectedCustomCategoryId = nil
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                    }
                }
                
                categorySelector
            }
        }
        .padding(isIPad ? 24 : 20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Statistics Content
    private var statisticsContent: some View {
        VStack(spacing: 24) {
            // Summary Cards
            summaryCardsSection
            
            // Insights Section
            if !insights.isEmpty {
                insightsSection
            }
            
            // Category Breakdown
            categoryBreakdownSection
            
            // Expense Trend
            expenseTrendSection
        }
    }
    
    // MARK: - Summary Cards Section
    private var summaryCardsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Overview")
                    .font(isIPad ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            if isIPad {
                HStack(spacing: 16) {
                    summaryCard(
                        title: "Total Spent",
                        value: viewModel.formattedAmount(totalExpenses()),
                        subtitle: selectedTimeFrame.rawValue,
                        icon: "creditcard.fill",
                        color: .appPrimary,
                        comparison: comparisonText()
                    )
                    
                    summaryCard(
                        title: "Transactions",
                        value: "\(filteredExpenses.count)",
                        subtitle: selectedTimeFrame.rawValue,
                        icon: "list.bullet.circle.fill",
                        color: .jordyBlue,
                        comparison: nil
                    )
                    
                    summaryCard(
                        title: "Average",
                        value: viewModel.formattedAmount(averageExpense()),
                        subtitle: "per transaction",
                        icon: "chart.bar.fill",
                        color: .teaRose,
                        comparison: nil
                    )
                }
            } else {
                VStack(spacing: 12) {
                    summaryCard(
                        title: "Total Spent",
                        value: viewModel.formattedAmount(totalExpenses()),
                        subtitle: selectedTimeFrame.rawValue,
                        icon: "creditcard.fill",
                        color: .appPrimary,
                        comparison: comparisonText()
                    )
                    
                    HStack(spacing: 12) {
                        summaryCard(
                            title: "Transactions",
                            value: "\(filteredExpenses.count)",
                            subtitle: selectedTimeFrame.rawValue,
                            icon: "list.bullet.circle.fill",
                            color: .jordyBlue,
                            comparison: nil
                        )
                        
                        summaryCard(
                            title: "Average",
                            value: viewModel.formattedAmount(averageExpense()),
                            subtitle: "per transaction",
                            icon: "chart.bar.fill",
                            color: .teaRose,
                            comparison: nil
                        )
                    }
                }
            }
        }
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
    }

    // MARK: - Insights Section
    private var insightsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Insights")
                    .font(isIPad ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: isIPad ? 2 : 1), spacing: 12) {
                ForEach(insights) { insight in
                    insightCard(insight)
                }
            }
        }
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: animateCards)
    }
    
    // MARK: - Category Breakdown Section
    private var categoryBreakdownSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Category Breakdown")
                    .font(isIPad ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
                
                if selectedCategory == nil {
                    Text("\(getCategoriesWithExpenses().count) categories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.tertiarySystemBackground)
                        .cornerRadius(8)
                }
            }
            
            VStack(spacing: 12) {
                if selectedCategory == nil {
                    ForEach(getCategoriesWithExpenses(), id: \.name) { categoryData in
                        enhancedCategoryRow(categoryData)
                    }
                } else {
                    if selectedCategory == .custom {
                        let customCategories = viewModel.getCustomCategories()
                        if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId,
                           let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                            let amount = totalExpenses(for: customCategory)
                            let categoryData = CategoryExpenseData(
                                name: customCategory.name,
                                amount: amount,
                                percentage: 100.0,
                                icon: customCategory.icon,
                                color: Color.forCategory(customCategory.colorName),
                                count: filteredExpenses.filter { $0.category == .custom && $0.customCategoryId == customCategory.id }.count
                            )
                            enhancedCategoryRow(categoryData)
                        }
                    } else {
                        let amount = totalExpenses(for: selectedCategory!)
                        let categoryData = CategoryExpenseData(
                            name: selectedCategory!.rawValue,
                            amount: amount,
                            percentage: 100.0,
                            icon: selectedCategory!.icon,
                            color: Color.forCategory(selectedCategory!.color),
                            count: filteredExpenses.filter { $0.category == selectedCategory! }.count
                        )
                        enhancedCategoryRow(categoryData)
                    }
                }
            }
            .padding(16)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
        }
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateCards)
    }
    
    // MARK: - Expense Trend Section
    private var expenseTrendSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Spending Trend")
                    .font(isIPad ? .title2 : .title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(selectedTimeFrame.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.tertiarySystemBackground)
                    .cornerRadius(8)
            }
            
            VStack(spacing: 16) {
                // Trend Description
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.appPrimary)
                        .font(.system(size: 16))
                    
                    Text(getTrendDescription())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                
                // Statistics Summary Cards
                if !filteredExpenses.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: isIPad ? 3 : 3), spacing: 12) {
                        trendStatCard(
                            title: "Total",
                            value: viewModel.formattedAmount(totalExpenses()),
                            icon: "creditcard.fill",
                            color: .appPrimary
                        )
                        
                        trendStatCard(
                            title: "Average",
                            value: viewModel.formattedAmount(averageExpense()),
                            icon: "chart.bar.fill",
                            color: .jordyBlue
                        )
                        
                        trendStatCard(
                            title: "Highest",
                            value: viewModel.formattedAmount(highestExpense()),
                            icon: "arrow.up.circle.fill",
                            color: .teaRose
                        )
                    }
                }
                
                // Chart Section
                VStack(spacing: 8) {
                    ExpenseTrendChart(
                        expenses: filteredExpenses,
                        timeFrame: selectedTimeFrame,
                        categoryColor: selectedCategory != nil ? 
                            Color.forCategory(selectedCategory!.color) : 
                            Color.appPrimary
                    )
                    .environmentObject(viewModel)
                    .frame(height: isIPad ? 300 : 200)
                    
                    // Simplified Chart Info - only show if there's meaningful comparison
                    if !filteredExpenses.isEmpty {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(selectedCategory != nil ? 
                                        Color.forCategory(selectedCategory!.color) : 
                                        Color.appPrimary)
                                    .frame(width: 6, height: 6)
                                
                                Text("Trend")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Only show comparison if there's a significant change
                            if let comparison = getTrendComparison(), comparison != "Stable" {
                                HStack(spacing: 4) {
                                    Image(systemName: comparison.hasPrefix("↑") ? "arrow.up" : "arrow.down")
                                        .font(.caption2)
                                        .foregroundColor(comparison.hasPrefix("↑") ? .red : .green)
                                    
                                    Text(comparison)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.tertiarySystemBackground)
                                .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(16)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
        }
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: animateCards)
    }
    
    // MARK: - Trend Stat Card
    private func trendStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.systemBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Helper Views
    private func timeFrameButton(_ timeFrame: ExpenseViewModel.TimeFrame) -> some View {
        Button(action: {
            HapticManager.shared.selectionChanged()
            withAnimation(.spring()) {
                selectedTimeFrame = timeFrame
            }
        }) {
            Text(timeFrame.rawValue)
                .font(.subheadline)
                .fontWeight(selectedTimeFrame == timeFrame ? .bold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(selectedTimeFrame == timeFrame ? Color.mauve : Color.tertiarySystemBackground)
                )
                .foregroundColor(selectedTimeFrame == timeFrame ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                    categoryFilterButton(for: category)
                }
                
                let customCategories = viewModel.getCustomCategories()
                ForEach(customCategories) { category in
                    customCategoryFilterButton(for: category)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func categoryFilterButton(for category: Expense.Category) -> some View {
        Button(action: {
            HapticManager.shared.selectionChanged()
            withAnimation(.spring()) {
                if selectedCategory == category {
                    selectedCategory = nil
                    viewModel.selectedCustomCategoryId = nil
                } else {
                    selectedCategory = category
                    viewModel.selectedCustomCategoryId = nil
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                
                Text(category.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selectedCategory == category ? Color.forCategory(category.color) : Color.tertiarySystemBackground)
            )
            .foregroundColor(selectedCategory == category ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func customCategoryFilterButton(for category: CustomCategory) -> some View {
        let isSelected = selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id
        
        return Button(action: {
            HapticManager.shared.selectionChanged()
            withAnimation(.spring()) {
                if isSelected {
                    selectedCategory = nil
                    viewModel.selectedCustomCategoryId = nil
                } else {
                    selectedCategory = .custom
                    viewModel.selectedCustomCategoryId = category.id
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                
                Text(category.name)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.forCategory(category.colorName) : Color.tertiarySystemBackground)
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func summaryCard(title: String, value: String, subtitle: String, icon: String, color: Color, comparison: String?) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text(value)
                        .font(isIPad ? .title2 : .title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: isIPad ? 50 : 40, height: isIPad ? 50 : 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: isIPad ? 22 : 18))
                        .foregroundColor(color)
                }
            }
            
            if let comparison = comparison {
                HStack {
                    Text(comparison)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func insightCard(_ insight: StatInsight) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(insight.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: insight.icon)
                    .font(.system(size: 18))
                    .foregroundColor(insight.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
    
    private func enhancedCategoryRow(_ categoryData: CategoryExpenseData) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(categoryData.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: categoryData.icon)
                        .font(.system(size: 18))
                        .foregroundColor(categoryData.color)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(categoryData.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text("\(categoryData.count) transaction\(categoryData.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text(viewModel.formattedAmount(categoryData.amount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if selectedCategory == nil && totalExpenses() > 0 {
                        Text("\(String(format: "%.1f", categoryData.percentage))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            if selectedCategory == nil && totalExpenses() > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.tertiarySystemBackground)
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(categoryData.color)
                            .frame(width: geometry.size.width * CGFloat(categoryData.percentage / 100), height: 8)
                            .animation(.easeOut(duration: 0.8), value: categoryData.percentage)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)
            
            Image(systemName: "chart.pie")
                .font(.system(size: 80))
                .foregroundColor(.appPrimary)
                .padding()
                .background(
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 150, height: 150)
                )
            
            Text("No Statistics Available")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Add some expenses to see your spending patterns and insights")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                HapticManager.shared.mediumTap()
                showingAddExpense = true
            }) {
                Text("Add Your First Expense")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 16)
            
            Spacer()
        }
        .padding()
        .frame(minHeight: 500)
    }
    
    // MARK: - Helper Functions
    private func totalExpenses() -> Double {
        return filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    private func totalExpenses(for category: Expense.Category) -> Double {
        return filteredExpenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
    }
    
    private func totalExpenses(for customCategory: CustomCategory) -> Double {
        return filteredExpenses.filter { 
            $0.category == .custom && $0.customCategoryId == customCategory.id 
        }.reduce(0) { $0 + $1.amount }
    }
    
    private func averageExpense() -> Double {
        let count = filteredExpenses.count
        return count > 0 ? totalExpenses() / Double(count) : 0
    }
    
    private func comparisonText() -> String? {
        let currentTotal = totalExpenses()
        let previousTotal = previousPeriodExpenses.reduce(0) { $0 + $1.amount }
        
        guard previousTotal > 0 else { return nil }
        
        let changePercent = ((currentTotal - previousTotal) / previousTotal) * 100
        let trend = changePercent > 0 ? "↑" : "↓"
        
        return "\(trend) \(String(format: "%.1f", abs(changePercent)))% vs. previous \(selectedTimeFrame.rawValue.lowercased())"
    }
    
    private func getCategoriesWithExpenses() -> [CategoryExpenseData] {
        var categoryData: [CategoryExpenseData] = []
        let total = totalExpenses()
        
        // Default categories
        for category in viewModel.getAvailableDefaultCategories() {
            let amount = totalExpenses(for: category)
            if amount > 0 {
                let count = filteredExpenses.filter { $0.category == category }.count
                categoryData.append(CategoryExpenseData(
                    name: category.rawValue,
                    amount: amount,
                    percentage: total > 0 ? (amount / total) * 100 : 0,
                    icon: category.icon,
                    color: Color.forCategory(category.color),
                    count: count
                ))
            }
        }
        
        // Custom categories
        for customCategory in viewModel.getCustomCategories() {
            let amount = totalExpenses(for: customCategory)
            if amount > 0 {
                let count = filteredExpenses.filter { $0.category == .custom && $0.customCategoryId == customCategory.id }.count
                categoryData.append(CategoryExpenseData(
                    name: customCategory.name,
                    amount: amount,
                    percentage: total > 0 ? (amount / total) * 100 : 0,
                    icon: customCategory.icon,
                    color: Color.forCategory(customCategory.colorName),
                    count: count
                ))
            }
        }
        
        return categoryData.sorted { $0.amount > $1.amount }
    }
    
    private func getTrendDescription() -> String {
        if filteredExpenses.isEmpty {
            return "No expenses recorded for this period."
        }
        
        if let category = selectedCategory {
            if category == .custom {
                let customCategories = viewModel.getCustomCategories()
                if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId,
                   let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                    return "Showing spending trend for \(customCategory.name) expenses."
                }
                return "Showing spending trend for Custom expenses."
            } else {
                return "Showing spending trend for \(category.rawValue) expenses."
            }
        } else {
            return "Showing overall spending trend for \(selectedTimeFrame.rawValue.lowercased())."
        }
    }
    
    private func getTrendComparison() -> String? {
        let currentTotal = totalExpenses()
        let previousTotal = previousPeriodExpenses.reduce(0) { $0 + $1.amount }
        
        guard previousTotal > 0 else { return nil }
        
        let changePercent = ((currentTotal - previousTotal) / previousTotal) * 100
        
        if abs(changePercent) < 5 {
            return "Stable"
        }
        
        let trend = changePercent > 0 ? "↑" : "↓"
        return "\(trend) \(String(format: "%.1f", abs(changePercent)))%"
    }
    
    private func highestExpense() -> Double {
        return filteredExpenses.max { $0.amount < $1.amount }?.amount ?? 0
    }
    
    private func getHeaderSubtitle() -> String {
        if viewModel.expenses.isEmpty {
            return "Add expenses to see insights"
        }
        
        let expenseCount = filteredExpenses.count
        let totalAmount = totalExpenses()
        
        if selectedCategory != nil {
            // When a category is selected
            if selectedCategory == .custom {
                let customCategories = viewModel.getCustomCategories()
                if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId,
                   let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                    return "\(expenseCount) \(customCategory.name.lowercased()) expense\(expenseCount == 1 ? "" : "s") • \(selectedTimeFrame.rawValue.lowercased())"
                }
                return "\(expenseCount) custom expense\(expenseCount == 1 ? "" : "s") • \(selectedTimeFrame.rawValue.lowercased())"
            } else {
                return "\(expenseCount) \(selectedCategory!.rawValue.lowercased()) expense\(expenseCount == 1 ? "" : "s") • \(selectedTimeFrame.rawValue.lowercased())"
            }
        } else {
            // When no category is selected
            return "\(expenseCount) expense\(expenseCount == 1 ? "" : "s") • \(viewModel.formattedAmount(totalAmount)) spent"
        }
    }
}

// MARK: - Data Structures
struct StatInsight: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
}

struct CategoryExpenseData {
    let name: String
    let amount: Double
    let percentage: Double
    let icon: String
    let color: Color
    let count: Int
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView()
            .environmentObject(ExpenseViewModel())
    }
} 