import SwiftUI

/// `TodayView` — the redesigned landing screen for v2.
///
/// One job: answer **"am I OK right now?"** in under two seconds.
///
/// The previous `HomeView` tried to be a dashboard *and* a quick-add
/// surface *and* a recent-activity list *and* a pinned-category picker
/// *and* a budget hub *and* a subscription pill — six jobs competing
/// for the same vertical space, all sized at "important." That's why
/// users had to scroll past everything else to find the budget card
/// (the single most important readout) and why the "split-brain"
/// timeframe state with Statistics quietly eroded trust.
///
/// TodayView strips the screen down to four things, in order:
///
///   1. **Verdict hero** — one fused readout: spend vs budget, days
///      left, projected month-end, and a one-word verdict pill
///      (On Track / Tight / Over). When the user has no budget,
///      degrades gracefully to a pace-vs-typical-month comparison.
///   2. **7-day spending strip** — horizontal bar-per-day spark,
///      tinted by each day's dominant category, today highlighted.
///      Lets the user see this week's shape at a glance.
///   3. **Three most recent expenses** — verification, not browsing.
///      "See all activity →" jumps to the Activity tab.
///   4. **One insight card** — the single best card `SmartInsightsEngine`
///      finds today, or a calm celebratory state when nothing notable
///      is happening.
///
/// What deliberately doesn't appear on Today:
///   • The five-period timeframe selector. Today is **always** "today
///     + this month context." If the user wants to browse Mar 2024,
///     they go to Activity or Insights — those tabs own period
///     browsing. Today owns "now."
///   • Pinned categories. They became Insights' job (categorical
///     composition is an analytical question, not a status question).
///   • Subscription pill. Recurring bills live in Activity (as a
///     filter) and You → Plan (as the manageable list).
///   • Budget Pro teaser. Today should never sell ads. Pro upsell
///     lives on the verdict hero's empty state when relevant, and
///     in You → Pro for everyone else.
struct TodayView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var proManager: ProManager

    /// Resolved verdict for the hero, recomputed off-main whenever
    /// expenses, budgets, or currency change. `nil` until the first
    /// pass lands — the hero shows a calm loading skeleton in that
    /// window rather than flashing wrong numbers.
    @State private var verdict: TodayVerdict? = nil

    /// Per-day amounts + dominant category for the last 7 days
    /// (oldest first). Recomputed off-main on the same hooks as
    /// `verdict`.
    @State private var weekStrip: [WeekStripDay] = []

    /// User-tapped day in the week strip. When `nil`, the strip
    /// shows the 7-day total in its header; when set, it shows the
    /// selected day's date and amount. Tap the same day to deselect.
    @State private var selectedWeekDay: WeekStripDay? = nil

    /// The single most relevant insight to surface today, picked by
    /// `SmartInsightsEngine`. `nil` while computing or when nothing
    /// clears the relevance bar.
    @State private var todayInsight: TodayInsight? = nil

    @State private var recomputeTask: Task<Void, Never>? = nil
    @State private var animateSections = false

    @State private var editingExpense: Expense? = nil

    /// Cross-tab handoff: tapping "See all activity" tells the parent
    /// to switch to the Activity tab. Wired up by `MainTabView`.
    var onSeeAllActivity: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxl) {
                header
                    .modifier(SectionEntrance(order: 0, animate: animateSections))

                verdictHero
                    .modifier(SectionEntrance(order: 1, animate: animateSections))

                if !weekStrip.isEmpty {
                    weekStripSection
                        .modifier(SectionEntrance(order: 2, animate: animateSections))
                }

                recentSection
                    .modifier(SectionEntrance(order: 3, animate: animateSections))

                if let insight = todayInsight {
                    insightCard(for: insight)
                        .modifier(SectionEntrance(order: 4, animate: animateSections))
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.tabBarInset)
        }
        .background(Color.systemBackground)
        .onAppear {
            if !animateSections {
                withAnimation { animateSections = true }
            }
            scheduleRecompute()
        }
        .onChange(of: viewModel.expenses.count) { _, _ in scheduleRecompute() }
        .onChange(of: viewModel.selectedCurrency) { _, _ in scheduleRecompute() }
        .onChange(of: budgetViewModel.budgetProgress) { _, _ in scheduleRecompute() }
        .sheet(item: $editingExpense) { expense in
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
                    var updated = expense
                    updated.title = title
                    updated.amount = amount
                    updated.date = date
                    updated.category = category
                    updated.customCategoryId = customCategoryId
                    updated.notes = notes
                    updated.tags = tags
                    updated.isRefund = isRefund
                    updated.paymentMethod = paymentMethod
                    updated.receiptImagePath = receiptImagePath
                    viewModel.updateExpense(updated)
                }
            )
            .environmentObject(categoryViewModel)
        }
    }

    // MARK: - Header
    //
    // Minimal by design. Greeting + name only.
    //
    // The v1 Home header had Search + Profile shortcuts because Profile
    // was sheet-only (no tab) and search was buried inside All
    // Expenses. Both jobs got promoted to top-level navigation in v2:
    // Activity owns search (in its nav bar), You owns Profile (its own
    // tab). The Today header is now purely identifying — no controls
    // competing with the verdict hero for attention.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(viewModel.userName)
                .font(Theme.Typography.pageTitle)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    // MARK: - Verdict hero
    //
    // The single most important block on the screen. Drives the
    // "am I OK?" judgement without scrolling.
    private var verdictHero: some View {
        Group {
            if let verdict = verdict {
                verdictCard(verdict)
            } else {
                verdictSkeleton
            }
        }
    }

    private var verdictSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 8).fill(Color.tertiarySystemBackground).frame(width: 80, height: 22)
            RoundedRectangle(cornerRadius: 12).fill(Color.tertiarySystemBackground).frame(width: 220, height: 44)
            RoundedRectangle(cornerRadius: 8).fill(Color.tertiarySystemBackground).frame(width: 180, height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    private func verdictCard(_ v: TodayVerdict) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Verdict pill + days-left.
                //
                // When the status is `.neutral` (user has no budgets
                // at all) we deliberately don't show a verdict pill —
                // a verdict implies a target, and there isn't one yet.
                // Instead we show a calm "This month" label so the
                // card still has a header without lying about pace.
                HStack(spacing: Theme.Spacing.sm) {
                    if v.status == .neutral {
                        Text("THIS MONTH")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.6)
                            .foregroundColor(.secondary)
                    } else {
                        verdictPill(v.status)
                    }
                    if let daysLeft = v.daysLeft {
                        Text("\(daysLeft) days left")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Hero number — the spend, made big.
                // Monospaced digits + rounded design = the "premium
                // finance display" treatment Copilot/Monarch use. The
                // digits never jiggle as the value animates.
                Text(viewModel.formattedAmount(v.spent))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .moneyAnimation(amount: v.spent, currency: viewModel.selectedCurrency)

                // Secondary line — what's the spend out of? Falls back
                // to "this month" copy when there's no budget anchor.
                Text(v.secondaryLine(formattedAmount: viewModel.formattedAmount))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Projection line — forward-looking. The audit called
                // this out as the single biggest missing piece on Home.
                if let projection = v.projectionLine(formattedAmount: viewModel.formattedAmount) {
                    Text(projection)
                        .font(.footnote)
                        .foregroundColor(v.status.tint)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
            verdictRing(percentage: v.ringPercentage, status: v.status)
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    private func verdictPill(_ status: TodayVerdict.Status) -> some View {
        Text(status.label.uppercased())
            .font(.caption2.bold())
            .tracking(0.6)
            .foregroundColor(status.tint)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(status.tint.opacity(0.12))
            )
    }

    /// Progress ring on the right of the hero. Empty (gray) when
    /// there's no budget anchor — the hero still works as a
    /// month-pace readout, but without a meaningful percentage we
    /// don't draw a misleading partial fill.
    private func verdictRing(percentage: Double?, status: TodayVerdict.Status) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondarySystemBackground, lineWidth: 8)
                .frame(width: 76, height: 76)
            if let pct = percentage {
                Circle()
                    .trim(from: 0, to: min(max(pct, 0), 1))
                    .stroke(status.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 76, height: 76)
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.Motion.emphasized, value: pct)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            } else {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
    }

    // MARK: - 7-day strip
    //
    // Horizontal sparkline-by-day. Tinted by each day's dominant
    // category so you don't just see "spent more on Wednesday" —
    // you see "spent more on Wednesday, and it was mostly Food."
    private var weekStripSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekStripHeaderTitle)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                Spacer()
                if let amount = weekStripHeaderAmount {
                    Text(viewModel.formattedAmount(amount))
                        .font(Theme.Typography.numericSmall)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .contentTransition(.numericText())
                        .moneyAnimation(amount: amount, currency: viewModel.selectedCurrency)
                }
            }
            ZStack(alignment: .bottom) {
                // Baseline ground line — anchors the bars and gives
                // the strip a clear "floor". Without this the bars
                // floated and the strip felt unfinished.
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.bottom, 20)

                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(weekStrip, id: \.dateKey) { day in
                        weekStripBar(day: day)
                            .onTapGesture {
                                HapticManager.shared.selectionChanged()
                                withAnimation(Theme.Motion.snappy) {
                                    if selectedWeekDay?.dateKey == day.dateKey {
                                        selectedWeekDay = nil
                                    } else {
                                        selectedWeekDay = day
                                    }
                                }
                            }
                    }
                }
            }
            .frame(height: 88)
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    private var weekStripHeaderTitle: String {
        if let selected = selectedWeekDay {
            return Self.selectedDayFormatter.string(from: selected.date)
        }
        return "This week"
    }

    private var weekStripHeaderAmount: Double? {
        if let selected = selectedWeekDay {
            return selected.amount
        }
        guard !weekStrip.isEmpty else { return nil }
        return weekStrip.reduce(0) { $0 + $1.amount }
    }

    private static let selectedDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private func weekStripBar(day: WeekStripDay) -> some View {
        let maxAmount = max(weekStrip.map(\.amount).max() ?? 1, 0.01)
        let normalized = day.amount / maxAmount
        let barHeight = max(3, CGFloat(normalized) * 56)
        let baseTint = day.tint ?? Color.appPrimary.opacity(0.28)
        let isSelected = selectedWeekDay?.dateKey == day.dateKey
        let fill: Color = {
            if day.isToday { return Color.appPrimary }
            if isSelected { return baseTint }
            return baseTint.opacity(selectedWeekDay == nil ? 1 : 0.4)
        }()
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: isSelected ? 22 : 18, height: barHeight)
                .animation(Theme.Motion.snappy, value: isSelected)
                .animation(Theme.Motion.snappy, value: selectedWeekDay?.dateKey)
            Text(day.shortLabel)
                .font(.system(size: 11, weight: day.isToday ? .semibold : .regular, design: .rounded))
                .foregroundColor(day.isToday ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Recent (top 3)
    //
    // Verification, not browsing. The user uses this row to remember
    // "wait, did I log that?" or "did I get the amount right on that
    // last entry?" — anything more belongs in Activity.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Recent")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    HapticManager.shared.lightTap()
                    onSeeAllActivity()
                }) {
                    HStack(spacing: 2) {
                        Text("See all")
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(Theme.Typography.caption.weight(.medium))
                    .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.expenses.isEmpty {
                emptyRecentBlock
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(viewModel.expenses.prefix(3)), id: \.id) { expense in
                        ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
                            .equatable()
                            .onTapGesture {
                                HapticManager.shared.lightTap()
                                editingExpense = expense
                            }
                    }
                }
            }
        }
    }

    private var emptyRecentBlock: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No expenses yet")
                .font(Theme.Typography.rowTitle)
                .foregroundColor(.primary)
            Text("Tap + to log your first one.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .cardSurface()
    }

    // MARK: - Insight card
    //
    // One observation, picked by the existing SmartInsightsEngine
    // (or a calm fallback). Never more than one — the audit was
    // explicit that "card sprawl" was eroding the screen.
    private func insightCard(for insight: TodayInsight) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: insight.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(insight.tint)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(insight.tint.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.headline)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Text(insight.detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    // MARK: - Recompute pipeline
    //
    // Mirrors the Phase G pattern: snapshot @MainActor data, hop to a
    // detached task for the O(N) math, single-burst commit on the
    // main actor when done. Debounce is small because Today already
    // benefits from the upstream filter pipeline's debounce.
    private func scheduleRecompute() {
        recomputeTask?.cancel()

        let expensesSnapshot = viewModel.expenses
        let currentCurrency = viewModel.selectedCurrency
        let overallBudget = budgetViewModel.activeBudgets.first { $0.categoryFilter.isOverall }
        let overallProgress = overallBudget.map { budgetViewModel.progress(for: $0) }
        let activeBudgets = budgetViewModel.activeBudgets
        let activeProgress = activeBudgets.map { budgetViewModel.progress(for: $0) }
        let now = Date()
        let categoryMap: [UUID: (name: String, color: String)] = Dictionary(
            uniqueKeysWithValues: categoryViewModel.customCategories.map { ($0.id, (name: $0.name, color: $0.colorName)) }
        )

        recomputeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let result: (verdict: TodayVerdict, weekStrip: [WeekStripDay], insight: TodayInsight?) =
                await Task.detached(priority: .userInitiated) {
                    let v = TodayVerdict.compute(
                        expenses: expensesSnapshot,
                        overallProgress: overallProgress,
                        categoryProgressList: activeProgress,
                        currency: currentCurrency,
                        now: now
                    )
                    let strip = WeekStripDay.computeLast7Days(
                        from: expensesSnapshot,
                        customCategories: categoryMap,
                        now: now
                    )
                    let insight = TodayInsight.pick(from: expensesSnapshot, verdict: v, now: now)
                    return (v, strip, insight)
                }.value

            guard !Task.isCancelled else { return }
            verdict = result.verdict
            weekStrip = result.weekStrip
            todayInsight = result.insight
        }
    }
}

