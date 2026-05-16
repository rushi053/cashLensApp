import SwiftUI

/// Landing screen.
///
/// Redesigned around a single premium "hero" glance for the selected period:
///
///   1. Compact greeting header (time-of-day aware, two action buttons)
///   2. Period selector (TimeFrame pills — moved above content so the filter
///      precedes everything it filters)
///   3. Hero spending card — big total for this period, delta vs the previous
///      comparable period, and two mini stats (expense count, avg/day)
///   4. Budget section (unchanged behavior, restyled)
///   5. Pinned categories — customizable grid of rich `PinnedCategoryCard`
///      tiles (amount + trend vs previous period + expense count + optional
///      budget bar + strong selected state). Tapping a card filters the
///      Recent Expenses list below.
///   6. Recent Expenses (with matched-geometry All / Subscriptions pill)
///
/// The older "Filter by Category" horizontal strip was removed because its
/// filter behaviour is now owned by the Pinned Categories grid (strong
/// selected state) and `QuickSearchView`'s Browse-by-Category chips handle
/// non-pinned categories. Home now has exactly one category-filter control.
///
/// All sections share the `SectionEntrance` cascading spring entrance used on
/// Statistics and Subscriptions so the whole app shares one motion language.
struct HomeView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var proManager: ProManager

    @State private var showingAddExpense = false
    @State private var showingProfile = false
    @State private var showingAllExpenses = false
    @State private var animateSections = false
    @State private var selectedExpense: Expense?
    @State private var showingCustomizeSummary = false
    @State private var showOnlySubscriptionsOnHome = false
    @State private var showingSearch = false
    @State private var showingBudgetSetup = false
    @State private var showingBudgetPaywall = false
    @State private var editingBudget: Budget?

    /// Total spent during the *previous* comparable period (e.g. last month if
    /// current TimeFrame is `.month`). Computed off-main and used to power the
    /// delta pill on the hero card. `nil` = not computed yet / no prior data.
    @State private var previousPeriodTotal: Double? = nil
    @State private var previousPeriodTask: Task<Void, Never>? = nil

    /// Per-category previous-period totals, keyed by a stable token
    /// (`"def:<rawValue>"` for default categories, `"custom:<uuid>"` for
    /// custom). Populated off-main by `recomputePinnedCategoryMetrics()` so
    /// each Pinned Category tile can render its own trend pill without
    /// recomputing at draw time.
    ///
    /// `nil` means "not yet computed" (suppresses trend rendering to avoid
    /// flashing "New" before the real comparison arrives); an empty map means
    /// the previous period genuinely had no activity.
    @State private var pinnedCategoryMetrics: [String: Double]? = nil
    @State private var pinnedMetricsTask: Task<Void, Never>? = nil

    /// Cached `StreakCalculator.summary(...)` result. The streak chip and its
    /// VoiceOver label both read from here; previously the computed property
    /// was evaluated **twice per body** and walks the full expense array plus
    /// a 90-day window. This is recomputed off-main on the same hooks as
    /// `previousPeriodTotal` so the chip stays correct without paying the
    /// cost on every re-render. `nil` = not yet computed (suppress the chip).
    @State private var cachedNoSpendStreak: StreakCalculator.StreakSummary? = nil
    @State private var noSpendStreakTask: Task<Void, Never>? = nil

    /// Earliest expense date in the user's full history. Used by
    /// `heroAveragePerActiveDay` for the `.all` timeframe so it doesn't
    /// have to `.map { $0.date }.min()` across the entire array on
    /// every body render. Recomputed alongside the no-spend streak
    /// (same hook, same data dependency). `nil` = no expenses logged.
    @State private var cachedAllTimeStartDate: Date? = nil

    @Namespace private var recentFilterNamespace

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isCompactPhone: Bool {
        UIDevice.current.userInterfaceIdiom != .pad && UIScreen.main.bounds.height < 760
    }

    var body: some View {
        ZStack {
            Color.systemBackground.edgesIgnoringSafeArea(.all)

            if isIPad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .onAppear {
            if !animateSections {
                withAnimation {
                    animateSections = true
                }
            }
            // PERF: Only recompute on appear when the caches are
            // actually empty (first time the view ever appears, or
            // after a clear-all-data event). Returning to the Home tab
            // from Statistics / Subscriptions used to re-fire all
            // three O(N) detached recomputes even though nothing had
            // changed. `onChange(of: expenses.count)` and
            // `onChange(of: selectedTimeFrame)` cover the legitimate
            // change cases.
            if previousPeriodTotal == nil { recomputePreviousPeriodTotal() }
            if pinnedCategoryMetrics == nil { recomputePinnedCategoryMetrics() }
            if cachedNoSpendStreak == nil { recomputeNoSpendStreak() }
        }
        .onChange(of: viewModel.selectedTimeFrame) { _, _ in
            recomputePreviousPeriodTotal()
            recomputePinnedCategoryMetrics()
        }
        .onChange(of: viewModel.expenses.count) { _, _ in
            recomputePreviousPeriodTotal()
            recomputePinnedCategoryMetrics()
            recomputeNoSpendStreak()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(viewModel)
                .environmentObject(proManager)
                .environmentObject(budgetViewModel)
                .environmentObject(categoryViewModel)
        }
        .sheet(isPresented: $showingAllExpenses) {
            AllExpensesView()
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
        }
        .sheet(item: $selectedExpense) { expense in
            AddExpenseView(
                viewModel: viewModel,
                title: expense.title,
                amount: viewModel.formattedAmount(expense.amount),
                date: expense.date,
                selectedCategory: expense.category,
                selectedCustomCategoryId: expense.customCategoryId,
                notes: expense.notes ?? "",
                tags: expense.tags ?? [],
                isRefund: expense.isRefund,
                paymentMethod: expense.paymentMethod,
                receiptImagePath: expense.receiptImagePath,
                isEditing: true,
                expenseId: expense.id,
                onSave: { title, amount, date, category, customCategoryId, notes, tags, isRefund, paymentMethod, receiptImagePath in
                    var updatedExpense = expense
                    updatedExpense.title = title
                    updatedExpense.amount = amount
                    updatedExpense.date = date
                    updatedExpense.category = category
                    updatedExpense.customCategoryId = customCategoryId
                    updatedExpense.notes = notes
                    updatedExpense.tags = tags
                    updatedExpense.isRefund = isRefund
                    updatedExpense.paymentMethod = paymentMethod
                    updatedExpense.receiptImagePath = receiptImagePath
                    viewModel.updateExpense(updatedExpense)
                }
            )
            .environmentObject(categoryViewModel)
        }
        .sheet(isPresented: $showingCustomizeSummary) {
            SummaryCustomizationView()
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
        }
        .sheet(isPresented: $showingSearch) {
            QuickSearchView()
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
        }
        .sheet(isPresented: $showingBudgetSetup) {
            BudgetSetupView()
                .environmentObject(budgetViewModel)
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(proManager)
        }
        .sheet(isPresented: $showingBudgetPaywall) {
            PaywallView()
        }
        .sheet(item: $editingBudget) { budget in
            BudgetSetupView(editingBudget: budget)
                .environmentObject(budgetViewModel)
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(proManager)
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: isCompactPhone ? Theme.Spacing.lg + 2 : Theme.Spacing.xxl) {
                headerView
                    .modifier(SectionEntrance(order: 0, animate: animateSections))

                periodSelector
                    .modifier(SectionEntrance(order: 1, animate: animateSections))

                if viewModel.expenses.isEmpty {
                    emptyStateView
                        .modifier(SectionEntrance(order: 2, animate: animateSections))
                } else {
                    heroSpendingCard
                        .modifier(SectionEntrance(order: 2, animate: animateSections))

                    budgetSection
                        .modifier(SectionEntrance(order: 3, animate: animateSections))

                    pinnedCategoriesSection
                        .modifier(SectionEntrance(order: 4, animate: animateSections))

                    recentExpensesView
                        .modifier(SectionEntrance(order: 5, animate: animateSections))
                }
            }
            .padding()
            .padding(.bottom, isCompactPhone ? 104 : Theme.Spacing.tabBarInset)
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxxl) {
                headerView
                    .padding(.bottom, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .modifier(SectionEntrance(order: 0, animate: animateSections))

                periodSelector
                    .padding(.horizontal, Theme.Spacing.xl)
                    .modifier(SectionEntrance(order: 1, animate: animateSections))

                if viewModel.expenses.isEmpty {
                    emptyStateView
                        .modifier(SectionEntrance(order: 2, animate: animateSections))
                } else {
                    VStack(spacing: Theme.Spacing.xxxl) {
                        iPadSection(title: "Overview") {
                            heroSpendingCardContent
                        }
                        .modifier(SectionEntrance(order: 2, animate: animateSections))

                        budgetSection
                            .padding(.horizontal, Theme.Spacing.xl)
                            .modifier(SectionEntrance(order: 3, animate: animateSections))

                        iPadSection(
                            title: "Pinned Categories",
                            trailing: {
                                SectionHeaderLink(title: "Customize", icon: "slider.horizontal.3") {
                                    HapticManager.shared.lightTap()
                                    showingCustomizeSummary = true
                                }
                            }
                        ) {
                            pinnedCategoriesContent
                                .frame(minHeight: 160)
                        }
                        .modifier(SectionEntrance(order: 4, animate: animateSections))

                        iPadSection(
                            title: "Recent Activity",
                            trailing: {
                                SectionHeaderLink(title: "See All") {
                                    HapticManager.shared.lightTap()
                                    showingAllExpenses = true
                                }
                            }
                        ) {
                            recentExpensesContent
                        }
                        .modifier(SectionEntrance(order: 5, animate: animateSections))
                    }
                }
            }
            .padding(Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.tabBarInset)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - iPad Section Helpers

    @ViewBuilder
    private func iPadSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            SectionHeader(title)
                .padding(.horizontal, Theme.Spacing.xl)

            content()
                .padding(Theme.Spacing.xl)
                .cardSurface()
        }
    }

    @ViewBuilder
    private func iPadSection<Trailing: View, Content: View>(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            SectionHeader(title, trailing: trailing)
                .padding(.horizontal, Theme.Spacing.xl)

            content()
                .padding(Theme.Spacing.xl)
                .cardSurface()
        }
    }

    // MARK: - Header

    /// Time-of-day-aware greeting. No dark-mode toggle here anymore —
    /// Profile → Appearance is the canonical entry point.
    private var headerView: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    Text(greetingPrefix)
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text(timeOfDayEmoji)
                        .font(.title3)
                }

                Text(viewModel.userName)
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(homeRangeLabel())
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.sm + 2) {
                headerIconButton(
                    system: "magnifyingglass",
                    label: "Search expenses"
                ) {
                    HapticManager.shared.lightTap()
                    showingSearch = true
                }

                headerIconButton(
                    system: "person.crop.circle.fill",
                    label: "Open profile",
                    size: 22
                ) {
                    HapticManager.shared.lightTap()
                    showingProfile = true
                }
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func headerIconButton(
        system: String,
        label: String,
        size: CGFloat = 18,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LinearGradient.appPrimaryDiagonal)
                .frame(width: 40, height: 40)
                // Elevated white disc — same surface system as the cards.
                // Adapts to dark mode via the shared ElevatedCircleSurface
                // helper so it always sits cleanly above the page.
                .modifier(ElevatedCircleSurface())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default:      return "Hey there,"
        }
    }

    private var timeOfDayEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "☀️"
        case 12..<17: return "🌤️"
        case 17..<22: return "🌆"
        default:      return "🌙"
        }
    }

    /// Hoisted so we don't pay an `init` allocation on every header redraw.
    /// `DateFormatter` is reference-typed but reading is thread-safe; we only
    /// touch this from the main actor (UI body), so a lazy static is safe.
    private static let homeRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func homeRangeLabel() -> String {
        let tf = viewModel.selectedTimeFrame

        if tf == .all {
            return "All time"
        }

        let formatter = HomeView.homeRangeFormatter
        let range = tf.dateRange(referenceDate: Date())
        let start = formatter.string(from: range.start)
        let endInclusive = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let end = formatter.string(from: endInclusive)

        if start == end { return start }
        return "\(start) – \(end)"
    }

    // MARK: - Period Selector (TimeFrame pills, moved up)

    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                    PillChip(
                        title: timeFrame.rawValue,
                        isSelected: viewModel.selectedTimeFrame == timeFrame
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(Theme.Motion.tap) {
                            viewModel.selectedTimeFrame = timeFrame
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
    }

    // MARK: - Hero Spending Card

    /// Premium glance card: big total for the active period, delta vs the
    /// previous comparable period, and two mini stats. Tapping opens All
    /// Expenses so drilling down feels natural.
    private var heroSpendingCard: some View {
        Button {
            HapticManager.shared.lightTap()
            showingAllExpenses = true
        } label: {
            heroSpendingCardContent
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Spent \(viewModel.formattedAmount(viewModel.cachedTotalAmount)) this \(heroPeriodNoun). Tap to see all expenses.")
    }

    private var heroSpendingCardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(heroPeriodCaption)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.4)
                    .textCase(.uppercase)

                Spacer()

                if let chip = noSpendStreakChipText {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(chip)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.green.opacity(0.12))
                    )
                    .accessibilityLabel(noSpendStreakAccessibilityLabel ?? "")
                    .transition(.scale.combined(with: .opacity))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                Text(viewModel.formattedAmount(viewModel.cachedTotalAmount))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
                    .moneyAnimation(Theme.Motion.tap,
                                    amount: viewModel.cachedTotalAmount,
                                    currency: viewModel.selectedCurrency)

                Spacer(minLength: Theme.Spacing.xs)

                if let delta = heroDelta {
                    heroDeltaPill(delta)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Divider().opacity(0.4)

            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                heroMiniStat(
                    value: "\(viewModel.filteredExpenses.count)",
                    label: viewModel.filteredExpenses.count == 1 ? "Expense" : "Expenses"
                )

                heroStatDivider

                heroMiniStat(
                    value: viewModel.formattedAmount(heroAveragePerActiveDay),
                    label: heroAverageLabel
                )

                heroStatDivider

                heroMiniStat(
                    value: heroTopCategoryName,
                    label: "Top category",
                    isText: true
                )
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Hero gets the glass surface plus a tinted brand stroke (overrides
        // the default hairline glass edge) so the most prominent card on
        // the home screen reads as the on-brand anchor.
        .cardSurface(
            radius: Theme.Radius.container,
            stroke: Color.appPrimary.opacity(0.18)
        )
    }

    private func heroMiniStat(value: String, label: String, isText: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(isText
                      ? .system(size: 15, weight: .semibold, design: .rounded)
                      : .system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroStatDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    /// "This month" / "This week" / etc. Uppercase caption.
    private var heroPeriodCaption: String {
        switch viewModel.selectedTimeFrame {
        case .day:   return "Spent today"
        case .week:  return "Spent this week"
        case .month: return "Spent this month"
        case .year:  return "Spent this year"
        case .all:   return "Lifetime spending"
        }
    }

    /// Noun used in the accessibility label ("this month" / "this year"…).
    private var heroPeriodNoun: String {
        switch viewModel.selectedTimeFrame {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        case .all:   return "lifetime"
        }
    }

    /// How many days the selected period has elapsed so far — used as the
    /// divisor for the "avg / day" mini stat so partial months don't look
    /// artificially low.
    ///
    /// PERF: For the `.all` timeframe this previously ran a full
    /// `filteredExpenses.map { $0.date }.min()` on **every** Home body
    /// render. With a large history that was a non-trivial CPU spike
    /// folded into scroll / animation frames. We now cache the
    /// earliest-expense date in `cachedAllTimeStartDate`, populated by
    /// `recomputePinnedCategoryMetrics()` (which already runs whenever
    /// expenses change). For non-`.all` timeframes the math is O(1) so
    /// no caching is needed there.
    private var heroAveragePerActiveDay: Double {
        let tf = viewModel.selectedTimeFrame
        let calendar = Calendar.current
        let now = Date()

        if tf == .all {
            guard let earliest = cachedAllTimeStartDate else { return 0 }
            let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: now)).day ?? 1)
            return viewModel.cachedTotalAmount / Double(days)
        }

        let range = tf.dateRange(referenceDate: now)
        let startDay = calendar.startOfDay(for: range.start)
        let cap = min(now, range.end)
        let daysElapsed = max(1, (calendar.dateComponents([.day], from: startDay, to: cap).day ?? 0) + 1)
        return viewModel.cachedTotalAmount / Double(daysElapsed)
    }

    private var heroAverageLabel: String {
        switch viewModel.selectedTimeFrame {
        case .day:   return "Per hour*"
        default:     return "Per day avg"
        }
    }

    // MARK: - No-Spend Streak chip
    //
    // Shown only when `StreakCalculator` reports a meaningful streak. The chip
    // prefers to surface the current run if it's >= 2 days (most addictive
    // signal), otherwise falls back to the "X no-spend days this month"
    // framing. Hidden entirely when neither signal is interesting.
    //
    // Both readouts below pull from `cachedNoSpendStreak` (an `@State`
    // populated off-main in `recomputeNoSpendStreak`). Previously this was
    // a computed property that scanned the full expense array twice per body
    // — once for the chip text, once for the VoiceOver label — which lit up
    // on every save / scroll / theme change.

    private var noSpendStreakChipText: String? {
        guard let s = cachedNoSpendStreak, s.isMeaningful else { return nil }

        if s.currentStreak >= 2 {
            return "\(s.currentStreak)-day streak"
        }
        if s.noSpendDaysThisMonth >= 1 {
            return "\(s.noSpendDaysThisMonth) no-spend"
        }
        return nil
    }

    private var noSpendStreakAccessibilityLabel: String? {
        guard let s = cachedNoSpendStreak, s.isMeaningful else { return nil }
        if s.currentStreak >= 2 {
            return "On a \(s.currentStreak) day no-spend streak. Best streak: \(s.bestStreak) days."
        }
        return "\(s.noSpendDaysThisMonth) no-spend days this month."
    }

    /// Debounced background recompute of the no-spend streak. Mirrors the
    /// pattern used for `recomputePreviousPeriodTotal` so the same lifecycle
    /// hooks update both. `StreakCalculator.summary` is pure value-type math
    /// over a snapshot, so it's safe to run from `Task.detached`.
    ///
    /// PERF: Also computes `cachedAllTimeStartDate` in the same detached
    /// pass — it walks the snapshot anyway, so getting the min date is
    /// free. That saves another O(N) loop in `heroAveragePerActiveDay`.
    private func recomputeNoSpendStreak() {
        noSpendStreakTask?.cancel()
        let snapshot = viewModel.expenses
        let referenceDate = Date()

        noSpendStreakTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let (summary, earliest) = await Task.detached(priority: .utility) {
                let s = StreakCalculator.summary(from: snapshot, now: referenceDate)
                let e = snapshot.min(by: { $0.date < $1.date })?.date
                return (s, e)
            }.value

            guard !Task.isCancelled else { return }
            cachedNoSpendStreak = summary
            cachedAllTimeStartDate = earliest
        }
    }

    /// Best-effort "biggest category this period" readout for the mini stat.
    /// Returns "—" when there isn't enough data or a clear winner.
    private var heroTopCategoryName: String {
        let customCategories = categoryViewModel.customCategories

        // Rank by amount; include custom categories.
        var ranked: [(name: String, amount: Double)] = []
        for (category, amount) in viewModel.cachedTotalsByCategory {
            guard category != .custom, amount > 0 else { continue }
            ranked.append((category.displayName, amount))
        }
        // Custom categories are separately cached by id.
        // We fetch via the view-model helper to keep all bookkeeping in one place.
        for custom in customCategories {
            let amount = viewModel.totalExpenses(forCustomCategoryId: custom.id)
            guard amount > 0 else { continue }
            ranked.append((custom.name, amount))
        }

        return ranked.max(by: { $0.amount < $1.amount })?.name ?? "—"
    }

    // MARK: - Hero delta pill

    /// Computed comparison of the current period's total to the previous
    /// comparable period. `nil` for `.all` (no meaningful comparison) or when
    /// we haven't finished background-computing the previous total yet.
    private var heroDelta: HeroDelta? {
        guard viewModel.selectedTimeFrame != .all else { return nil }
        guard let previous = previousPeriodTotal else { return nil }
        let current = viewModel.cachedTotalAmount

        // If both are zero there's nothing to show.
        if previous == 0, current == 0 { return nil }

        if previous == 0 {
            return HeroDelta(direction: .up, percentText: "New", isNeutral: true)
        }

        let ratio = (current - previous) / previous
        let percent = Int((abs(ratio) * 100).rounded())
        if percent == 0 {
            return HeroDelta(direction: .flat, percentText: "Same", isNeutral: true)
        }

        let direction: HeroDelta.Direction = current > previous ? .up : .down
        return HeroDelta(direction: direction, percentText: "\(percent)%", isNeutral: false)
    }

    private func heroDeltaPill(_ delta: HeroDelta) -> some View {
        // Up in spending = red-ish (warning), down = green (good). Neutral = appPrimary.
        let tint: Color = {
            if delta.isNeutral { return .appPrimary }
            switch delta.direction {
            case .up:   return .red
            case .down: return .green
            case .flat: return .appPrimary
            }
        }()

        return HStack(spacing: 4) {
            Image(systemName: delta.iconName)
                .font(.system(size: 10, weight: .bold))
            Text(delta.percentText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
    }

    private struct HeroDelta {
        enum Direction {
            case up, down, flat
        }

        let direction: Direction
        let percentText: String
        let isNeutral: Bool

        var iconName: String {
            switch direction {
            case .up:   return "arrow.up"
            case .down: return "arrow.down"
            case .flat: return "equal"
            }
        }
    }

    /// Kick off a debounced background compute of the previous period total.
    /// Never blocks the main thread; safely bails when the TimeFrame is `.all`.
    private func recomputePreviousPeriodTotal() {
        previousPeriodTask?.cancel()

        let tf = viewModel.selectedTimeFrame
        guard tf != .all else {
            previousPeriodTotal = nil
            return
        }

        let snapshot = viewModel.expenses
        let referenceDate = Date()

        previousPeriodTask = Task { @MainActor in
            // Small debounce so quick TimeFrame flicks don't spawn work.
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let total = await Task.detached(priority: .utility) {
                HomeView.computePreviousPeriodTotal(
                    expenses: snapshot,
                    timeFrame: tf,
                    referenceDate: referenceDate
                )
            }.value

            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.tap) {
                previousPeriodTotal = total
            }
        }
    }

    nonisolated private static func computePreviousPeriodTotal(
        expenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        referenceDate: Date
    ) -> Double {
        let calendar = Calendar.current
        let current = timeFrame.dateRange(referenceDate: referenceDate)

        // Build previous range by offsetting the same calendar unit backwards.
        let prevReference: Date? = {
            switch timeFrame {
            case .day:   return calendar.date(byAdding: .day, value: -1, to: referenceDate)
            case .week:  return calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate)
            case .month: return calendar.date(byAdding: .month, value: -1, to: referenceDate)
            case .year:  return calendar.date(byAdding: .year, value: -1, to: referenceDate)
            case .all:   return nil
            }
        }()
        guard let prevRef = prevReference else { return 0 }

        let previous = timeFrame.dateRange(referenceDate: prevRef)

        // Match the natural boundary of the current period: if today is the
        // 8th of the month, only sum up through day 8 of the previous month so
        // the delta compares apples-to-apples.
        let elapsedInterval = referenceDate.timeIntervalSince(current.start)
        let previousCap = previous.start.addingTimeInterval(elapsedInterval)
        let upperBound = min(previousCap, previous.end)

        var total: Double = 0
        for expense in expenses where expense.amount.isFinite {
            if expense.date >= previous.start && expense.date < upperBound {
                // Refund-aware so the delta pill compares net-vs-net.
                total += expense.signedAmount
            }
        }
        return total.isFinite ? total : 0
    }

    // MARK: - Pinned Categories (formerly "Summary")

    private var pinnedCategoriesSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SectionHeader("Pinned Categories") {
                SectionHeaderLink(title: "Customize", icon: "slider.horizontal.3") {
                    HapticManager.shared.lightTap()
                    showingCustomizeSummary = true
                }
            }

            pinnedCategoriesContent
        }
    }

    /// Identifiable wrapper around the view-model's summary tuple so the
    /// `ForEach` below can use a **stable** identity (the per-category
    /// pinned token) instead of array index. Index-based ids cause SwiftUI
    /// to misattribute state across reorders — animations from one tile
    /// would land on the next when a user customizes their pinned set.
    private struct PinnedTile: Identifiable {
        let id: String
        let category: Expense.Category?
        let customCategoryId: UUID?
        let title: String
        let amount: Double
        let icon: String
        let color: Color
    }

    /// The view-model's summary helper always returns the "Total Expenses"
    /// tile first; drop it here because the hero card already shows that
    /// number at much larger size.
    private var pinnedCategoryTiles: [PinnedTile] {
        viewModel
            .getSummaryCardsData(customCategories: categoryViewModel.customCategories)
            .filter { !($0.category == nil && $0.customCategoryId == nil) }
            .map { tuple in
                // Token derived from the tile's category identity, not its
                // position; falls back to the title only for the unreachable
                // "Total Expenses" tile we already filtered out.
                let id = HomeView.pinnedToken(for: tuple.category, customCategoryId: tuple.customCategoryId)
                    ?? "tile-\(tuple.title)"
                return PinnedTile(
                    id: id,
                    category: tuple.category,
                    customCategoryId: tuple.customCategoryId,
                    title: tuple.title,
                    amount: tuple.amount,
                    icon: tuple.icon,
                    color: tuple.color
                )
            }
    }

    @ViewBuilder
    private var pinnedCategoriesContent: some View {
        let tiles = pinnedCategoryTiles

        if tiles.isEmpty {
            pinnedCategoriesEmptyPrompt
        } else {
            AdaptiveGrid {
                ForEach(tiles) { cardData in
                    PinnedCategoryCard(
                        title: cardData.title,
                        amount: cardData.amount,
                        icon: cardData.icon,
                        color: cardData.color,
                        expenseCount: pinnedExpenseCount(
                            for: cardData.category,
                            customCategoryId: cardData.customCategoryId
                        ),
                        trend: pinnedTrend(
                            for: cardData.category,
                            customCategoryId: cardData.customCategoryId,
                            currentAmount: cardData.amount
                        ),
                        budget: pinnedBudgetSignal(
                            for: cardData.category,
                            customCategoryId: cardData.customCategoryId
                        ),
                        isSelected: isPinnedCardSelected(
                            category: cardData.category,
                            customCategoryId: cardData.customCategoryId
                        ),
                        action: {
                            HapticManager.shared.lightTap()
                            togglePinnedFilter(
                                category: cardData.category,
                                customCategoryId: cardData.customCategoryId
                            )
                        }
                    )
                }
            }
        }
    }

    // MARK: Pinned Category helpers

    /// Stable token used to key per-category metrics across compute/lookup.
    nonisolated private static func pinnedToken(for category: Expense.Category?, customCategoryId: UUID?) -> String? {
        if let customId = customCategoryId { return "custom:\(customId.uuidString)" }
        if let cat = category, cat != .custom { return "def:\(cat.rawValue)" }
        return nil
    }

    nonisolated private static func pinnedToken(for expense: Expense) -> String {
        if expense.category == .custom, let customId = expense.customCategoryId {
            return "custom:\(customId.uuidString)"
        }
        return "def:\(expense.category.rawValue)"
    }

    private func pinnedExpenseCount(for category: Expense.Category?, customCategoryId: UUID?) -> Int {
        if let customId = customCategoryId {
            return viewModel.expenseCount(forCustomCategoryId: customId)
        }
        if let cat = category {
            return viewModel.expenseCount(for: cat)
        }
        return 0
    }

    private func pinnedTrend(
        for category: Expense.Category?,
        customCategoryId: UUID?,
        currentAmount: Double
    ) -> PinnedCategoryCard.Trend? {
        // No comparable previous period when "All" time is selected.
        guard viewModel.selectedTimeFrame != .all else { return nil }
        guard let metrics = pinnedCategoryMetrics else { return nil }
        guard let token = HomeView.pinnedToken(for: category, customCategoryId: customCategoryId) else {
            return nil
        }
        let previous = metrics[token] ?? 0
        // Only render a trend pill when there's genuine comparison signal.
        // No previous data → no pill (don't spam "+ New" on every card).
        if previous == 0 { return nil }
        if currentAmount == 0 { return .down(1.0) }
        let delta = (currentAmount - previous) / previous
        if abs(delta) < 0.02 { return .flat }
        return delta > 0 ? .up(delta) : .down(abs(delta))
    }

    private func pinnedBudgetSignal(
        for category: Expense.Category?,
        customCategoryId: UUID?
    ) -> PinnedCategoryCard.BudgetSignal? {
        let filter: Budget.CategoryFilter
        if let customId = customCategoryId {
            filter = .customCategory(customId)
        } else if let cat = category, cat != .custom {
            filter = .defaultCategory(cat.rawValue)
        } else {
            return nil
        }
        guard let budget = budgetViewModel.budgets.first(where: { $0.isActive && $0.categoryFilter == filter }) else {
            return nil
        }
        let progress = budgetViewModel.progress(for: budget)
        guard progress.limit > 0 else { return nil }
        return PinnedCategoryCard.BudgetSignal(spent: progress.spent, limit: progress.limit)
    }

    private func isPinnedCardSelected(category: Expense.Category?, customCategoryId: UUID?) -> Bool {
        if let customId = customCategoryId {
            return viewModel.selectedCategory == .custom && viewModel.selectedCustomCategoryId == customId
        }
        if let cat = category {
            return viewModel.selectedCategory == cat && viewModel.selectedCustomCategoryId == nil
        }
        return false
    }

    /// Tap a Pinned Category card: toggles the same filter that used to live
    /// in the (removed) "Filter by Category" strip. Tapping the currently
    /// selected card clears the filter.
    private func togglePinnedFilter(category: Expense.Category?, customCategoryId: UUID?) {
        withAnimation(Theme.Motion.snappy) {
            if isPinnedCardSelected(category: category, customCategoryId: customCategoryId) {
                viewModel.selectedCategory = nil
                viewModel.selectedCustomCategoryId = nil
            } else if let customId = customCategoryId {
                viewModel.selectedCategory = .custom
                viewModel.selectedCustomCategoryId = customId
            } else {
                viewModel.selectedCategory = category
                viewModel.selectedCustomCategoryId = nil
            }
        }
    }

    /// Debounced background recompute of per-category previous-period totals.
    /// Mirrors the pattern used for `recomputePreviousPeriodTotal` so we never
    /// block the main thread, and a single pass touches every pinned tile.
    private func recomputePinnedCategoryMetrics() {
        pinnedMetricsTask?.cancel()

        let tf = viewModel.selectedTimeFrame
        guard tf != .all else {
            pinnedCategoryMetrics = nil
            return
        }

        let snapshot = viewModel.expenses
        let referenceDate = Date()

        pinnedMetricsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .utility) {
                HomeView.computePinnedCategoryMetrics(
                    expenses: snapshot,
                    timeFrame: tf,
                    referenceDate: referenceDate
                )
            }.value

            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.tap) {
                pinnedCategoryMetrics = result
            }
        }
    }

    nonisolated private static func computePinnedCategoryMetrics(
        expenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        referenceDate: Date
    ) -> [String: Double] {
        let calendar = Calendar.current
        let prevReference: Date? = {
            switch timeFrame {
            case .day:   return calendar.date(byAdding: .day, value: -1, to: referenceDate)
            case .week:  return calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate)
            case .month: return calendar.date(byAdding: .month, value: -1, to: referenceDate)
            case .year:  return calendar.date(byAdding: .year, value: -1, to: referenceDate)
            case .all:   return nil
            }
        }()
        guard let prevRef = prevReference else { return [:] }

        let current = timeFrame.dateRange(referenceDate: referenceDate)
        let previous = timeFrame.dateRange(referenceDate: prevRef)

        // Apples-to-apples: only count prior-period expenses up to the same
        // elapsed offset from that period's start as `now` is from the current
        // period's start (so a mid-month snapshot compares to mid-last-month).
        let elapsedInterval = referenceDate.timeIntervalSince(current.start)
        let previousCap = previous.start.addingTimeInterval(elapsedInterval)
        let upperBound = min(previousCap, previous.end)

        var byToken: [String: Double] = [:]
        for expense in expenses where expense.amount.isFinite {
            if expense.date >= previous.start && expense.date < upperBound {
                // Refund-aware so per-tile trend pills compare net-vs-net.
                byToken[pinnedToken(for: expense), default: 0] += expense.signedAmount
            }
        }
        return byToken
    }

    private var pinnedCategoriesEmptyPrompt: some View {
        Button {
            HapticManager.shared.lightTap()
            showingCustomizeSummary = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "pin.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pin your top categories")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Glance at what matters most on Home")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(Theme.Spacing.lg)
            .cardSurface(radius: Theme.Radius.row)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Adaptive Grid

    private struct AdaptiveGrid<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            LazyVGrid(
                columns: Self.columns(isPad: UIDevice.current.userInterfaceIdiom == .pad),
                spacing: Theme.Spacing.lg
            ) {
                content
            }
        }

        private static func columns(isPad: Bool) -> [GridItem] {
            if isPad {
                return Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.lg),
                    count: 3
                )
            } else {
                return Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.lg),
                    count: 2
                )
            }
        }
    }

    // MARK: - Recent Expenses

    private var recentExpensesView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SectionHeader("Recent Expenses") {
                SectionHeaderLink(title: "See All") {
                    HapticManager.shared.lightTap()
                    showingAllExpenses = true
                }
            }

            recentFilterChips

            recentExpensesList
        }
    }

    private var recentExpensesContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            recentFilterChips
            recentExpensesList
        }
    }

    /// Matched-geometry segmented pills mirroring the Subscriptions page filter
    /// so the app shares one interaction vocabulary.
    private var recentFilterChips: some View {
        HStack(spacing: Theme.Spacing.sm) {
            recentFilterPill(
                title: "All",
                icon: nil,
                isSelected: !showOnlySubscriptionsOnHome
            ) {
                HapticManager.shared.selectionChanged()
                withAnimation(Theme.Motion.snappy) {
                    showOnlySubscriptionsOnHome = false
                }
            }

            recentFilterPill(
                title: "Subscriptions",
                icon: "arrow.triangle.2.circlepath",
                isSelected: showOnlySubscriptionsOnHome
            ) {
                HapticManager.shared.selectionChanged()
                withAnimation(Theme.Motion.snappy) {
                    showOnlySubscriptionsOnHome = true
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func recentFilterPill(
        title: String,
        icon: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.md + 2)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.appPrimary)
                            .matchedGeometryEffect(id: "recentFilter", in: recentFilterNamespace)
                    } else {
                        Capsule()
                            .fill(Color.secondarySystemBackground)
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recentExpensesList: some View {
        // PERF: When the user toggles "show only subscriptions" we only
        // ever display the first 5 rows. Previously the eager `.filter`
        // walked the **entire** `filteredExpenses` array — fine for 10
        // expenses, painful at 1500. Using a lazy chain lets Swift
        // short-circuit after we've collected enough matches.
        let list: [Expense] = showOnlySubscriptionsOnHome
            ? Array(viewModel.filteredExpenses.lazy.filter { $0.isFromSubscription }.prefix(5))
            : Array(viewModel.filteredExpenses.prefix(5))

        if list.isEmpty {
            InlineEmptyState(
                icon: "doc.text.magnifyingglass",
                title: "No expenses found",
                message: showOnlySubscriptionsOnHome
                    ? "No subscription expenses in this period"
                    : "Add your first expense by tapping the + button"
            )
        } else {
            LazyVStack(spacing: Theme.Spacing.lg) {
                // `list` is already capped at 5 by the lazy slice above;
                // no need for another `prefix(5)` here.
                ForEach(list, id: \.id) { expense in
                    ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
                        .equatable()
                        .onTapGesture {
                            HapticManager.shared.impact(style: .light)
                            selectedExpense = expense
                        }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        EmptyStatePanel(
            icon: "plus.circle",
            title: "No Expenses Yet",
            message: "Start tracking your expenses by tapping the + button below"
        ) {
            PrimaryGradientButton(title: "Add Your First Expense", width: .hug) {
                HapticManager.shared.heavyTap()
                showingAddExpense = true
            }
        }
        .frame(minHeight: 500)
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
                .environmentObject(categoryViewModel)
        }
    }

    // MARK: - Budget Section

    private func presentBudgetCreation() {
        if proManager.isPro {
            showingBudgetSetup = true
        } else {
            showingBudgetPaywall = true
        }
    }

    @ViewBuilder
    private var budgetSection: some View {
        if !proManager.isPro {
            budgetProTeaser
        } else {
            let active = budgetViewModel.activeBudgets
            if !active.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    SectionHeader("Budgets") {
                        Button {
                            HapticManager.shared.lightTap()
                            presentBudgetCreation()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.appPrimary)
                                .contentShape(Rectangle())
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel("Add budget")
                    }

                    if active.count == 1, let budget = active.first {
                        BudgetProgressCard(
                            budget: budget,
                            progress: budgetViewModel.progress(for: budget),
                            currencySymbol: viewModel.selectedCurrency.symbol,
                            formattedAmount: viewModel.formattedAmount,
                            currency: viewModel.selectedCurrency,
                            onTap: { editingBudget = budget }
                        )
                    } else {
                        AdaptiveGrid {
                            ForEach(active) { budget in
                                BudgetMiniCard(
                                    budget: budget,
                                    progress: budgetViewModel.progress(for: budget),
                                    formattedAmount: viewModel.formattedAmount,
                                    currency: viewModel.selectedCurrency,
                                    onTap: { editingBudget = budget }
                                )
                            }
                        }
                    }
                }
            } else {
                budgetEmptyPrompt
            }
        }
    }

    private var budgetProTeaser: some View {
        Button {
            HapticManager.shared.mediumTap()
            showingBudgetPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.md + 2) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.appPrimarySoft)
                        .frame(width: 48, height: 48)
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LinearGradient.appPrimaryDiagonal)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs + 2) {
                        Text("Budgets & alerts")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("PRO")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.appPrimary)
                            )
                    }
                    Text("Set spending limits, see live progress, get alerts at 80% and 100%.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "lock.open.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.appPrimary)
            }
            .padding(Theme.Spacing.lg)
            .cardSurface(radius: Theme.Radius.container)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .stroke(Color.appPrimary.opacity(0.30), lineWidth: Theme.Stroke.thin)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var budgetEmptyPrompt: some View {
        Button {
            HapticManager.shared.lightTap()
            presentBudgetCreation()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Set a Budget")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Track spending and stay on target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(Theme.Spacing.lg)
            .cardSurface(radius: Theme.Radius.row)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Entrance animation

/// Cascading spring-based entrance mirroring the Statistics and Subscriptions
/// pages so the whole app shares one "section appears" motion.
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

// MARK: - Preview

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
            .environmentObject(BudgetViewModel())
            .environmentObject(ProManager.shared)
    }
}
