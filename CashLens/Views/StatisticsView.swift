import SwiftUI
import CoreData

struct StatisticsView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager
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

    /// PERF: TabView keeps Statistics permanently mounted, so this view
    /// was reacting to **every** `viewModel.$expenses` publish even
    /// when the user was on Home or Subscriptions — racing detached
    /// recomputes that the user would never actually see. We now track
    /// whether the Statistics tab is currently the visible one and
    /// defer recomputes to the next `onAppear` when it isn't.
    @State private var isStatsTabVisible = false
    @State private var statsRecomputePending = false
    @State private var didFirstStatsRecompute = false
    @State private var isRecomputingStats = false
    
    // Pro-tier cached aggregates (daily pace, velocity projection, YoY chart data).
    @State private var cachedDailyPace = AdvancedStatsCalculator.DailyPace(
        dailyAverage: 0, previousDailyAverage: 0, changePercent: nil, daysElapsed: 1
    )
    @State private var cachedVelocity = AdvancedStatsCalculator.Velocity(
        state: .projecting, currentTotal: 0, projectedTotal: 0,
        previousTotal: 0, changePercent: nil, progress: 0
    )
    @State private var cachedYoYPoints: [AdvancedStatsCalculator.YearOverYearPoint] = []
    @State private var cachedTopExpenses: [Expense] = []

    // Forecast (Pro): horizon-controlled future spend projection.
    // `cachedForecast` is computed on the same detached background task as the
    // rest of the stats so the main thread stays jitter-free. `forecastHorizon`
    // is part of the recompute key — switching it triggers a fresh pass.
    @State private var cachedForecast: ForecastEngine.Forecast = .empty
    @State private var forecastHorizon: ForecastSection.Horizon = .thirty

    // Swipeable Trend pager data — computed once per recompute pass on the background task.
    @State private var cachedWeekdayAverages: [WeekdayAveragePoint] = []
    @State private var cachedTopDays: [TopDayPoint] = []
    /// Pre-bucketed line-chart series keyed to the currently selected
    /// `selectedTimeFrame`. The audit caught `ExpenseTrendChart` rebuilding
    /// these in its `body` on every redraw; we now build them once on the
    /// background recompute task and hand them in as immutable arrays.
    @State private var cachedTrendChartDates: [Date] = []
    @State private var cachedTrendChartValues: [Double] = []

    // Payment Methods (Pro). Same recompute pass as the rest of the stats so the
    // donut never lags behind a filter change. Selection is highlight-only — the
    // donut and breakdown rows talk to each other through `paymentDonutSelectedId`.
    @State private var cachedPaymentMethodBreakdown: PaymentMethodBreakdown = PaymentMethodBreakdown(
        slices: [], unspecifiedAmount: 0, unspecifiedCount: 0, total: 0
    )
    @State private var paymentDonutSelectedId: String? = nil
    
    // PDF export state
    @State private var showingPaywall = false
    @State private var showingShareSheet = false
    @State private var exportedPDFURL: URL? = nil
    @State private var isExportingPDF = false
    @State private var exportErrorMessage: String? = nil
    
    // Date range sheet uses temporary values to avoid recomputing while scrolling the picker.
    @State private var tempRangeStartDate = Date()
    @State private var tempRangeEndDate = Date()
    
    // Donut selection is highlight-only (keeps animation smooth without triggering full stats recompute).
    @State private var donutSelectedId: String? = nil
    
    // MARK: - Computed Properties

    // Note: A `filteredExpenses` computed property used to live here. It ran
    // `ExpenseFilter.apply` + a sort on the main thread on every body
    // redraw and was the P0 hot path the audit flagged. Removed in the
    // perf pass — `SpendingHeatmap` now reads `cachedHeatmapData` and
    // `TrendChartPager` reads pre-built `cachedTrendChartDates / Values`.
    // Both are populated off-main once per recompute pass.

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
                VStack(spacing: Theme.Spacing.xxl) {
                    headerSection
                    controlSection

                    if viewModel.expenses.isEmpty {
                        emptyStateView
                    } else {
                        statisticsContent
                    }
                }
                .padding(.horizontal, isWideLayout ? Theme.Spacing.xxxl : Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.tabBarInset)
                .frame(maxWidth: isWideLayout ? 1200 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .background(Color.systemBackground)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isStatsTabVisible = true
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                    animateCards = true
                }
                // v2 IA fix: Insights inherits Today's filter state on
                // appear so the two tabs never give different answers
                // to the same question. The IA audit flagged "split-
                // brain timeframe" as the biggest trust-erosion bug:
                // a user tapped a pinned category on Home, switched to
                // Stats expecting it filtered, and got the full month
                // instead. Insights retains its custom-date-range
                // override (date range is an Insights-only concept)
                // but the preset timeframe and category selection
                // mirror Today on every visit.
                let inheritedTimeFrame = viewModel.selectedTimeFrame
                let inheritedCategory = viewModel.selectedCategory
                let inheritedCustomId = viewModel.selectedCustomCategoryId
                if selectedTimeFrame != inheritedTimeFrame {
                    selectedTimeFrame = inheritedTimeFrame
                }
                if selectedCategory != inheritedCategory {
                    selectedCategory = inheritedCategory
                }
                if selectedCustomCategoryId != inheritedCustomId {
                    selectedCustomCategoryId = inheritedCustomId
                }
                if !didInitializeRange {
                    didInitializeRange = true
                    applyPresetTimeFrame(selectedTimeFrame)
                }
                // PERF: Only run the immediate recompute on the very
                // first visit, or when a `$expenses` publish arrived
                // while the tab was hidden. Otherwise switching back
                // to Statistics from Home would always pay for a full
                // immediate recompute even if nothing changed.
                if !didFirstStatsRecompute || statsRecomputePending {
                    didFirstStatsRecompute = true
                    statsRecomputePending = false
                    scheduleRecomputeStats(immediate: true)
                }
            }
            .onDisappear {
                isStatsTabVisible = false
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Always use stack style to prevent split view
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedPDFURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .onReceive(viewModel.$expenses) { _ in
            // PERF: Skip the recompute entirely while the tab is
            // hidden; just flag a pending recompute so the next
            // `onAppear` picks it up. This stops Statistics from
            // racing detached recomputes on every save while the user
            // is somewhere else in the app — invisible work that
            // contended for the main actor without showing anything.
            if isStatsTabVisible {
                scheduleRecomputeStats(immediate: false)
            } else {
                statsRecomputePending = true
            }
        }
        .onChange(of: selectedCategory) {
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: selectedCustomCategoryId) {
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: rangeStartDate) {
            scheduleRecomputeStats(immediate: false)
        }
        .onChange(of: rangeEndDate) {
            scheduleRecomputeStats(immediate: false)
        }
        // Currency switch must trigger an **immediate** recompute. Most live
        // money displays update via @Published, but `cachedInsights` bakes
        // the formatted string in at compute time, so it would otherwise
        // keep the old currency symbol on the Highlights cards until the
        // next data change.
        .onChange(of: viewModel.selectedCurrency) {
            scheduleRecomputeStats(immediate: true)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: Theme.Spacing.xl)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Statistics")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(.primary)

                    Text(getHeaderSubtitle())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                exportReportButton
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    /// Pro-gated "Export PDF Report" icon button. Free users tap → paywall; Pro users
    /// tap → PDF is generated off-main and a share sheet opens automatically.
    private var exportReportButton: some View {
        Button {
            HapticManager.shared.lightTap()
            if proManager.isPro {
                exportPDFReport()
            } else {
                showingPaywall = true
            }
        } label: {
            ZStack {
                // Elevated white disc — mirrors the new card surface
                // system so the icon button reads as a tiny floating
                // chip rather than a flat grey circle.
                Color.clear
                    .frame(width: 40, height: 40)
                    .modifier(ElevatedCircleSurface())

                if isExportingPDF {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                if !proManager.isPro {
                    // Tiny PRO badge at the corner for free users.
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(
                            Circle().fill(Color.appPrimary)
                        )
                        .offset(x: 14, y: -14)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isExportingPDF || viewModel.expenses.isEmpty)
        .opacity(viewModel.expenses.isEmpty ? 0.4 : 1.0)
        .accessibilityLabel("Export PDF report")
    }
    
    // MARK: - Control Section
    //
    // A single card that combines time frame, date range, and category filter in
    // three tight rows with no verbose subheaders. Each row is self-describing
    // (icon + context) so the card stays glanceable.
    private var controlSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            timeFrameRow
            dateRangeRow

            if hasAnyCategoriesToFilter {
                Divider().opacity(0.4)
                categoryFilterRow
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, isWideLayout ? Theme.Spacing.xl : Theme.Spacing.md)
        .cardSurface()
    }

    private var hasAnyCategoriesToFilter: Bool {
        !viewModel.getAvailableDefaultCategories().isEmpty || !categoryViewModel.customCategories.isEmpty
    }

    private var timeFrameRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                    PillChip(
                        title: timeFrame.rawValue,
                        isSelected: selectedTimeFrame == timeFrame
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(Theme.Motion.snappy) {
                            selectedTimeFrame = timeFrame
                            applyPresetTimeFrame(timeFrame)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    /// Apple-Fitness-style period navigation: back chevron + center label + forward chevron.
    /// Tapping the center label opens the custom date-range picker; tapping a chevron
    /// shifts the current range by one unit of `selectedTimeFrame`. Forward is disabled
    /// when we're already at the current period (prevents navigating into the future).
    /// `.all` hides chevrons entirely and shows a static "All time" label.
    private var dateRangeRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if selectedTimeFrame != .all {
                periodChevronButton(direction: -1, enabled: canGoBackPeriod)
            }

            Button {
                HapticManager.shared.lightTap()
                tempRangeStartDate = rangeStartDate
                tempRangeEndDate = rangeEndDate
                showingDateRangePicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appPrimary)
                    Text(currentPeriodLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.identity)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(Color.tertiarySystemBackground)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            if selectedTimeFrame != .all {
                periodChevronButton(direction: 1, enabled: canGoForwardPeriod)
            }

            if rangeWasModifiedFromPreset {
                Button {
                    HapticManager.shared.lightTap()
                    withAnimation(Theme.Motion.snappy) {
                        applyPresetTimeFrame(selectedTimeFrame)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.appPrimary.opacity(0.12)))
                }
                .buttonStyle(ScaleButtonStyle())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Reset to current period")
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .animation(Theme.Motion.snappy, value: rangeWasModifiedFromPreset)
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

    /// Circular chevron button used for period navigation. `direction` is -1 (back) or +1 (forward).
    /// Disabled state dims the icon and blocks taps so forward-into-future is impossible.
    private func periodChevronButton(direction: Int, enabled: Bool) -> some View {
        let icon = direction < 0 ? "chevron.left" : "chevron.right"
        let label = direction < 0 ? "Previous period" : "Next period"

        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                shiftPeriod(by: direction)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(enabled ? .appPrimary : .secondary.opacity(0.4))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(enabled ? Color.appPrimary.opacity(0.12) : Color.tertiarySystemBackground)
                )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var canGoBackPeriod: Bool { selectedTimeFrame != .all }

    /// Forward navigation is disabled once the visible range already reaches (or passes) today —
    /// we don't allow navigating into the future because there's no data there.
    private var canGoForwardPeriod: Bool {
        guard selectedTimeFrame != .all else { return false }
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return rangeEndDate < endOfToday
    }

    /// Smart, human-friendly label for the current visible range. Falls back to a
    /// formatted date range when the current window doesn't match a named shortcut.
    ///
    /// All formatters used below are hoisted to file-level statics so this
    /// helper, which runs on every Statistics body redraw, doesn't allocate
    /// fresh `DateFormatter` instances per call. The audit flagged the prior
    /// per-call allocations as a P1 hot path.
    private var currentPeriodLabel: String {
        let calendar = Calendar.current
        let now = Date()

        switch selectedTimeFrame {
        case .all:
            return "All time"

        case .day:
            if calendar.isDateInToday(rangeStartDate) { return "Today" }
            if calendar.isDateInYesterday(rangeStartDate) { return "Yesterday" }
            return Self.formatterMediumDate.string(from: rangeStartDate)

        case .week:
            let thisWeekRange = ExpenseViewModel.TimeFrame.week.dateRange(referenceDate: now)
            let thisWeekStart = calendar.startOfDay(for: thisWeekRange.start)
            let rangeStart = calendar.startOfDay(for: rangeStartDate)
            if rangeStart == thisWeekStart { return "This week" }
            if let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart),
               rangeStart == lastWeekStart { return "Last week" }
            return "\(Self.formatterDayMonth.string(from: rangeStartDate)) – \(Self.formatterDayMonth.string(from: rangeEndDate))"

        case .month:
            let rangeYear = calendar.component(.year, from: rangeStartDate)
            let currentYear = calendar.component(.year, from: now)
            let formatter = rangeYear == currentYear
                ? Self.formatterMonthOnly
                : Self.formatterMonthYear
            return formatter.string(from: rangeStartDate)

        case .year:
            return Self.formatterYearOnly.string(from: rangeStartDate)
        }
    }

    // MARK: - Hoisted DateFormatters
    //
    // Every formatter touched by `currentPeriodLabel`, `dateRangeSubtitle`,
    // and `getHeaderSubtitle` lives here so we don't pay an `init`
    // allocation for each one on every body redraw. All only ever read on
    // the main actor (UI body), so a lazy static is safe.
    private static let formatterMediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
    private static let formatterDayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private static let formatterMonthOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()
    private static let formatterMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private static let formatterYearOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    /// Shifts the current range by one unit of the selected time-frame in the given direction.
    /// `direction` of +1 moves forward (later) and -1 moves backward (earlier). Safe for `.all`.
    private func shiftPeriod(by direction: Int) {
        guard selectedTimeFrame != .all else { return }
        let calendar = Calendar.current

        let component: Calendar.Component
        let value: Int
        switch selectedTimeFrame {
        case .day:   component = .day;   value = direction
        case .week:  component = .day;   value = direction * 7
        case .month: component = .month; value = direction
        case .year:  component = .year;  value = direction
        case .all:   return
        }

        guard let newStart = calendar.date(byAdding: component, value: value, to: rangeStartDate),
              let newEnd = calendar.date(byAdding: component, value: value, to: rangeEndDate) else { return }

        rangeStartDate = newStart
        rangeEndDate = newEnd
    }

    /// True when the current date range differs from the preset derived from `selectedTimeFrame`.
    /// Used to show a contextual "Reset" pill only when there's actually something to reset.
    private var rangeWasModifiedFromPreset: Bool {
        let calendar = Calendar.current
        let range = selectedTimeFrame.dateRange(referenceDate: Date())
        let presetStart = calendar.startOfDay(for: range.start)
        let presetEnd = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end)
        return calendar.startOfDay(for: rangeStartDate) != presetStart
            || calendar.startOfDay(for: rangeEndDate) != presetEnd
    }

    private var categoryFilterRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            categorySelector

            if selectedCategory != nil {
                Button {
                    HapticManager.shared.selectionChanged()
                    withAnimation(Theme.Motion.snappy) {
                        selectedCategory = nil
                        selectedCustomCategoryId = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    
    private func dateRangeSubtitle() -> String {
        return "\(Self.formatterMediumDate.string(from: rangeStartDate)) – \(Self.formatterMediumDate.string(from: rangeEndDate))"
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
        let forecastHorizonDays = forecastHorizon.rawValue
        // Captured for `ExpenseTrendChart.buildChartData` so the line-chart
        // series is built off-main, in the same pass as the rest of the
        // stats, instead of recomputing in the chart view body.
        let trendTimeFrame = selectedTimeFrame
        let referenceNow = Date()
        
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
                // Refund-aware: aggregations sum signed amounts, but the
                // single-row "biggest expense" check still uses the raw
                // amount because the user thinks of "biggest" as biggest
                // movement, not biggest net.
                let signed = e.signedAmount
                total += signed
                if e.amount > maxExpense { maxExpense = e.amount }
                
                countsByCategory[e.category, default: 0] += 1
                totalsByCategory[e.category, default: 0] += signed
                
                if e.category == .custom, let id = e.customCategoryId {
                    countsByCustom[id, default: 0] += 1
                    totalsByCustom[id, default: 0] += signed
                }
                
                // Aggregate for heatmap
                let dayKey = calendar.startOfDay(for: e.date)
                heatmapData[dayKey, default: 0] += signed
            }
            // Floor any net-negative day at 0 — the heatmap colour ramp can't
            // represent negative net spending and would otherwise render as
            // the lightest tier alongside true no-spend days.
            for (k, v) in heatmapData where v < 0 {
                heatmapData[k] = 0
            }
            
            let previousTotal = prevFiltered.netTotal()
            
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
                    monthlyTotals[monthStart, default: 0] += e.signedAmount
                }
            }
            trendData = monthlyTotals.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
            
            let filteredCount = currentFiltered.count

            // Advanced Pro stats (cheap — all derived from already-aggregated totals).
            let dailyPace = AdvancedStatsCalculator.dailyPace(
                currentTotal: total,
                previousTotal: previousTotal,
                rangeStart: start,
                rangeEnd: end
            )
            let velocity = AdvancedStatsCalculator.velocity(
                currentTotal: total,
                previousTotal: previousTotal,
                rangeStart: start,
                rangeEnd: end
            )
            // Year-over-year looks at the *full* expense set (ignores date filter on purpose —
            // YoY is meaningful across years, independent of the in-view range).
            let yoyPoints = AdvancedStatsCalculator.yearOverYear(
                allExpenses: expensesSnapshot,
                count: 6
            )
            // Top 40 expenses (by amount) scoped to the current filter — powers the PDF report.
            let topExpenses = Array(currentFiltered.sorted { $0.amount > $1.amount }.prefix(40))

            // Forecast (Pro). Reads active subscriptions directly from a
            // background Core Data context so we don't need to inject a
            // SubscriptionViewModel into the Statistics screen. Uses the FULL
            // expense set (not the date-filtered slice) — the forecast is
            // about your overall trajectory, not the period currently in view.
            let activeSubscriptions: [Subscription] = {
                let context = PersistenceController.shared.container.newBackgroundContext()
                var subs: [Subscription] = []
                context.performAndWait {
                    let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                    request.predicate = NSPredicate(format: "isActive == YES")
                    if let entities = try? context.fetch(request) {
                        subs = entities.toSubscriptions()
                    }
                }
                return subs
            }()
            let forecast = ForecastEngine.compute(
                history: expensesSnapshot,
                upcomingSubscriptions: activeSubscriptions,
                horizonDays: forecastHorizonDays
            )

            // Swipeable Trend aggregates (cheap, O(n) each — safe on the background task).
            let weekdayAverages = StatisticsCalculator.weekdayAverages(
                filteredExpenses: currentFiltered,
                rangeStart: startDay,
                rangeEnd: end
            )
            let topDays = StatisticsCalculator.topSpendingDays(
                filteredExpenses: currentFiltered,
                limit: 5
            )

            // Payment-method donut (Pro). Single O(n) pass; we lean on the
            // calculator helper rather than rolling another loop here so the
            // logic stays testable and refund-aware in one place.
            let paymentBreakdown = StatisticsCalculator.paymentMethodBreakdown(
                filteredExpenses: currentFiltered
            )

            // Pre-bucket the line-chart series for the currently selected
            // time frame. Old behaviour: `ExpenseTrendChart` did this inside
            // its own `body` (P1 hot path); now it's a single off-main pass
            // and the chart receives immutable arrays.
            let trendChartSeries = ExpenseTrendChart.buildChartData(
                expenses: currentFiltered,
                timeFrame: trendTimeFrame,
                referenceDate: referenceNow
            )

            // Freeze mutable aggregates into immutable snapshots before crossing
            // the main-actor boundary so captures are Sendable-safe.
            let finalTotal = total
            let finalMaxExpense = maxExpense
            let finalTotalsByCategory = totalsByCategory
            let finalCountsByCategory = countsByCategory
            let finalTotalsByCustom = totalsByCustom
            let finalCountsByCustom = countsByCustom
            let finalTrendData = trendData
            let finalHeatmapData = heatmapData
            let finalTrendChartDates = trendChartSeries.dates
            let finalTrendChartValues = trendChartSeries.values

            await MainActor.run {
                self.cachedFilteredCount = filteredCount
                self.cachedInsights = computedInsights
                self.cachedTotalSpent = finalTotal
                self.cachedPreviousTotalSpent = previousTotal
                self.cachedMaxExpense = finalMaxExpense
                self.cachedTotalsByCategory = finalTotalsByCategory
                self.cachedCountsByCategory = finalCountsByCategory
                self.cachedTotalsByCustomId = finalTotalsByCustom
                self.cachedCountsByCustomId = finalCountsByCustom
                self.cachedTrendData = finalTrendData
                self.cachedHeatmapData = finalHeatmapData
                self.cachedDailyPace = dailyPace
                self.cachedVelocity = velocity
                self.cachedYoYPoints = yoyPoints
                self.cachedTopExpenses = topExpenses
                self.cachedForecast = forecast
                self.cachedWeekdayAverages = weekdayAverages
                self.cachedTopDays = topDays
                self.cachedPaymentMethodBreakdown = paymentBreakdown
                self.cachedTrendChartDates = finalTrendChartDates
                self.cachedTrendChartValues = finalTrendChartValues
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
    //
    // Orchestrates the redesigned stack:
    //   1. Hero Overview  — big total + mini-stats in one card
    //   2. Pro Insights    — daily pace / velocity / YoY (gated)
    //   3. Highlights      — auto-generated insight cards
    //   4. Where It Goes   — donut + category rows merged with two-way selection
    //   5. Spending Pattern — the heatmap
    //   6. Trend           — just the chart (stripped of duplicated stats)
    //
    // A single `staggered(...)` helper gives every section a consistent, snappy
    // spring-in cascade so the screen feels unified.
    private var statisticsContent: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            heroOverviewSection
                .modifier(SectionEntrance(order: 0, animate: animateCards))

            ProInsightsSection(
                isPro: proManager.isPro,
                dailyPace: cachedDailyPace,
                velocity: cachedVelocity,
                yearOverYearPoints: cachedYoYPoints,
                accent: accentForSelection,
                formattedAmount: viewModel.formattedAmount,
                onUpgradeTap: { showingPaywall = true }
            )
            .modifier(SectionEntrance(order: 1, animate: animateCards))

            ForecastSection(
                isPro: proManager.isPro,
                forecast: cachedForecast,
                horizon: forecastHorizon,
                topDriverDisplayName: forecastTopDriverDisplayName,
                topDriverColor: forecastTopDriverColor,
                accent: .appPrimary,
                formattedAmount: viewModel.formattedAmount,
                currency: viewModel.selectedCurrency,
                onHorizonChange: { newValue in
                    forecastHorizon = newValue
                    scheduleRecomputeStats(immediate: true)
                },
                onUpgradeTap: { showingPaywall = true }
            )
            .modifier(SectionEntrance(order: 2, animate: animateCards))

            if !insights.isEmpty {
                highlightsSection
                    .modifier(SectionEntrance(order: 3, animate: animateCards))
            }

            if cachedFilteredCount > 0 {
                whereItGoesSection
                    .modifier(SectionEntrance(order: 4, animate: animateCards))

                paymentMethodsSection
                    .modifier(SectionEntrance(order: 5, animate: animateCards))

                spendingPatternSection
                    .modifier(SectionEntrance(order: 6, animate: animateCards))

                trendSection
                    .modifier(SectionEntrance(order: 7, animate: animateCards))
            }
        }
    }

    /// Resolves the human-readable name of the forecast's top-driver category.
    /// Built/mapped on the main actor because it needs the live custom-category
    /// list — the engine itself only knows `(category, customId)` pairs.
    private var forecastTopDriverDisplayName: String? {
        guard let driver = cachedForecast.topDriverCategory else { return nil }
        if driver.category == .custom, let id = driver.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return custom.name
        }
        return driver.category.displayName
    }

    private var forecastTopDriverColor: Color? {
        guard let driver = cachedForecast.topDriverCategory else { return nil }
        if driver.category == .custom, let id = driver.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return Color.forCategory(custom.colorName)
        }
        return Color.forCategory(driver.category.color)
    }

    /// Returns the brand color to use as "accent" when a specific category is filtered,
    /// or the app primary otherwise. Drives the tint on Pro Insights + Trend.
    private var accentForSelection: Color {
        if let selectedCategory, selectedCategory != .custom {
            return Color.forCategory(selectedCategory.color)
        }
        if selectedCategory == .custom,
           let id = selectedCustomCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return Color.forCategory(custom.colorName)
        }
        return .appPrimary
    }
    
    // MARK: - Hero Overview Section
    //
    // Single card that dominates the first fold: huge total spend, delta pill vs.
    // previous period, a subtle rule, and three inline mini-stats. Replaces the
    // old three-card grid — one glance, one number, zero redundancy.
    private var heroOverviewSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("TOTAL SPENT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                    InsightInfoButton(info: .heroOverview)
                    Spacer(minLength: 0)
                    if let category = selectedCategory {
                        heroFilterChip(category: category)
                    }
                }

                Text(viewModel.formattedAmount(totalExpenses()))
                    .font(.system(size: isWideLayout ? 44 : 38, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())
                    // Listen to amount AND currency so a Settings switch
                    // refreshes the hero immediately instead of being held
                    // back by `.contentTransition(.numericText())`'s glyph
                    // cache (which keys off the value below).
                    .moneyAnimation(amount: cachedTotalSpent, currency: viewModel.selectedCurrency)

                if let delta = heroDeltaPillData() {
                    heroDeltaPill(delta: delta)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, Theme.Spacing.lg)
                .opacity(0.5)

            heroMiniStatsRow
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.Radius.container)
        .shadow(color: Theme.Shadow.cardColor, radius: Theme.Shadow.cardRadius, x: 0, y: Theme.Shadow.cardY)
    }

    /// Compact chip in the hero top-right showing the active category filter.
    /// Tapping clears the filter — one tap to get back to the full picture.
    private func heroFilterChip(category: Expense.Category) -> some View {
        let label: String = {
            if category == .custom,
               let id = selectedCustomCategoryId,
               let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
                return custom.name
            }
            return category.displayName
        }()
        let color: Color = {
            if category == .custom,
               let id = selectedCustomCategoryId,
               let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
                return Color.forCategory(custom.colorName)
            }
            return Color.forCategory(category.color)
        }()

        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                selectedCategory = nil
                selectedCustomCategoryId = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(color)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(Capsule().fill(color.opacity(0.12)))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private struct HeroDelta {
        let changePercent: Double
        let isIncrease: Bool
        let previousTotal: Double
    }

    private func heroDeltaPillData() -> HeroDelta? {
        guard cachedPreviousTotalSpent > 0 else { return nil }
        let change = ((cachedTotalSpent - cachedPreviousTotalSpent) / cachedPreviousTotalSpent) * 100
        return HeroDelta(
            changePercent: change,
            isIncrease: change >= 0,
            previousTotal: cachedPreviousTotalSpent
        )
    }

    private func heroDeltaPill(delta: HeroDelta) -> some View {
        let color: Color = delta.isIncrease ? .red : .green
        let arrow = delta.isIncrease ? "arrow.up.right" : "arrow.down.right"
        let capped = min(abs(delta.changePercent), 999)

        return HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: arrow)
                    .font(.system(size: 10, weight: .bold))
                Text("\(String(format: "%.1f", capped))%")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundColor(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(Capsule().fill(color.opacity(0.14)))

            Text("vs previous period")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var heroMiniStatsRow: some View {
        HStack(spacing: 0) {
            miniStat(label: "Expenses", value: "\(cachedFilteredCount)", moneyAmount: nil)
            miniStatDivider
            miniStat(label: "Average",
                     value: viewModel.formattedAmount(averageExpense()),
                     moneyAmount: averageExpense())
            miniStatDivider
            miniStat(label: "Highest",
                     value: viewModel.formattedAmount(highestExpense()),
                     moneyAmount: highestExpense())
        }
    }

    private var miniStatDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: Theme.Stroke.hairline, height: 32)
    }

    /// One mini-stat cell. `moneyAmount` is non-nil for currency-bearing
    /// stats (Average, Highest) so we can include the active currency in
    /// the animation key — that way a Settings currency switch refreshes
    /// the value immediately instead of being held back by
    /// `.contentTransition(.numericText())`'s glyph cache.
    @ViewBuilder
    private func miniStat(label: String, value: String, moneyAmount: Double?) -> some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
                .lineLimit(1)

            if let amount = moneyAmount {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                    .moneyAnimation(amount: amount, currency: viewModel.selectedCurrency)
            } else {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.snappy, value: value)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Highlights Section (auto insights)
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Highlights") {
                InsightInfoButton(info: .highlights)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: isWideLayout ? 2 : 1),
                spacing: Theme.Spacing.md
            ) {
                ForEach(insights) { insight in
                    insightCard(insight)
                }
            }
        }
    }

    // MARK: - Where It Goes Section
    //
    // Donut chart + category rows combined into one card. Tapping a row selects the
    // matching donut slice (and vice versa) via shared `donutSelectedId` state, so
    // the user can explore by either side and the two halves always stay in sync.
    private var whereItGoesSection: some View {
        let slices = categorySlices()
        let rows = getCategoriesWithExpenses()
        let slicesTotal = slices.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Where It Goes") {
                HStack(spacing: Theme.Spacing.sm) {
                    if selectedCategory == nil, rows.count > 0 {
                        countBadge(count: rows.count, label: rows.count == 1 ? "category" : "categories")
                    }
                    InsightInfoButton(info: .whereItGoes)
                }
            }

            VStack(spacing: Theme.Spacing.lg) {
                if !slices.isEmpty {
                    CategoryDonutChart(
                        slices: slices,
                        total: slicesTotal,
                        selectedId: donutSelectedId,
                        onSelect: { slice in
                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                                donutSelectedId = slice?.id
                            }
                        }
                    )

                    Divider().opacity(0.4)
                }

                VStack(spacing: Theme.Spacing.md) {
                    if selectedCategory == nil {
                        ForEach(rows, id: \.name) { categoryData in
                            categoryRowButton(for: categoryData)
                        }
                    } else if selectedCategory == .custom,
                              let selectedCustomCategoryId,
                              let customCategory = categoryViewModel.customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                        let amount = totalExpenses(for: customCategory)
                        let categoryData = CategoryExpenseData(
                            name: customCategory.name,
                            amount: amount,
                            percentage: 100.0,
                            icon: customCategory.icon,
                            color: Color.forCategory(customCategory.colorName),
                            count: cachedCountsByCustomId[customCategory.id, default: 0]
                        )
                        enhancedCategoryRow(categoryData, isSelected: false)
                    } else if let category = selectedCategory {
                        let amount = totalExpenses(for: category)
                        let categoryData = CategoryExpenseData(
                            name: category.rawValue,
                            amount: amount,
                            percentage: 100.0,
                            icon: category.icon,
                            color: Color.forCategory(category.color),
                            count: cachedCountsByCategory[category, default: 0]
                        )
                        enhancedCategoryRow(categoryData, isSelected: false)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .cardSurface()
        }
        .onChange(of: selectedCategory) { donutSelectedId = nil }
        .onChange(of: selectedCustomCategoryId) { donutSelectedId = nil }
    }

    /// Tappable row — highlights the matching donut slice and fades others.
    /// Second tap clears the highlight, so rows never land in an ambiguous state.
    private func categoryRowButton(for data: CategoryExpenseData) -> some View {
        let sliceId = sliceId(forRow: data)
        let isSelected = donutSelectedId == sliceId

        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                donutSelectedId = isSelected ? nil : sliceId
            }
        } label: {
            enhancedCategoryRow(data, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    /// Maps a `CategoryExpenseData` row back to the slice id used by the donut,
    /// so the two halves of the section can stay in sync via `donutSelectedId`.
    private func sliceId(forRow data: CategoryExpenseData) -> String {
        if let defaultCategory = viewModel.getAvailableDefaultCategories()
            .first(where: { $0 != .custom && $0.rawValue == data.name }) {
            return "default:\(defaultCategory.rawValue)"
        }
        if let custom = categoryViewModel.customCategories.first(where: { $0.name == data.name }) {
            return "custom:\(custom.id.uuidString)"
        }
        return data.name
    }

    @ViewBuilder
    private func countBadge(count: Int, label: String) -> some View {
        Text("\(count) \(label)")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.tertiarySystemBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.sm, style: .continuous))
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

    // MARK: - Payment Methods Section (Pro)
    //
    // Donut + per-method rows that mirror the "Where It Goes" pattern so
    // the screen feels consistent. Free users see a locked teaser instead
    // of the live donut — that's the value gate, but capturing the data
    // upstream is intentionally free so upgrading feels instant.
    //
    // We hide the section entirely if **no** expense in the current view
    // has a payment method *and* the user is free — there's literally
    // nothing to show, and an empty Pro card would feel like dead space.
    private var paymentMethodsSection: some View {
        let breakdown = cachedPaymentMethodBreakdown
        let hasAnyData = breakdown.hasData || breakdown.unspecifiedCount > 0
        let totalCount = breakdown.slices.reduce(0) { $0 + $1.count }

        return Group {
            if hasAnyData {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    SectionHeader("Payment Methods") {
                        HStack(spacing: Theme.Spacing.sm) {
                            if proManager.isPro, breakdown.slices.count > 0 {
                                countBadge(
                                    count: breakdown.slices.count,
                                    label: breakdown.slices.count == 1 ? "method" : "methods"
                                )
                            } else if !proManager.isPro {
                                proLockBadge
                            }
                            InsightInfoButton(info: .paymentMethods)
                        }
                    }

                    if proManager.isPro {
                        paymentMethodsCard(breakdown: breakdown, totalCount: totalCount)
                    } else {
                        paymentMethodsLockedTeaser(breakdown: breakdown)
                    }
                }
                .onChange(of: selectedCategory) { paymentDonutSelectedId = nil }
                .onChange(of: selectedCustomCategoryId) { paymentDonutSelectedId = nil }
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func paymentMethodsCard(
        breakdown: PaymentMethodBreakdown,
        totalCount: Int
    ) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            if !breakdown.slices.isEmpty {
                CategoryDonutChart(
                    slices: paymentMethodDonutSlices(breakdown),
                    total: breakdown.slices.reduce(0) { $0 + $1.amount },
                    selectedId: paymentDonutSelectedId,
                    onSelect: { slice in
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                            paymentDonutSelectedId = slice?.id
                        }
                    }
                )

                Divider().opacity(0.4)

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(breakdown.slices) { slice in
                        paymentMethodRowButton(slice: slice, total: breakdown.total)
                    }
                }
            } else {
                // All expenses in view are unspecified — surface the nudge as
                // the primary content rather than as a footer.
                noTaggedMethodsHint(unspecifiedCount: breakdown.unspecifiedCount)
            }

            if breakdown.unspecifiedCount > 0 && !breakdown.slices.isEmpty {
                untaggedFooter(
                    unspecifiedCount: breakdown.unspecifiedCount,
                    coverage: breakdown.taggedCoverage
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    /// Bottom-of-card hint: tells the user how many expenses don't yet have
    /// a method tagged so the donut feels like progress, not a rebuke.
    private func untaggedFooter(unspecifiedCount: Int, coverage: Double) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(unspecifiedCount) without a method")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Tag them in Add/Edit to complete the picture (\(Int(round(coverage * 100)))% covered)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Spacing.sm + 4, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    /// Empty-state hint shown when every expense in view has no method set.
    private func noTaggedMethodsHint(unspecifiedCount: Int) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(.appPrimary.opacity(0.85))

            Text("No payment methods tagged yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Text("Add a method when you log an expense and it'll instantly appear here as a slice. \(unspecifiedCount) expenses are waiting.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    /// Pro-locked teaser: shows the slice list disabled with a single CTA.
    /// We deliberately do not render the live donut so the upgrade actually
    /// reveals new visual content rather than just re-skinning what's there.
    @ViewBuilder
    private func paymentMethodsLockedTeaser(breakdown: PaymentMethodBreakdown) -> some View {
        Button {
            HapticManager.shared.lightTap()
            showingPaywall = true
        } label: {
            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(spacing: 4) {
                    Text("See your credit-vs-cash split")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Unlock the Payment Methods donut to see exactly how much went on each card, cash, or wallet.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, Theme.Spacing.sm)
                }

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("Unlock with Pro")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .background(Capsule().fill(Color.appPrimary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Spacing.lg, style: .continuous)
                    .fill(Color.tertiarySystemBackground)
            )
        }
        .buttonStyle(.plain)
    }

    /// Small "Pro" pill mirroring how the Forecast card shows the lock state.
    private var proLockBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Pro")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.appPrimary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
    }

    /// Tappable per-method row mirroring the category row pattern: tinted
    /// pill icon, name, count, formatted amount, and percentage. Selecting
    /// a row syncs back into the donut highlight.
    @ViewBuilder
    private func paymentMethodRowButton(
        slice: PaymentMethodSlice,
        total: Double
    ) -> some View {
        let sliceId = "pm:\(slice.method.rawValue)"
        let isSelected = paymentDonutSelectedId == sliceId
        let isAnyHighlighted = paymentDonutSelectedId != nil
        let isDimmed = isAnyHighlighted && !isSelected

        Button {
            HapticManager.shared.selectionChanged()
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                paymentDonutSelectedId = isSelected ? nil : sliceId
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(slice.method.color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: slice.method.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(slice.method.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(slice.method.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(slice.count) \(slice.count == 1 ? "expense" : "expenses")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.formattedAmount(slice.amount))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(Int(round(slice.percentage)))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(slice.method.color)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Spacing.md, style: .continuous)
                    .fill(isSelected ? slice.method.color.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Spacing.md, style: .continuous)
                    .stroke(isSelected ? slice.method.color.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }

    /// Adapts our `PaymentMethodSlice` shape into the donut's reusable Slice type.
    /// We unset `category` / `customCategoryId` so taps from the donut don't
    /// inadvertently route into category-filtering logic.
    private func paymentMethodDonutSlices(_ breakdown: PaymentMethodBreakdown) -> [CategoryDonutChart.Slice] {
        breakdown.slices.map { slice in
            CategoryDonutChart.Slice(
                id: "pm:\(slice.method.rawValue)",
                title: slice.method.displayName,
                amount: slice.amount,
                color: slice.method.color,
                icon: slice.method.icon,
                category: nil,
                customCategoryId: nil
            )
        }
    }

    // MARK: - Spending Pattern Section (heatmap)
    private var spendingPatternSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Spending Pattern") {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Daily view")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    InsightInfoButton(info: .spendingPattern)
                }
            }

            SpendingHeatmap(
                // Pre-aggregated on the background recompute task — see
                // `cachedHeatmapData` in `recomputeStatsNow`. Avoids a
                // P0 main-thread O(N) re-walk of the full filtered list
                // on every Statistics body redraw.
                dailyTotals: cachedHeatmapData,
                startDate: rangeStartDate,
                endDate: rangeEndDate,
                accentColor: accentForSelection,
                formattedAmount: viewModel.formattedAmount
            )
            .padding(Theme.Spacing.lg)
            .cardSurface()
        }
    }

    // MARK: - Trend Section (swipeable pager)
    //
    // Three horizontally-paged angles on the same filtered set:
    //
    //   1. Over time    — the original line chart
    //   2. By weekday   — average per-weekday bar chart
    //   3. Top days     — five biggest single-day totals
    //
    // The pager owns its own selection state. Weekday + top-day aggregates are
    // precomputed on the background recompute task so swipes stay at 60 fps.
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Trend") {
                HStack(spacing: Theme.Spacing.sm) {
                    if let comparison = getTrendComparison(), comparison != "Stable" {
                        Text(comparison)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Theme.Spacing.sm + 2)
                            .padding(.vertical, Theme.Spacing.xs + 2)
                            .background(Capsule().fill(Color.tertiarySystemBackground))
                    }
                    InsightInfoButton(info: .trend)
                }
            }

            TrendChartPager(
                // Pre-built off-main in `recomputeStatsNow`. The pager (and
                // the underlying ExpenseTrendChart) no longer touches the
                // raw expense array on the main thread.
                trendDates: cachedTrendChartDates,
                trendValues: cachedTrendChartValues,
                timeFrame: selectedTimeFrame,
                accent: accentForSelection,
                weekdayPoints: cachedWeekdayAverages,
                topDays: cachedTopDays,
                formattedAmount: viewModel.formattedAmount
            )
            .environmentObject(viewModel)
            .padding(Theme.Spacing.lg)
            .cardSurface()
        }
    }
    
    // MARK: - Helper Views
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                    categoryFilterButton(for: category)
                }

                ForEach(categoryViewModel.customCategories) { category in
                    customCategoryFilterButton(for: category)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private func categoryFilterButton(for category: Expense.Category) -> some View {
        let isSelected = selectedCategory == category
        return Button(action: {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                if isSelected {
                    selectedCategory = nil
                    selectedCustomCategoryId = nil
                } else {
                    selectedCategory = category
                    selectedCustomCategoryId = nil
                }
            }
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                Text(category.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Color.forCategory(category.color) : Color.tertiarySystemBackground)
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func customCategoryFilterButton(for category: CustomCategory) -> some View {
        let isSelected = selectedCategory == .custom && selectedCustomCategoryId == category.id

        return Button(action: {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                if isSelected {
                    selectedCategory = nil
                    selectedCustomCategoryId = nil
                } else {
                    selectedCategory = .custom
                    selectedCustomCategoryId = category.id
                }
            }
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                Text(category.name)
                    .font(.subheadline)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Color.forCategory(category.colorName) : Color.tertiarySystemBackground)
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func insightCard(_ insight: StatInsight) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(insight.color.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: insight.icon)
                    .font(.system(size: 18))
                    .foregroundColor(insight.color)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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
        .padding(Theme.Spacing.lg)
        .cardSurface(radius: Theme.Radius.chip)
        .softShadow()
    }

    /// Renders a single category row. When `isSelected` is true, the row gets a
    /// tinted halo and the others are dimmed by the donut so it feels linked — the
    /// user can tap either the donut slice or the row to focus a category.
    private func enhancedCategoryRow(_ categoryData: CategoryExpenseData, isSelected: Bool = false) -> some View {
        let isDimmed = donutSelectedId != nil && !isSelected && selectedCategory == nil

        return VStack(spacing: Theme.Spacing.sm + 2) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(categoryData.color.opacity(isSelected ? 0.28 : 0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: categoryData.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(categoryData.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(categoryData.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("\(categoryData.count) \(categoryData.count == 1 ? "expense" : "expenses")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.sm)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.formattedAmount(categoryData.amount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if selectedCategory == nil && totalExpenses() > 0 {
                        Text("\(String(format: "%.1f", categoryData.percentage))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if selectedCategory == nil && totalExpenses() > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.tertiarySystemBackground)
                            .frame(height: 6)

                        Capsule()
                            .fill(categoryData.color)
                            .frame(
                                width: max(4, geometry.size.width * CGFloat(categoryData.percentage / 100)),
                                height: 6
                            )
                            .animation(.easeOut(duration: 0.35), value: categoryData.percentage)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, isSelected ? Theme.Spacing.sm : 0)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(categoryData.color.opacity(isSelected ? 0.08 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .stroke(categoryData.color.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
        )
        .opacity(isDimmed ? 0.45 : 1.0)
        .animation(.easeOut(duration: 0.22), value: isSelected)
        .animation(.easeOut(duration: 0.22), value: isDimmed)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        EmptyStatePanel(
            icon: "chart.pie",
            title: "No Statistics Available",
            message: "Add some expenses to see your spending patterns and insights"
        ) {
            PrimaryGradientButton(title: "Add Your First Expense", width: .hug) {
                HapticManager.shared.mediumTap()
                showingAddExpense = true
            }
        }
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

    // MARK: - PDF Report Export

    /// Builds a `ReportData` from cached aggregates and renders a PDF on a background
    /// queue. Must be called on the main actor — it flips `isExportingPDF` and
    /// hands the final URL to the share sheet.
    private func exportPDFReport() {
        guard !isExportingPDF else { return }
        isExportingPDF = true

        // Build the report payload synchronously from already-cached state. Doing this on
        // the main actor is cheap because we're just copying primitives out of `self`.
        let data = buildReportData()

        Task.detached(priority: .userInitiated) {
            do {
                let url = try PDFReportGenerator.generate(data: data)
                await MainActor.run {
                    self.exportedPDFURL = url
                    self.isExportingPDF = false
                    self.showingShareSheet = true
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    self.isExportingPDF = false
                    self.exportErrorMessage = error.localizedDescription
                    HapticManager.shared.warning()
                }
            }
        }
    }

    private func buildReportData() -> PDFReportGenerator.ReportData {
        let rangeFormatter = DateFormatter()
        rangeFormatter.dateFormat = "MMM d, yyyy"
        let subtitle = "\(rangeFormatter.string(from: rangeStartDate)) – \(rangeFormatter.string(from: rangeEndDate))"

        let categoryRows: [PDFReportGenerator.ReportData.CategoryRow] = getCategoriesWithExpenses().map {
            .init(
                name: $0.name,
                amount: $0.amount,
                percentage: $0.percentage,
                transactionCount: $0.count
            )
        }

        let customCategories = categoryViewModel.customCategories
        let topExpenseRows: [PDFReportGenerator.ReportData.ExpenseRow] = cachedTopExpenses.map { expense in
            let categoryName: String = {
                if expense.category == .custom,
                   let id = expense.customCategoryId,
                   let custom = customCategories.first(where: { $0.id == id }) {
                    return custom.name
                }
                return expense.category.displayName
            }()
            return PDFReportGenerator.ReportData.ExpenseRow(
                date: expense.date,
                title: expense.title.isEmpty ? categoryName : expense.title,
                category: categoryName,
                amount: expense.amount
            )
        }

        return PDFReportGenerator.ReportData(
            title: "CashLens Spending Report",
            subtitle: subtitle,
            rangeStart: rangeStartDate,
            rangeEnd: rangeEndDate,
            generatedAt: Date(),
            currencyCode: viewModel.selectedCurrency.rawValue,
            totalSpent: cachedTotalSpent,
            transactionCount: cachedFilteredCount,
            averagePerTransaction: averageExpense(),
            previousTotal: cachedPreviousTotalSpent,
            dailyPace: cachedDailyPace.dailyAverage,
            projectedTotal: cachedVelocity.projectedTotal,
            isProjecting: cachedVelocity.state == .projecting,
            categories: categoryRows,
            topExpenses: topExpenseRows
        )
    }
    
    private func getHeaderSubtitle() -> String {
        if viewModel.expenses.isEmpty {
            return "Add expenses to see insights"
        }
        
        let expenseCount = cachedFilteredCount
        let totalAmount = totalExpenses()
        let rangeLabel = "\(Self.formatterMediumDate.string(from: rangeStartDate)) – \(Self.formatterMediumDate.string(from: rangeEndDate))"
        
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

// MARK: - Section Entrance Modifier
//
// A unified, snappy entrance animation for every section on the Statistics
// screen. Each section specifies its `order` (0, 1, 2…) and the modifier
// stages a small translate + fade with a spring, offset by 60 ms per section.
// The whole screen settles in ~0.4 s instead of the ~1 s cascade we had before.
private struct SectionEntrance: ViewModifier {
    let order: Int
    let animate: Bool

    private var delay: Double { Double(order) * 0.06 }

    func body(content: Content) -> some View {
        content
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 12)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0)
                    .delay(delay),
                value: animate
            )
    }
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
            .environmentObject(ProManager.shared)
    }
} 