// MARK: - Verdict model
//
// Pure value type — the result of one recompute pass. All math runs
// off-main. The view just renders. Keeping this separate from the
// view makes it trivial to unit-test later.

struct TodayVerdict: Sendable, Equatable {
    enum Status: Equatable {
        case onTrack, tight, over, neutral

        var label: String {
            switch self {
            case .onTrack: return "On Track"
            case .tight:   return "Tight"
            case .over:    return "Over"
            case .neutral: return "This Month"
            }
        }

        /// Color isn't `@MainActor`-bound — it's a value type lookup —
        /// but `Color` doesn't conform to `Sendable` cleanly in Swift 6
        /// across all SDK versions. Resolved at render time in the
        /// view rather than stored on the verdict.
        @MainActor var tint: Color {
            switch self {
            case .onTrack: return .green
            case .tight:   return .orange
            case .over:    return .red
            case .neutral: return .secondary
            }
        }
    }

    let status: Status
    let spent: Double
    let limit: Double?            // nil when there's no budget anchor
    let projectedTotal: Double?   // nil when we can't safely project
    let daysLeft: Int?
    let ringPercentage: Double?   // nil → ring renders as empty placeholder

    /// Secondary copy under the hero number — depends on whether we
    /// have a budget anchor.
    func secondaryLine(formattedAmount: (Double) -> String) -> String {
        if let limit = limit {
            return "of \(formattedAmount(limit)) this month"
        }
        return "spent this month"
    }

