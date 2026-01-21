import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @State private var selectedTimeFrame: ExpenseViewModel.TimeFrame = .month
    @State private var rangeStartDate = Date()
    @State private var rangeEndDate = Date()
    @State private var showingAddExpense = false
    @State private var selectedCategory: Expense.Category? = nil
    @State private var selectedCustomCategoryId: UUID? = nil
    @State private var animateCards = false
    @State private var showingDateRangePicker = false
    
    // Performance: cache ONLY aggregated data (not full arrays) to minimize memory.
    @State private var cachedFilteredCount: Int = 0
    @State private var cachedInsights: [StatInsight] = []
    @State private var cachedTotalSpent: Double = 0
    @State private var cachedPreviousTotalSpent: Double = 0
    @State private var cachedMaxExpense: Double = 0
    @State private var cachedTotalsByCategory: [Expense.Category: Double] = [:]
    @State private var cachedCountsByCategory: [Expense.Category: Int] = [:]
    @State private var cachedTotalsByCustomId: [UUID: Double] = [:]
    @State private var cachedCountsByCustomId: [UUID: Int] = [:]
    // Pre-aggregated chart data to avoid passing full expense arrays to charts
    @State private var cachedTrendData: [(date: Date, amount: Double)] = []
    @State private var cachedHeatmapData: [Date: Double] = [:]
    @State private var statsRecomputeTask: Task<Void, Never>?
    @State private var didInitializeRange = false
    @State private var isRecomputingStats = false
    
    // Date range sheet uses temporary values to avoid recomputing while scrolling the picker.
    @State private var tempRangeStartDate = Date()
    @State private var tempRangeEndDate = Date()
    
    // Donut selection is highlight-only (keeps animation smooth without triggering full stats recompute).
    @State private var donutSelectedId: String? = nil
    
    // MARK: - Computed Properties
    
    /// Returns filtered expenses on-demand (NOT cached) to avoid memory duplication.
    /// Use cachedFilteredCount for count checks, and cachedTotalsByCategory for totals.
    private var filteredExpenses: [Expense] {
        ExpenseFilter.apply(
            expenses: viewModel.expenses,
            category: selectedCategory,
            customCategoryId: selectedCustomCategoryId,
            timeFrame: .all,
            dateRangeStart: rangeStartDate,
            dateRangeEnd: rangeEndDate
        )
    }
    
    private var insights: [StatInsight] {
        cachedInsights
    }
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    /// True when we have extra horizontal space (iPad or iPhone landscape)
    private var isWideLayout: Bool {
        isIPad || horizontalSizeClass == .regular
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
                .padding(.horizontal, isWideLayout ? 32 : 20)
                .padding(.bottom, 120)
                .frame(maxWidth: isWideLayout ? 1200 : .infinity) // Limit max width on very wide screens
                .frame(maxWidth: .infinity) // Center content
            }
            .background(Color.systemBackground)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                    animateCards = true
                }
                if !didInitializeRange {
                    didInitializeRange = true
                    applyPresetTimeFrame(selectedTimeFrame)
                }
                scheduleRecomputeStats(immediate: true)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Always use stack style to prevent split view
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
        }
        .onReceive(viewModel.$expenses) { _ in
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: selectedCategory) { _ in
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: selectedCustomCategoryId) { _ in
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: rangeStartDate) { _ in
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: rangeEndDate) { _ in
            scheduleRecomputeStats(immediate: false)
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
                        .font(isWideLayout ? .title3 : .headline)
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
            
            // Date Range (separate feature)
            dateRangeSection
            
            // Category Filter
            VStack(spacing: 12) {
                HStack {
                    Text("Filter by Category")
                        .font(isWideLayout ? .title3 : .headline)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if selectedCategory != nil {
                        Button("Clear") {
                            HapticManager.shared.selectionChanged()
                            withAnimation(.spring()) {
                                selectedCategory = nil
                                selectedCustomCategoryId = nil
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                    }
                }
                
                categorySelector
            }
        }
        .padding(isWideLayout ? 24 : 20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
    }
    
    private var dateRangeSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Date Range")
                    .font(isWideLayout ? .title3 : .headline)
                    .fontWeight(.bold)
                Spacer()
            }
            
            customRangeRow
        }
    }
    
    private var customRangeRow: some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        return HStack(spacing: 12) {
            Button {
                HapticManager.shared.lightTap()
                tempRangeStartDate = rangeStartDate
                tempRangeEndDate = rangeEndDate
                showingDateRangePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.appPrimary)
                    Text("\(formatter.string(from: rangeStartDate)) – \(formatter.string(from: rangeEndDate))")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.tertiarySystemBackground)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Button("Reset") {
                HapticManager.shared.lightTap()
                applyPresetTimeFrame(selectedTimeFrame)
            }
            .font(.subheadline)
            .foregroundColor(.appPrimary)
        }
        .sheet(isPresented: $showingDateRangePicker) {
            NavigationView {
                Form {
                    DatePicker("Start", selection: $tempRangeStartDate, displayedComponents: [.date])
                    DatePicker("End", selection: $tempRangeEndDate, displayedComponents: [.date])
                }
                .navigationTitle("Date Range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingDateRangePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if tempRangeEndDate < tempRangeStartDate {
                                // Auto-fix invalid range
                                let tmp = tempRangeStartDate
                                tempRangeStartDate = tempRangeEndDate
                                tempRangeEndDate = tmp
                            }
                            rangeStartDate = tempRangeStartDate
                            rangeEndDate = tempRangeEndDate
                            showingDateRangePicker = false
                        }
                    }
                }
            }
        }
    }

    
    private func dateRangeSubtitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: rangeStartDate)) – \(formatter.string(from: rangeEndDate))"
    }
    
    // MARK: - Performance: recompute cached stats
    
    private func scheduleRecomputeStats(immediate: Bool) {
        statsRecomputeTask?.cancel()
        if immediate {
            recomputeStatsNow()
            return
        }
        statsRecomputeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            recomputeStatsNow()
        }
    }
    
    private func recomputeStatsNow() {
        let expensesSnapshot = viewModel.expenses
        let start = rangeStartDate
        let end = rangeEndDate
        let selectedCat = selectedCategory
        let selectedCustomId = selectedCustomCategoryId
        let formattedAmount = viewModel.formattedAmount
        
        // Show loading for large datasets
        if expensesSnapshot.count > 500 {
            isRecomputingStats = true
        }
        
        Task.detached(priority: .userInitiated) {
            let currentFiltered = ExpenseFilter.apply(
                expenses: expensesSnapshot,
                category: selectedCat,
                customCategoryId: selectedCustomId,
                timeFrame: .all,
                dateRangeStart: start,
                dateRangeEnd: end
            )
            
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: start)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            let length = endExclusive.timeIntervalSince(startDay)
            let previousEnd = startDay
            let previousStart = previousEnd.addingTimeInterval(-length)
            let prevFiltered = expensesSnapshot.filter { $0.date >= previousStart && $0.date < previousEnd }
            
            var total: Double = 0
            var maxExpense: Double = 0
            var totalsByCategory: [Expense.Category: Double] = [:]
            var countsByCategory: [Expense.Category: Int] = [:]
            var totalsByCustom: [UUID: Double] = [:]
            var countsByCustom: [UUID: Int] = [:]
            
            // Pre-aggregate heatmap data (totals by day) - limited to 365 days
            var heatmapData: [Date: Double] = [:]
            
            for e in currentFiltered {
                total += e.amount
                if e.amount > maxExpense { maxExpense = e.amount }
                
                countsByCategory[e.category, default: 0] += 1
                totalsByCategory[e.category, default: 0] += e.amount
                
                if e.category == .custom, let id = e.customCategoryId {
                    countsByCustom[id, default: 0] += 1
                    totalsByCustom[id, default: 0] += e.amount
                }
                
                // Aggregate for heatmap
                let dayKey = calendar.startOfDay(for: e.date)
                heatmapData[dayKey, default: 0] += e.amount
            }
            
            let previousTotal = prevFiltered.reduce(0) { $0 + $1.amount }
            
            let dayCount = calendar.dateComponents([.day], from: startDay, to: endExclusive).day ?? 0
            let includeHighDay = dayCount > 0 && dayCount <= 31
            let computedInsights = StatisticsCalculator.insights(
                filteredExpenses: currentFiltered,
                previousPeriodExpenses: prevFiltered,
                periodLabel: "period",
                includeHighSpendingDay: includeHighDay,
                formattedAmount: formattedAmount
            )
            
            // Pre-aggregate trend data (by month for memory efficiency)
            var trendData: [(date: Date, amount: Double)] = []
            var monthlyTotals: [Date: Double] = [:]
            for e in currentFiltered {
                if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: e.date)) {
                    monthlyTotals[monthStart, default: 0] += e.amount
                }
            }
            trendData = monthlyTotals.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
            
            let filteredCount = currentFiltered.count
            
            await MainActor.run {
                self.cachedFilteredCount = filteredCount
                self.cachedInsights = computedInsights
                self.cachedTotalSpent = total
                self.cachedPreviousTotalSpent = previousTotal
                self.cachedMaxExpense = maxExpense
                self.cachedTotalsByCategory = totalsByCategory
                self.cachedCountsByCategory = countsByCategory
                self.cachedTotalsByCustomId = totalsByCustom
                self.cachedCountsByCustomId = countsByCustom
                self.cachedTrendData = trendData
                self.cachedHeatmapData = heatmapData
                self.isRecomputingStats = false
            }
        }
    }
    
    private func applyPresetTimeFrame(_ timeFrame: ExpenseViewModel.TimeFrame) {
        let calendar = Calendar.current
        let now = Date()
        let range = timeFrame.dateRange(referenceDate: now)
        rangeStartDate = range.start
        rangeEndDate = calendar.date(byAdding: .day, value: -1, to: range.end) ?? now
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
            
            // Category Share (donut)
            if cachedFilteredCount > 0 {
                categoryShareSection
            }
            
            // Heatmap
            if cachedFilteredCount > 0 {
                spendingHeatmapSection
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
                    .font(isWideLayout ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            if isWideLayout {
                // Wide layout: all cards in a row
                HStack(spacing: 16) {
                    summaryCard(
                        title: "Total Spent",
                        value: viewModel.formattedAmount(totalExpenses()),
                        subtitle: dateRangeSubtitle(),
                        icon: "creditcard.fill",
                        color: .appPrimary,
                        comparison: comparisonText()
                    )
                    
                    summaryCard(
                        title: "Transactions",
                        value: "\(cachedFilteredCount)",
                        subtitle: dateRangeSubtitle(),
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
                // Compact layout: stacked cards
                VStack(spacing: 12) {
                    summaryCard(
                        title: "Total Spent",
                        value: viewModel.formattedAmount(totalExpenses()),
                        subtitle: dateRangeSubtitle(),
                        icon: "creditcard.fill",
                        color: .appPrimary,
                        comparison: comparisonText()
                    )
                    
                    HStack(spacing: 12) {
                        summaryCard(
                            title: "Transactions",
                            value: "\(cachedFilteredCount)",
                            subtitle: dateRangeSubtitle(),
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
                    .font(isWideLayout ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: isWideLayout ? 2 : 1), spacing: 12) {
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
                    .font(isWideLayout ? .title2 : .title3)
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
                        let customCategories = categoryViewModel.customCategories
                        if let selectedCustomCategoryId = selectedCustomCategoryId,
                           let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                            let amount = totalExpenses(for: customCategory)
                            let categoryData = CategoryExpenseData(
                                name: customCategory.name,
                                amount: amount,
                                percentage: 100.0,
                                icon: customCategory.icon,
                                color: Color.forCategory(customCategory.colorName),
                                count: cachedCountsByCustomId[customCategory.id, default: 0]
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
                            count: cachedCountsByCategory[selectedCategory!, default: 0]
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

    // MARK: - Category Share (Donut) Section
    private var categoryShareSection: some View {
        let slices = categorySlices()
        let total = slices.reduce(0) { $0 + $1.amount }
        
        return VStack(spacing: 16) {
            HStack {
                Text("Category Share")
                    .font(isWideLayout ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
                
                if selectedCategory == nil {
                    Text("\(slices.filter { $0.amount > 0 }.count) categories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.tertiarySystemBackground)
                        .cornerRadius(8)
                }
            }
            
            CategoryDonutChart(
                slices: slices,
                total: total,
                selectedId: donutSelectedId,
                onSelect: { slice in
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                        donutSelectedId = slice?.id
                    }
                }
            )
        }
        .padding(16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .onChange(of: selectedCategory) { _ in donutSelectedId = nil }
        .onChange(of: selectedCustomCategoryId) { _ in donutSelectedId = nil }
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.28), value: animateCards)
    }
    
    private func categorySlices() -> [CategoryDonutChart.Slice] {
        let total = cachedTotalSpent
        guard total > 0 else { return [] }
        
        var result: [CategoryDonutChart.Slice] = []
        
        // Default categories
        for category in viewModel.getAvailableDefaultCategories().filter({ $0 != .custom }) {
            let amount = cachedTotalsByCategory[category, default: 0]
            if amount > 0 {
                result.append(
                    CategoryDonutChart.Slice(
                        id: "default:\(category.rawValue)",
                        title: category.displayName,
                        amount: amount,
                        color: Color.forCategory(category.color),
                        icon: category.icon,
                        category: category,
                        customCategoryId: nil
                    )
                )
            }
        }
        
        // Custom categories
        for custom in categoryViewModel.customCategories {
            let amount = cachedTotalsByCustomId[custom.id, default: 0]
            if amount > 0 {
                result.append(
                    CategoryDonutChart.Slice(
                        id: "custom:\(custom.id.uuidString)",
                        title: custom.name,
                        amount: amount,
                        color: Color.forCategory(custom.colorName),
                        icon: custom.icon,
                        category: .custom,
                        customCategoryId: custom.id
                    )
                )
            }
        }
        
        // If a category filter is active, the donut would be a single slice; still ok.
        // Sort biggest-first for stable legend.
        return result.sorted { $0.amount > $1.amount }
    }

    // MARK: - Spending Heatmap Section
    private var spendingHeatmapSection: some View {
        let accent: Color = {
            if let selectedCategory, selectedCategory != .custom {
                return Color.forCategory(selectedCategory.color)
            }
            if selectedCategory == .custom, let id = selectedCustomCategoryId,
               let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
                return Color.forCategory(custom.colorName)
            }
            return .appPrimary
        }()
        
        return VStack(spacing: 16) {
            HStack {
                Text("Spending Heatmap")
                    .font(isWideLayout ? .title2 : .title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            SpendingHeatmap(
                expenses: filteredExpenses,
                startDate: rangeStartDate,
                endDate: rangeEndDate,
                accentColor: accent,
                formattedAmount: viewModel.formattedAmount
            )
        }
        .padding(16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.32), value: animateCards)
    }
    
    // MARK: - Expense Trend Section
    private var expenseTrendSection: some View {
        let accent = selectedCategory != nil ? Color.forCategory(selectedCategory!.color) : Color.appPrimary
        
        return VStack(spacing: 14) {
            HStack {
                Text("Spending Trend")
                    .font(isWideLayout ? .title2 : .title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(selectedTimeFrame.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.tertiarySystemBackground)
                    .cornerRadius(10)
            }
            
            // Description (smaller + cleaner)
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(accent)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(getTrendDescription())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            
            // Stats row (avoid 3 tiny columns on iPhone)
            if cachedFilteredCount > 0 {
                if isIPad {
                    HStack(spacing: 12) {
                        trendStatCard(title: "Total", value: viewModel.formattedAmount(totalExpenses()), icon: "creditcard.fill", color: accent)
                        trendStatCard(title: "Average", value: viewModel.formattedAmount(averageExpense()), icon: "chart.bar.fill", color: .jordyBlue)
                        trendStatCard(title: "Highest", value: viewModel.formattedAmount(highestExpense()), icon: "arrow.up.circle.fill", color: .teaRose)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            trendStatCard(title: "Total", value: viewModel.formattedAmount(totalExpenses()), icon: "creditcard.fill", color: accent)
                                .frame(width: 140)
                            trendStatCard(title: "Average", value: viewModel.formattedAmount(averageExpense()), icon: "chart.bar.fill", color: .jordyBlue)
                                .frame(width: 140)
                            trendStatCard(title: "Highest", value: viewModel.formattedAmount(highestExpense()), icon: "arrow.up.circle.fill", color: .teaRose)
                                .frame(width: 140)
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            
            // Chart
            ExpenseTrendChart(
                expenses: filteredExpenses,
                timeFrame: selectedTimeFrame,
                categoryColor: accent
            )
            .environmentObject(viewModel)
            
            // Footer legend + comparison (de-cluttered)
            if cachedFilteredCount > 0 {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                    Text("Trend")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let comparison = getTrendComparison(), comparison != "Stable" {
                        Text(comparison)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.tertiarySystemBackground)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .scaleEffect(animateCards ? 1.0 : 0.95)
        .opacity(animateCards ? 1.0 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: animateCards)
        .padding(16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Trend Stat Card
    private func trendStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 34, height: 34)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.systemBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Helper Views
    private func timeFrameButton(_ timeFrame: ExpenseViewModel.TimeFrame) -> some View {
        Button(action: {
            HapticManager.shared.selectionChanged()
            // Fast UI animation, data computation happens in background
            withAnimation(.easeOut(duration: 0.15)) {
                selectedTimeFrame = timeFrame
                applyPresetTimeFrame(timeFrame)
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
                
                let customCategories = categoryViewModel.customCategories
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
            // Fast animation for UI, data filtering is debounced in background
            withAnimation(.easeOut(duration: 0.15)) {
                if selectedCategory == category {
                    selectedCategory = nil
                    selectedCustomCategoryId = nil
                } else {
                    selectedCategory = category
                    selectedCustomCategoryId = nil
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
        let isSelected = selectedCategory == .custom && selectedCustomCategoryId == category.id
        
        return Button(action: {
            HapticManager.shared.selectionChanged()
            // Fast animation for UI, data filtering is debounced in background
            withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                    selectedCategory = nil
                    selectedCustomCategoryId = nil
                } else {
                    selectedCategory = .custom
                    selectedCustomCategoryId = category.id
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
                        .font(isWideLayout ? .title2 : .title3)
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
                        .frame(width: isWideLayout ? 50 : 40, height: isWideLayout ? 50 : 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: isWideLayout ? 22 : 18))
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
        return cachedTotalSpent
    }
    
    private func totalExpenses(for category: Expense.Category) -> Double {
        return cachedTotalsByCategory[category, default: 0]
    }
    
    private func totalExpenses(for customCategory: CustomCategory) -> Double {
        return cachedTotalsByCustomId[customCategory.id, default: 0]
    }
    
    private func averageExpense() -> Double {
        let count = cachedFilteredCount
        return count > 0 ? totalExpenses() / Double(count) : 0
    }
    
    private func comparisonText() -> String? {
        let currentTotal = cachedTotalSpent
        let previousTotal = cachedPreviousTotalSpent
        
        guard previousTotal > 0 else { return nil }
        
        let changePercent = ((currentTotal - previousTotal) / previousTotal) * 100
        let trend = changePercent > 0 ? "↑" : "↓"
        
        return "\(trend) \(String(format: "%.1f", abs(changePercent)))% vs. previous period"
    }
    
    private func getCategoriesWithExpenses() -> [CategoryExpenseData] {
        // Use cached totals instead of recomputing from expenses (memory efficient)
        var categoryData: [CategoryExpenseData] = []
        let total = cachedTotalSpent
        
        for category in viewModel.getAvailableDefaultCategories() {
            let amount = cachedTotalsByCategory[category, default: 0]
            if amount > 0 {
                let count = cachedCountsByCategory[category, default: 0]
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
        
        for customCategory in categoryViewModel.customCategories {
            let amount = cachedTotalsByCustomId[customCategory.id, default: 0]
            if amount > 0 {
                let count = cachedCountsByCustomId[customCategory.id, default: 0]
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
    
    private func getTrendDescription() -> String {
        if cachedFilteredCount == 0 {
            return "No expenses recorded for this period."
        }
        
        if let category = selectedCategory {
            if category == .custom {
                let customCategories = categoryViewModel.customCategories
                if let selectedCustomCategoryId = selectedCustomCategoryId,
                   let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                    return "Showing spending trend for \(customCategory.name) expenses."
                }
                return "Showing spending trend for Custom expenses."
            } else {
                return "Showing spending trend for \(category.rawValue) expenses."
            }
        } else {
            return "Showing overall spending trend for selected date range."
        }
    }
    
    private func getTrendComparison() -> String? {
        let currentTotal = cachedTotalSpent
        let previousTotal = cachedPreviousTotalSpent
        
        guard previousTotal > 0 else { return nil }
        
        let changePercent = ((currentTotal - previousTotal) / previousTotal) * 100
        
        if abs(changePercent) < 5 {
            return "Stable"
        }
        
        let trend = changePercent > 0 ? "↑" : "↓"
        
        // Avoid absurd-looking numbers when previous period is tiny.
        let capped = min(abs(changePercent), 999)
        if abs(changePercent) > 999 {
            return "\(trend) \(String(format: "%.0f", capped))%+"
        }
        
        return "\(trend) \(String(format: "%.1f", capped))%"
    }
    
    private func highestExpense() -> Double {
        return cachedMaxExpense
    }
    
    private func getHeaderSubtitle() -> String {
        if viewModel.expenses.isEmpty {
            return "Add expenses to see insights"
        }
        
        let expenseCount = cachedFilteredCount
        let totalAmount = totalExpenses()
        let rangeFormatter = DateFormatter()
        rangeFormatter.dateStyle = .medium
        let rangeLabel = "\(rangeFormatter.string(from: rangeStartDate)) – \(rangeFormatter.string(from: rangeEndDate))"
        
        if selectedCategory != nil {
            // When a category is selected
            if selectedCategory == .custom {
                let customCategories = categoryViewModel.customCategories
                if let selectedCustomCategoryId = selectedCustomCategoryId,
                   let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                    return "\(expenseCount) \(customCategory.name.lowercased()) expense\(expenseCount == 1 ? "" : "s") • \(rangeLabel)"
                }
                return "\(expenseCount) custom expense\(expenseCount == 1 ? "" : "s") • \(rangeLabel)"
            } else {
                return "\(expenseCount) \(selectedCategory!.rawValue.lowercased()) expense\(expenseCount == 1 ? "" : "s") • \(rangeLabel)"
            }
        } else {
            // When no category is selected
            return "\(expenseCount) expense\(expenseCount == 1 ? "" : "s") • \(rangeLabel) • \(viewModel.formattedAmount(totalAmount))"
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
            .environmentObject(CategoryViewModel())
    }
} 