    /// Projection footer — only when we have enough data to be honest
    /// about the prediction.
    func projectionLine(formattedAmount: (Double) -> String) -> String? {
        guard let projection = projectedTotal else { return nil }
        if let limit = limit {
            let delta = projection - limit
            if delta > 0 {
                return "At this pace → \(formattedAmount(projection)) by month-end (\(formattedAmount(delta)) over)"
            }
            return "At this pace → \(formattedAmount(projection)) by month-end"
        }
        return "At this pace → \(formattedAmount(projection)) by month-end"
    }

    // MARK: - Compute
    static func compute(
        expenses: [Expense],
        overallProgress: BudgetViewModel.BudgetProgress?,
        categoryProgressList: [BudgetViewModel.BudgetProgress],
        currency: Expense.Currency,
        now: Date
    ) -> TodayVerdict {
        // Case 1: explicit overall budget → use it directly.
        if let p = overallProgress {
            return verdict(from: p)
        }
        // Case 2: no overall, but category budgets exist → aggregate
        // them so the user still gets a meaningful "am I OK?" readout.
        // We sum limits and spends and use the longest daysRemaining
        // as the period anchor (typically they're all monthly).
        if !categoryProgressList.isEmpty {
            let limit = categoryProgressList.reduce(0) { $0 + $1.limit }
            let spent = categoryProgressList.reduce(0) { $0 + $1.spent }
            let daysRemaining = categoryProgressList.map(\.daysRemaining).max() ?? 0
            let totalDays = categoryProgressList.map(\.totalDays).max() ?? 30
            let elapsed = max(1, totalDays - daysRemaining)
            let dailyPace = spent / Double(elapsed)
            let projection = dailyPace * Double(totalDays)
            let pct = limit > 0 ? spent / limit : 0
            let status: Status = {
                if projection > limit * 1.05 { return .over }
                if pct > 0.9 || projection > limit * 0.95 { return .tight }
                return .onTrack
            }()
            return TodayVerdict(
                status: status,
                spent: spent,
                limit: limit,
                projectedTotal: projection,
                daysLeft: daysRemaining,
                ringPercentage: limit > 0 ? min(max(spent / limit, 0), 1) : nil
            )
        }
        // Case 3: no budgets → degrade to month-so-far + projection,
        // no verdict pill judgment (we don't know what "ok" means for
        // a user who hasn't told us their target).
        let cal = Calendar.current
        let monthInterval = cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)
        let spent = expenses
            .filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }
            .reduce(0) { $0 + $1.signedAmount }
        let totalDays = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysElapsed = max(1, cal.dateComponents([.day], from: monthInterval.start, to: now).day.map { $0 + 1 } ?? 1)
        let daysRemaining = max(0, totalDays - daysElapsed)
        let dailyPace = spent / Double(daysElapsed)
        let projection = daysElapsed >= 3 ? dailyPace * Double(totalDays) : nil
        return TodayVerdict(
            status: .neutral,
            spent: max(spent, 0),
            limit: nil,
            projectedTotal: projection,
            daysLeft: daysRemaining,
            ringPercentage: nil
        )
    }

    private static func verdict(from p: BudgetViewModel.BudgetProgress) -> TodayVerdict {
        let projection = p.projectedTotal
        let status: Status = {
            if projection > p.limit * 1.05 || p.status == .exceeded { return .over }
            if p.percentage > 0.9 || projection > p.limit * 0.95 { return .tight }
            return .onTrack
        }()
        return TodayVerdict(
            status: status,
            spent: p.spent,
            limit: p.limit,
            projectedTotal: projection,
            daysLeft: p.daysRemaining,
            ringPercentage: p.limit > 0 ? min(max(p.spent / p.limit, 0), 1) : nil
        )
    }
}

// MARK: - Week strip model

struct WeekStripDay: Sendable, Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
    /// Hex-ish color name (resolved against `Color.forCategory` at
    /// render). `nil` when the day has no spend.
    let colorName: String?
    let isToday: Bool

    var dateKey: TimeInterval { date.timeIntervalSince1970 }

    var shortLabel: String {
        Self.shortFormatter.string(from: date)
    }

    @MainActor
    var tint: Color? {
        colorName.map { Color.forCategory($0) }
    }

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // M T W T F S S
        return f
    }()

    /// Build the last-7-days strip, oldest first, today included.
    static func computeLast7Days(
        from expenses: [Expense],
        customCategories: [UUID: (name: String, color: String)],
        now: Date
    ) -> [WeekStripDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let startWindow = cal.date(byAdding: .day, value: -6, to: today) ?? today

        // Bucket expenses by day, tracking spend totals per category to
        // find each day's dominant category for tinting.
        var byDay: [Date: (total: Double, byCategory: [String: Double])] = [:]
        for e in expenses where e.date >= startWindow && e.date < cal.date(byAdding: .day, value: 1, to: today)! {
            let day = cal.startOfDay(for: e.date)
            let signed = max(e.signedAmount, 0)  // refunds don't tint
            var bucket = byDay[day] ?? (0, [:])
            bucket.total += signed
            // Resolve a color key. Custom categories use their stored
            // colorName; default categories use the enum's color.
            let key: String
            if e.category == .custom, let id = e.customCategoryId, let cat = customCategories[id] {
                key = cat.color
            } else {
                key = e.category.color
            }
            bucket.byCategory[key, default: 0] += signed
            byDay[day] = bucket
        }

        var result: [WeekStripDay] = []
        for offset in 0...6 {
            let date = cal.date(byAdding: .day, value: -6 + offset, to: today) ?? today
            let bucket = byDay[date] ?? (0, [:])
            let dominant = bucket.byCategory.max(by: { $0.value < $1.value })?.key
            result.append(WeekStripDay(
                date: date,
                amount: bucket.total,
                colorName: dominant,
                isToday: cal.isDate(date, inSameDayAs: today)
            ))
        }
        return result
    }
}

// MARK: - Local entrance motion

/// Cascading spring-based entrance, mirrored from the existing
/// HomeView / StatisticsView / SubscriptionsView so the whole app
/// shares one "section appears" motion. Kept `private` per the
/// app's existing convention — when v2 promotes this to a shared
/// modifier (Phase R6), it'll move into `Design/ViewModifiers.swift`.
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

// MARK: - Insight model
//
// The Today insight is intentionally lightweight — a heuristic pick
// from the expense list, not a full SmartInsightsEngine run. The
// goal is "always have something kind/relevant to say," not "do
// deep analytics" (Insights tab owns analytics).

struct TodayInsight: Sendable, Equatable {
    let icon: String
    let headline: String
    let detail: String
    /// The view resolves the actual Color at render — `Color` doesn't
    /// cross actor boundaries cleanly in Swift 6 across SDK versions.
    let tintKind: TintKind

    enum TintKind: Equatable {
        case primary, positive, warning

        @MainActor var color: Color {
            switch self {
            case .primary:  return .appPrimary
            case .positive: return .green
            case .warning:  return .orange
            }
        }
    }

    @MainActor var tint: Color { tintKind.color }

    static func pick(
        from expenses: [Expense],
        verdict: TodayVerdict,
        now: Date
    ) -> TodayInsight? {
        guard !expenses.isEmpty else {
            return TodayInsight(
                icon: "sparkles",
                headline: "Log your first expense",
                detail: "Tap the + button below. Today's verdict will appear here once you have a few entries.",
                tintKind: .primary
            )
        }

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let monthInterval = cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)

        // Heuristic 1: spent today already? Celebrate or warn based on
        // recent average.
        let todaySpend = expenses
            .filter { cal.isDate($0.date, inSameDayAs: todayStart) }
            .reduce(0) { $0 + max($1.signedAmount, 0) }
        let weekSpend = expenses
            .filter { $0.date >= weekStart && $0.date < todayStart }
            .reduce(0) { $0 + max($1.signedAmount, 0) }
        let weekDailyAvg = weekSpend / 7
        if todaySpend > weekDailyAvg * 1.6, weekDailyAvg > 0 {
            return TodayInsight(
                icon: "exclamationmark.triangle",
                headline: "Higher spending today",
                detail: "You've spent more today than your last-7-days average. Heads up before another impulse buy.",
                tintKind: .warning
            )
        }
        if todaySpend == 0 {
            return TodayInsight(
                icon: "leaf.fill",
                headline: "No-spend day so far",
                detail: "Nothing logged yet today. That's a small win.",
                tintKind: .positive
            )
        }

        // Heuristic 2: month is on pace?
        if let projection = verdict.projectedTotal, let limit = verdict.limit, projection < limit * 0.85 {
            return TodayInsight(
                icon: "checkmark.seal.fill",
                headline: "Tracking under budget",
                detail: "At this pace you'll finish the month with breathing room.",
                tintKind: .positive
            )
        }

        // Default heuristic: largest expense this month so far.
        let monthMax = expenses
            .filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }
            .max(by: { $0.signedAmount < $1.signedAmount })
        if let biggest = monthMax {
            return TodayInsight(
                icon: "chart.line.uptrend.xyaxis",
                headline: "Biggest expense this month",
                detail: "\(biggest.title) — \(biggest.category.displayName).",
                tintKind: .primary
            )
        }

        return nil
    }
}
