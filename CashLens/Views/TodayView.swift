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
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel

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

    /// No-spend streak metrics, recomputed off-main alongside the
    /// verdict. Drives the flame chip in the week-strip header — the
    /// same `StreakCalculator` output the widget shows, so app and
    /// widget always agree. `nil` until the first pass lands.
    @State private var streak: StreakCalculator.StreakSummary? = nil

    /// One-shot scale pop on the streak chip when the current streak
    /// *increments* (design review: "when the streak increments, the
    /// flame chip scale-pops once"). Never loops.
    @State private var streakPop = false

    /// The month to offer a recap for (start of the *previous* month),
    /// set during the first few days of a new month while the user
    /// hasn't viewed that recap yet. `nil` hides the card. Evaluated
    /// inside the recompute pass because it needs the (hydrated)
    /// expense array to confirm the month actually has data.
    @State private var recapMonth: Date? = nil
    @State private var showingRecapSheet = false

    @State private var recomputeTask: Task<Void, Never>? = nil
    @State private var animateSections = false
    /// Guards the one-time `onAppear` recompute — see the comment there.
    @State private var hasAppearedOnce = false

    /// Drives the gentle "over budget" pulse on the verdict ring's
    /// outer glow. Pulses three times, then settles into a calm
    /// static glow (the review flagged the previous `repeatForever`
    /// shadow animation: per-frame invalidation, forever, on the
    /// app's most-visited screen — a real battery/ProMotion cost for
    /// exactly the users who check most often).
    @State private var overRingPulse: Double = 0

    /// True once the verdict ring has played its first-appear trim
    /// animation (0 → value). Without this the ring snapped straight
    /// to its final trim on first render and only animated on later
    /// changes.
    @State private var verdictRingAppeared = false

    @State private var editingExpense: Expense? = nil

    /// Drives the "Manage budgets" sheet opened from the budgets
    /// section header or any of its rows. Reuses `BudgetListView`
    /// (the same sheet Profile uses) so there's one canonical
    /// budget-management surface app-wide.
    @State private var showingBudgetList = false

    /// Per-budget snapshots used by the stacked-budgets card when
    /// the user has 2+ active budgets. Recomputed off-main on the
    /// same hook as `verdict`, populated even when there are 0 or
    /// 1 budgets (the count drives the layout decision in
    /// `budgetsSection`).
    @State private var budgetSnapshots: [BudgetSnapshot] = []

    /// Next few subscriptions due in the upcoming window. Driven
    /// by `recomputeUpcomingBills()` whenever the subscription list
    /// changes. `nil` until the first compute pass; an empty array
    /// means "no upcoming bills in the window" (we render nothing).
    @State private var upcomingBills: [UpcomingBill]? = nil

    /// Period the two top-of-screen summary cards display. Persists
    /// across app launches via UserDefaults so the user doesn't have
    /// to re-select their preferred lens every session.
    @State private var summaryPeriod: SummaryPeriod = SummaryPeriod.restored()

    /// User-customizable layout for everything below the pinned
    /// verdict card. Loaded once from UserDefaults; the customize
    /// sheet edits these bindings live (the screen re-renders behind
    /// the sheet) and persists on every change.
    @State private var sectionOrder: [TodaySectionID]
    @State private var hiddenSections: Set<TodaySectionID>
    @State private var showingCustomizeSheet = false

    init(
        onSeeAllActivity: @escaping () -> Void = {},
        onOpenInsights: @escaping () -> Void = {},
        onRequestAddExpense: @escaping () -> Void = {}
    ) {
        self.onSeeAllActivity = onSeeAllActivity
        self.onOpenInsights = onOpenInsights
        self.onRequestAddExpense = onRequestAddExpense
        let layout = TodaySectionID.loadLayout()
        _sectionOrder = State(initialValue: layout.order)
        _hiddenSections = State(initialValue: layout.hidden)
    }

    /// Computed stats for the selected `summaryPeriod`. `nil` while
    /// the first pass is in flight; both cards show calm placeholder
    /// values in that window rather than flashing wrong numbers.
    @State private var summary: SummaryStats? = nil

    /// Cross-tab handoff: tapping "See all activity" tells the parent
    /// to switch to the Activity tab. Wired up by `MainTabView`.
    var onSeeAllActivity: () -> Void = {}

    /// Cross-tab handoff: tapping the chevron on the "This week"
    /// header jumps to the Insights tab so the user can drill into
    /// the full chart set for the same window. Wired up by
    /// `MainTabView`. Also posts a notification before the switch
    /// so `StatisticsView` can preselect the `.week` timeframe and
    /// land the user exactly where they expect.
    var onOpenInsights: () -> Void = {}

    /// Bubbles up to `MainTabView` so the first-run hero's CTA button
    /// presents the same Add Expense sheet the FAB does. We don't own
    /// the sheet locally because the FAB and its sheet already live on
    /// `MainTabView` — funnelling all "open add expense" paths through
    /// one owner keeps presentation behaviour consistent.
    var onRequestAddExpense: () -> Void = {}

    /// Sheet-presentation flag for the Subscriptions manager. The
    /// chevron on the "Upcoming Subscriptions" header toggles this.
    /// We present a sheet (not a tab switch) because Subscriptions
    /// isn't a tab in v2 — it lives under You → Subscriptions, and
    /// the sheet is the same one ProfileView uses, keeping the
    /// presentation behaviour identical across entry points.
    @State private var showingSubscriptions: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxl) {
                header
                    .modifier(SectionEntrance(order: 0, animate: animateSections))

                // Time-boxed recap invitation — "Your June recap is
                // ready" — shown during the first few days of a new
                // month until the user opens the recap (from here or
                // from Insights). Sits directly under the header so
                // the month-end moment gets prime placement while it
                // lasts, then disappears for the rest of the month.
                if let recapMonth {
                    recapReadyCard(for: recapMonth)
                        .modifier(SectionEntrance(order: 1, animate: animateSections))
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Cold-start centering: when the user has no expenses
                // yet, the only thing below the header is the
                // first-run hero card. A flexible spacer above and
                // below pushes it to the visible vertical centre of
                // the screen (paired with the `coldStartFillsScreen`
                // modifier at the bottom of this VStack, which pins
                // the VStack height to the scrollview's visible
                // extent so the spacers actually have room to
                // expand). Non-cold-start renders are completely
                // unaffected.
                if viewModel.expenses.isEmpty {
                    Spacer(minLength: 0)
                }

                // ONE adaptive Budgets surface that scales from 0
                // budgets (month-pace card) → 1 budget (full hero) →
                // 2+ budgets (stacked list with per-budget rows).
                // No more "hero + breakdown" duplication.
                //
                // Order: verdict FIRST, summary second. The design
                // review flagged that v2 had quietly inverted the
                // screen's own contract ("am I OK?" is the first
                // pixel, per the doc comment above) by stacking the
                // Summary tiles' 28pt totals above the 46pt verdict
                // hero. The verdict is back on top.
                budgetsSection
                    .modifier(SectionEntrance(order: 1, animate: animateSections))
                    .sectionScrollTransition()

                // Bottom-side spacer for the cold-start centring
                // described above. Matches the top spacer 1:1 so the
                // hero lands at the true vertical middle of the
                // available space between header and tab bar.
                if viewModel.expenses.isEmpty {
                    Spacer(minLength: 0)
                }

                // Everything below the verdict renders in the user's
                // chosen order (Customize Today sheet), with hidden
                // sections dropped. `visibleSections` also applies
                // the per-section content gates (cold start, empty
                // upcoming window, nil insight) so a section with
                // nothing to say never renders an empty shell.
                ForEach(Array(visibleSections.enumerated()), id: \.element) { index, section in
                    sectionView(for: section)
                        .modifier(SectionEntrance(order: index + 2, animate: animateSections))
                        .sectionScrollTransition()
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.tabBarInset)
            // Animate live layout edits made from the Customize
            // sheet — sections glide to their new slot / fade out
            // behind the half-height sheet instead of snapping.
            .animation(Theme.Motion.emphasized, value: sectionOrder)
            .animation(Theme.Motion.emphasized, value: hiddenSections)
            // Conditionally pin the VStack height to the scrollview's
            // visible extent ONLY in cold-start. With a real expense
            // list this stays inactive so the normal scroll behaviour,
            // section heights, and overflow are completely unchanged.
            .modifier(ColdStartFillsScreenModifier(active: viewModel.expenses.isEmpty))
        }
        .background(Color.systemBackground)
        .onAppear {
            if !animateSections {
                withAnimation { animateSections = true }
            }
            // First appearance only. The view stays mounted while other
            // tabs are selected, so the `onReceive`/`onChange` listeners
            // below keep everything current in the background — an
            // unconditional recompute here just re-ran the same work on
            // every tab revisit (extra main-thread churn per switch).
            guard !hasAppearedOnce else { return }
            hasAppearedOnce = true
            scheduleRecompute()
            recomputeUpcomingBills()
        }
        // PERF: `onReceive` instead of `onChange(of: viewModel.expenses)`.
        // `onChange` retains the previous `[Expense]` and runs a full O(N)
        // `==` on the main thread per publish — tens of milliseconds at
        // 50k rows. `onReceive` skips the comparison entirely; same-count
        // mutations (edits, toggles) still trigger, because *every*
        // publish triggers. Redundant publishes are already suppressed at
        // the source (`loadExpensesAsync` diff-gates its publish) and any
        // residual double-fire is absorbed by `scheduleRecompute`'s 80ms
        // debounce. Same pattern AllExpensesView uses.
        .onReceive(viewModel.$expenses) { _ in scheduleRecompute() }
        .onChange(of: viewModel.selectedCurrency) { _, _ in scheduleRecompute() }
        .onChange(of: budgetViewModel.budgetProgress) { _, _ in scheduleRecompute() }
        .onReceive(subscriptionViewModel.$subscriptions) { _ in recomputeUpcomingBills() }
        .onChange(of: summaryPeriod) { _, newPeriod in
            // Persist immediately so the choice survives a kill+relaunch.
            UserDefaults.standard.set(newPeriod.rawValue, forKey: SummaryPeriod.userDefaultsKey)
            scheduleRecompute()
        }
        .sheet(isPresented: $showingRecapSheet, onDismiss: {
            // The sheet's `onAppear` already persisted "seen" for this
            // month — clear the local card with a calm fade.
            withAnimation(Theme.Motion.emphasized) { recapMonth = nil }
        }) {
            if let recapMonth {
                MonthlyRecapSheet(month: recapMonth)
            }
        }
        .sheet(isPresented: $showingCustomizeSheet) {
            TodayCustomizeView(
                sectionOrder: $sectionOrder,
                hiddenSections: $hiddenSections
            )
        }
        .sheet(isPresented: $showingBudgetList) {
            // Env objects (ExpenseViewModel / CategoryViewModel /
            // BudgetViewModel / ProManager) all inherit automatically
            // from the App root, same pattern Profile uses for this
            // exact sheet.
            BudgetListView()
        }
        .sheet(isPresented: $showingSubscriptions) {
            // No NavigationView wrapper — `SubscriptionsView` ships
            // its own custom page header (title + Add) and presents
            // its own Add/Edit sheets internally, so wrapping it
            // here would only stack an empty nav bar on top and
            // re-introduce the legacy ~50pt gap above the title.
            SubscriptionsView()
                .presentationDragIndicator(.visible)
        }
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
    // Minimal by design: greeting + name, plus one quiet trailing
    // control — the Customize Today entry point. It uses the same
    // 36pt material-disc language as `SheetCloseButton` so it reads
    // as chrome, not content, and never competes with the verdict
    // hero for attention.
    //
    // The v1 Home header had Search + Profile shortcuts because Profile
    // was sheet-only (no tab) and search was buried inside All
    // Expenses. Both jobs got promoted to top-level navigation in v2:
    // Activity owns search (in its nav bar), You owns Profile (its own
    // tab).
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(viewModel.userName)
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                HapticManager.shared.lightTap()
                showingCustomizeSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize Today")
        }
    }

    // MARK: - Section routing
    //
    // The user's saved order, filtered down to sections that (a)
    // aren't hidden and (b) actually have content right now. The
    // content gates preserve the original per-section skip rules:
    // everything hides on a cold start (the first-run hero owns that
    // moment), Upcoming needs bills in the window, Insight needs a
    // non-nil pick.
    private var visibleSections: [TodaySectionID] {
        sectionOrder.filter { section in
            guard !hiddenSections.contains(section) else { return false }
            switch section {
            case .summary:
                return !viewModel.expenses.isEmpty
            case .upcoming:
                return !(upcomingBills ?? []).isEmpty
            case .weekStrip:
                return !viewModel.expenses.isEmpty && !weekStrip.isEmpty
            case .recent:
                return !viewModel.expenses.isEmpty
            case .insight:
                return !viewModel.expenses.isEmpty && todayInsight != nil
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: TodaySectionID) -> some View {
        switch section {
        case .summary:
            summarySection
        case .upcoming:
            if let upcoming = upcomingBills, !upcoming.isEmpty {
                upcomingBillsSection(upcoming)
            }
        case .weekStrip:
            weekStripSection
        case .recent:
            recentSection
        case .insight:
            if let insight = todayInsight {
                insightCard(for: insight)
            }
        }
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

    // MARK: - Monthly recap invitation

    /// "Your June recap is ready" — a slim, tinted, whole-card-tappable
    /// invitation. Deliberately quieter than the verdict hero (single
    /// row, sparkles medallion, chevron) so it reads as an invitation,
    /// not an alert. Tapping opens `MonthlyRecapSheet`; viewing marks
    /// the month as seen, which hides the card until next month.
    private func recapReadyCard(for month: Date) -> some View {
        Button {
            HapticManager.shared.mediumTap()
            showingRecapSheet = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(Self.recapMonthFormatter.string(from: month)) recap is ready")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(.primary)
                    Text("See where last month went — and share it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }
            .padding(Theme.Spacing.lg)
            .cardSurface(
                fill: Color.appPrimary.opacity(0.06),
                stroke: Color.appPrimary.opacity(0.18)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your \(Self.recapMonthFormatter.string(from: month)) recap is ready")
        .accessibilityHint("Opens your month in review")
    }

    private static let recapMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    // MARK: - Summary section
    //
    // Two glance cards at the top: Total Spent + Top Category, both
    // tied to a shared period picker (Today / This Week / This Month
    // / All Time). The pair answers "where did my money go?" — a
    // different question from Budgets' "am I OK against my plan?",
    // so the two sections sit happily next to each other without
    // duplicating information.
    //
    // Why two cards (not one): keeping them split lets each card
    // stay glance-only. One row of giant text + a second row of
    // smaller supporting copy on each. Two cards side by side feel
    // like dashboard tiles; one wide card with both stats would
    // collapse into a "stats list" and lose the at-a-glance quality.
    //
    // Why default to "This Month": Today/This Week often read empty
    // in the morning, while month-so-far is always meaningful.
    // The user's choice persists across launches via UserDefaults
    // so the cards always come back to their preferred lens.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Summary")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                Spacer()
                summaryPeriodPicker
            }

            HStack(spacing: Theme.Spacing.md) {
                totalSpentCard
                topCategoryCard
            }
        }
    }

    /// Single picker that drives both summary cards. Tappable chip
    /// in the section header (same accent + chevron treatment as
    /// other "see more" affordances on Today) opens a native Menu.
    private var summaryPeriodPicker: some View {
        Menu {
            ForEach(SummaryPeriod.allCases, id: \.self) { period in
                Button(action: {
                    HapticManager.shared.selectionChanged()
                    summaryPeriod = period
                }) {
                    if period == summaryPeriod {
                        Label(period.displayName, systemImage: "checkmark")
                    } else {
                        Text(period.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(summaryPeriod.displayName)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(Theme.Typography.caption.weight(.medium))
            .foregroundColor(.appPrimary)
        }
    }

    /// Left card: total positive spend in the selected period.
    /// Hero amount with a small icon-medallion'd label above and a
    /// supporting "N expenses" line below.
    private var totalSpentCard: some View {
        let total = summary?.totalSpent ?? 0
        let count = summary?.transactionCount ?? 0
        return summaryStatCard(
            medallion: (icon: "chart.bar.fill", color: .appPrimary),
            label: "TOTAL SPENT",
            amount: total,
            supporting: count == 1 ? "1 expense" : "\(count) expenses",
            isEmpty: false
        )
    }

    /// Right card: category that consumed the largest share of the
    /// period's spend. Same skeleton as Total Spent so the two cards
    /// read as a matching pair — only the label, medallion tint, and
    /// supporting line differ.
    @ViewBuilder
    private var topCategoryCard: some View {
        if let amount = summary?.topCategoryAmount, amount > 0,
           let name = summary?.topCategoryName,
           let icon = summary?.topCategoryIcon,
           let colorName = summary?.topCategoryColor {
            let pct = Int(((summary?.topCategoryPercentage ?? 0) * 100).rounded())
            summaryStatCard(
                medallion: (icon: icon, color: Color.forCategory(colorName)),
                label: "TOP CATEGORY",
                amount: amount,
                supporting: "\(name) · \(pct)%",
                isEmpty: false
            )
        } else {
            // Period had no spend (e.g. user picked "Today" before
            // logging anything). Calm dashed placeholder that keeps
            // the card structurally identical to the Total Spent
            // card next to it.
            summaryStatCard(
                medallion: (icon: "square.stack.3d.up.fill", color: .secondary),
                label: "TOP CATEGORY",
                amount: nil,
                supporting: "No expenses in period",
                isEmpty: true
            )
        }
    }

    /// Shared skeleton for both summary tiles. Keeps the two cards
    /// pixel-aligned: same eyebrow row, same hero-amount font, same
    /// supporting line, same padding. Anything that needs to differ
    /// (medallion icon/tint, label, amount, supporting copy) is
    /// passed in. Centralising the layout here is what guarantees
    /// they always look like a matched pair, even as we tweak font
    /// sizes or spacing later.
    private func summaryStatCard(
        medallion: (icon: String, color: Color),
        label: String,
        amount: Double?,
        supporting: String,
        isEmpty: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Eyebrow row: icon medallion + uppercase label. Reuses
            // the same medallion shape as the budget rows so the
            // visual language stays consistent across the screen.
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(medallion.color.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Image(systemName: medallion.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(medallion.color)
                }
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundColor(.secondary)
            }

            // Hero amount. 28pt rounded bold is big enough to dominate
            // the tile (no more sea of white space) while still fitting
            // a 6-digit value side-by-side with the second card.
            // `minimumScaleFactor(0.5)` keeps it from truncating if
            // the user has a very large total in a wide currency.
            if let amount = amount {
                Text(viewModel.formattedAmount(amount))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .moneyAnimation(amount: amount, currency: viewModel.selectedCurrency)
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(supporting)
                .font(.caption)
                .foregroundColor(isEmpty ? .secondary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    // MARK: - Budgets section (unified)
    //
    // ONE adaptive surface that handles every budget count:
    //   • 0 budgets → a calm "This Month" pace card (the neutral
    //     verdict — month spent + projection + quick stats, no
    //     judgement because we don't know the user's target)
    //   • 1 budget → the full hero card (big SPENT number, ring,
    //     projection chip, quick stats footer)
    //   • 2+ budgets → a stacked card listing each budget as a
    //     compact row with name / amounts / mini progress bar /
    //     remaining-or-over readout, topped by a worst-status pill
    //     and footed by the same quick stats line
    //
    // The earlier "verdict hero + separate breakdown section"
    // duplicated data when the hero was just showing one of the
    // budgets again. Collapsing both into one section means each
    // budget shows up exactly once.
    private var budgetsSection: some View {
        Group {
            if viewModel.expenses.isEmpty {
                // First-run empty state is its own self-contained
                // hero — adding a "Budgets" header above it would
                // contradict the friendly "welcome" framing.
                firstRunHero
            } else if let verdict = verdict {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    budgetsSectionHeader
                    if budgetSnapshots.count >= 2 {
                        stackedBudgetsCard(verdict)
                    } else {
                        verdictCard(verdict)
                    }
                }
            } else {
                verdictSkeleton
            }
        }
    }

    /// Single canonical section header for the Budgets surface. Title
    /// reads "Budgets" when the user has budgets configured, "This
    /// Month" when they don't (the card below is a month-pace readout
    /// in that case, not a budget readout). Trailing slot is the
    /// Manage shortcut, shown only when there's something to manage.
    ///
    /// Lives outside the card to match the Recent / Upcoming pattern —
    /// the screen-wide rule is: section title above the card, never
    /// inside it.
    private var budgetsSectionHeader: some View {
        HStack {
            Text(budgetSnapshots.isEmpty ? "This Month" : "Budgets")
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(.primary)
            Spacer()
            // One header chrome, two labels. With budgets configured
            // we offer `Manage →` (open the list). Without any, we
            // offer `+ Set →` (same destination, but the leading
            // glyph + verb sells the create action). Lives in the
            // header — not the card body — so the no-budget hero
            // doesn't have to make room for a CTA chip.
            Button(action: {
                HapticManager.shared.lightTap()
                showingBudgetList = true
            }) {
                HStack(spacing: 3) {
                    if budgetSnapshots.isEmpty {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                        Text("Set Budget")
                    } else {
                        Text("Manage")
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(Theme.Typography.caption.weight(.medium))
                .foregroundColor(.appPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(budgetSnapshots.isEmpty ? "Set a budget" : "Manage budgets")
        }
    }

    /// Shown when the user has no expenses yet.
    ///
    /// Minimalist, centered empty state: a single softly-pulsing
    /// sparkle icon, a confident headline, one short supporting line,
    /// and one primary CTA. No eyebrow label, no microcopy, no
    /// secondary "feature preview" card — the goal is to give the
    /// user exactly one obvious next action without competing
    /// elements. The CTA opens the same Add Expense sheet the FAB
    /// does so the user never has to hunt for the + button.
    private var firstRunHero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            FirstRunSparkleIcon()

            VStack(spacing: Theme.Spacing.sm) {
                Text("Start with one expense.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Log it once. CashLens does the rest.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                HapticManager.shared.mediumTap()
                onRequestAddExpense()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Log your first expense")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md + 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(LinearGradient.appDuotone)
                )
                .primaryGlow(strength: 0.28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log your first expense")
            .accessibilityHint("Opens the add expense screen")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxl + 4)
        .cardSurface(radius: Theme.Radius.hero)
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
        .skeletonShimmer()
    }

    private func verdictCard(_ v: TodayVerdict) -> some View {
        // Pull the single-budget snapshot up front so the identity
        // row and the hero row can both read from it without
        // recomputing. `nil` means "0 budgets" (neutral state) —
        // verdictCard is only ever invoked with 0 or 1 snapshots;
        // the 2+ case routes through `stackedBudgetsCard`.
        let solo: BudgetSnapshot? = budgetSnapshots.count == 1 ? budgetSnapshots.first : nil

        return VStack(alignment: .leading, spacing: 0) {
            // Top status row: verdict pill + days-left chip. Hidden
            // entirely in the neutral / no-budget state so the card
            // doesn't reserve a row for content that isn't there.
            if v.status != .neutral {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    verdictPill(v.status)
                    if let daysLeft = v.daysLeft {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(daysLeft) days left")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Budget-identity row — only when there's exactly one
            // budget. Without this, the single-budget verdict card
            // didn't tell the user *which* budget they were looking
            // at (vs the stacked card which labels every row). Uses
            // the same medallion + name treatment `stackedBudgetRow`
            // does so single ↔ multi budget views feel like the
            // same component family.
            if let snap = solo {
                singleBudgetIdentityRow(snap)
                    .padding(.top, Theme.Spacing.md)
            }

            // Hero row — hero block on the left, ring vertically
            // centred on the right. Previously the ring sat in the
            // top-right corner of the card *above* the hero, which
            // left a large empty slot to the right of the hero
            // amount (a 72pt ring on top of a ~120pt hero stack
            // = ~50pt of dead corner). Pairing them in one
            // centre-aligned HStack collapses that white space.
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("SPENT")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundColor(.secondary)

                    Text(viewModel.formattedAmount(v.spent))
                        .font(Theme.Typography.heroNumeric)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .moneyAnimation(amount: v.spent, currency: viewModel.selectedCurrency)

                    Text(v.secondaryLine(formattedAmount: viewModel.formattedAmount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if v.ringPercentage != nil {
                    verdictRing(percentage: v.ringPercentage, status: v.status)
                }
            }
            // Drop the breathing room above the hero in the no-
            // budget state — neither the top status row nor the
            // identity row exists there, so the padding would just
            // hang as ~16pt of dead space at the top of the card.
            .padding(.top, v.status != .neutral ? Theme.Spacing.lg : 0)

            // Projection chip — forward-looking. The audit called
            // this out as the single biggest missing piece on Home.
            // Pulled out into its own rounded chip so it reads as
            // a distinct "what's coming" callout rather than yet
            // another body line under the secondary.
            //
            // Tint: status colour when we have a real verdict; soft
            // `appPrimary` in the neutral / no-budget state. The
            // legacy code used `.secondary` (grey-on-grey) for the
            // neutral case, which made the chip blend into the card
            // background — the only forward-looking line on the
            // surface had become the most muted thing on it.
            if let projection = v.projectionLine(formattedAmount: viewModel.formattedAmount) {
                let chipTint: Color = v.status == .neutral ? .appPrimary : v.status.tint
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(projection)
                        .font(.footnote.weight(.medium))
                }
                .foregroundColor(chipTint)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(chipTint.opacity(0.10))
                )
                .padding(.top, Theme.Spacing.lg)
            }

            // Quick-stats footer — three glance-only readouts that
            // make the card feel alive without adding another card
            // to scroll past. Stays inside the verdict card so the
            // hero stays the single anchoring block on screen.
            //
            // With a budget: Today / Daily Avg / Remaining
            // Without a budget: Today / Daily Avg / Days Left
            Divider()
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)

            quickStatsRow(for: v)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl + 2)
        .cardSurface()
    }

    /// Three-up stats footer for the verdict card. Each cell is a
    /// tiny labeled number with a hairline divider between cells —
    /// the same pattern Copilot uses on its monthly summary tile.
    /// Built as a single HStack instead of three independent tiles
    /// so the row reads as a continuation of the verdict, not a
    /// separate strip.
    ///
    /// Middle cell depends on whether there's a budget anchor:
    ///   • With a budget → "LEFT PER DAY" (remaining ÷ days left) —
    ///     the forward-looking safe-to-spend number, the single most
    ///     actionable stat in manual budgeting (Copilot's Free to
    ///     Spend). Backward-looking daily average already informs
    ///     the projection chip above, so it doesn't need a cell.
    ///   • Without a budget → "DAILY AVG" (there's no "left" to
    ///     divide, so pace is the most honest middle stat).
    @ViewBuilder
    private func quickStatsRow(for v: TodayVerdict) -> some View {
        HStack(alignment: .top, spacing: 0) {
            quickStatCell(
                label: "TODAY",
                value: viewModel.formattedAmount(v.todaySpent),
                trend: v.todaySpent > 0 ? .neutral : .positive
            )
            quickStatDivider
            if let leftPerDay = v.leftPerDay {
                quickStatCell(
                    label: "LEFT PER DAY",
                    value: viewModel.formattedAmount(leftPerDay),
                    trend: leftPerDay > 0 ? .positive : .warning
                )
            } else {
                quickStatCell(
                    label: "DAILY AVG",
                    value: viewModel.formattedAmount(v.dailyAvg)
                )
            }
            quickStatDivider
            if let remaining = v.remaining {
                quickStatCell(
                    label: "REMAINING",
                    value: viewModel.formattedAmount(remaining),
                    trend: remaining > 0 ? .positive : .warning
                )
            } else if let daysLeft = v.daysLeft {
                quickStatCell(
                    label: "DAYS LEFT",
                    value: "\(daysLeft)"
                )
            } else {
                quickStatCell(label: "", value: "")
            }
        }
    }

    /// One cell of the quick-stats footer. The value is monospaced
    /// rounded for the same "premium finance" treatment as the hero
    /// number; the trend tint is intentionally muted (foreground
    /// only, no background fill) so the cells don't fight the
    /// verdict pill for attention.
    private func quickStatCell(label: String, value: String, trend: StatTrend = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(trend.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickStatDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 28)
            .padding(.horizontal, Theme.Spacing.sm)
    }

    private enum StatTrend {
        case neutral, positive, warning

        @MainActor var color: Color {
            switch self {
            case .neutral:  return .primary
            case .positive: return .primary  // keep restful; positive ≠ loud green
            case .warning:  return .primary  // tint is reserved for the verdict pill
            }
        }
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
            // Milestone moment: when the verdict flips (On Track →
            // Tight → Over), the pill swap animates instead of hard-
            // cutting. The paired warning haptic fires from the
            // recompute commit (once per day), not here.
            .contentTransition(.opacity)
            .animation(Theme.Motion.tap, value: status)
    }

    /// Progress ring on the right of the hero. Only rendered when
    /// the verdict has a real `ringPercentage` — the no-budget case
    /// is handled by simply omitting the ring (the top verdict row
    /// is dropped entirely in that branch) so the hero gets the full
    /// card width and the "+ Set" affordance lives in the section
    /// header above the card instead.
    ///
    /// When the user is `over` budget the ring gets a gentle
    /// recurring pulse — calm enough to live on the screen
    /// indefinitely (not a flashing alert), bright enough to draw
    /// the eye back to the verdict.
    private func verdictRing(percentage: Double?, status: TodayVerdict.Status) -> some View {
        let trimAmount = min(max(percentage ?? 0, 0), 1)
        // First-appear: the trim animates 0 → value (the review noted
        // it previously snapped to its final trim on first render and
        // only animated on later changes).
        let displayedTrim = verdictRingAppeared ? trimAmount : 0
        return ZStack {
            Circle()
                .stroke(Color.secondarySystemBackground, lineWidth: 7)
                .frame(width: 72, height: 72)
            if percentage != nil {
                Circle()
                    .trim(from: 0, to: displayedTrim)
                    .stroke(status.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.Motion.emphasized, value: displayedTrim)
                    .shadow(
                        color: status.tint.opacity(status == .over ? overRingPulse : 0),
                        radius: 8,
                        x: 0,
                        y: 0
                    )
                Text("\(Int((trimAmount * 100).rounded()))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.tap, value: trimAmount)
            } else {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .onAppear {
            if !verdictRingAppeared {
                // Flip on the next runloop tick so SwiftUI animates the
                // 0 → value change instead of collapsing it into the
                // initial render.
                Task { @MainActor in
                    withAnimation(Theme.Motion.emphasized) { verdictRingAppeared = true }
                }
            }
            startOverPulseIfNeeded(status: status)
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .over {
                startOverPulseIfNeeded(status: newStatus)
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    overRingPulse = 0
                }
            }
        }
    }

    /// Three visible pulses (odd repeat count ends at the target),
    /// then the glow *holds* at 0.35 — a static shadow costs nothing,
    /// unlike the previous infinite pulse which invalidated the layer
    /// every frame for as long as the user stayed over budget.
    private func startOverPulseIfNeeded(status: TodayVerdict.Status) {
        guard status == .over else {
            overRingPulse = 0
            return
        }
        overRingPulse = 0
        withAnimation(.easeInOut(duration: 0.9).repeatCount(5, autoreverses: true)) {
            overRingPulse = 0.6
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_600_000_000)
            guard overRingPulse > 0 else { return }
            withAnimation(.easeOut(duration: 0.6)) { overRingPulse = 0.35 }
        }
    }

    // MARK: - Stacked budgets card (2+ budgets)
    //
    // Replaces the old "verdict hero + breakdown" stack when the
    // user has multiple budgets. One card, one row per budget,
    // worst-status pill on top, the same Today/DailyAvg/Remaining
    // quick stats on the bottom — and the projection chip pulled
    // in from the verdict because it still makes sense aggregated.
    private func stackedBudgetsCard(_ v: TodayVerdict) -> some View {
        let worst = worstStatus(across: budgetSnapshots, fallback: v.status)

        return VStack(alignment: .leading, spacing: 0) {
            // Card top row: worst-status pill + days-left chip. The
            // section title and Manage shortcut already live above
            // the card (`budgetsSectionHeader`) so they're not
            // duplicated here.
            HStack(spacing: Theme.Spacing.xs + 2) {
                verdictPill(worst)
                if let daysLeft = v.daysLeft {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(daysLeft) days left")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            // Per-budget rows. Each is tappable to open the Manage
            // sheet so the user can edit/delete without hunting for
            // it in Profile. Hairline dividers between rows keep the
            // section reading as one connected list.
            VStack(spacing: 0) {
                ForEach(Array(budgetSnapshots.enumerated()), id: \.element.id) { idx, snap in
                    stackedBudgetRow(snap)
                        .padding(.top, idx == 0 ? Theme.Spacing.xl : Theme.Spacing.lg)
                        .padding(.bottom, idx == budgetSnapshots.count - 1 ? 0 : Theme.Spacing.lg)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.shared.lightTap()
                            showingBudgetList = true
                        }
                    if idx < budgetSnapshots.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }

            // Aggregate projection chip. Read from the verdict,
            // which already sums per-budget pace into a single
            // forward-looking line.
            if let projection = v.projectionLine(formattedAmount: viewModel.formattedAmount) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(projection)
                        .font(.footnote.weight(.medium))
                }
                .foregroundColor(worst.tint)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 7)
                .background(Capsule().fill(worst.tint.opacity(0.10)))
                .padding(.top, Theme.Spacing.lg)
            }

            // Same footer as the single-budget hero so the section
            // reads consistently regardless of how many budgets the
            // user has.
            Divider()
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)
            quickStatsRow(for: v)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl + 2)
        .cardSurface()
    }

    /// One row inside the stacked-budgets card. Three info clusters:
    /// medallion + name+subline, mini progress bar, right-rail
    /// remaining/over readout. Pulled into its own function so the
    /// `stackedBudgetsCard` body stays readable.
    private func stackedBudgetRow(_ snap: BudgetSnapshot) -> some View {
        let medallion = budgetMedallion(for: snap.categoryFilter)
        let tint = budgetRowTint(percentage: snap.percentage, isOver: snap.isOver)

        return HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(medallion.color.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: medallion.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(medallion.color)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snap.name)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.sm)
                    if snap.isOver {
                        Text("\(viewModel.formattedAmount(snap.overshoot)) over")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.red)
                            .contentTransition(.numericText())
                    } else {
                        Text("\(viewModel.formattedAmount(snap.remaining)) left")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                    }
                }

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint)
                            .frame(width: max(4, geo.size.width * CGFloat(snap.barProgress)))
                            .animation(Theme.Motion.emphasized, value: snap.barProgress)
                    }
                }
                .frame(height: 5)

                Text("\(viewModel.formattedAmount(snap.spent)) of \(viewModel.formattedAmount(snap.limit))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Picks the worst status across all snapshots so the stacked
    /// card's headline pill reflects the user's most-pressing
    /// budget. Falls back to the verdict's own status (used for the
    /// no-snapshots edge case, though the caller already guards
    /// against it).
    private func worstStatus(across snaps: [BudgetSnapshot], fallback: TodayVerdict.Status) -> TodayVerdict.Status {
        if snaps.contains(where: { $0.isOver }) { return .over }
        if snaps.contains(where: { $0.percentage > 0.9 }) { return .tight }
        if snaps.isEmpty { return fallback }
        return .onTrack
    }

    /// Mini-bar tint shared between the stacked-budget row and
    /// anywhere else we draw a budget progress bar. Mirrors the
    /// verdict pill's tint mapping so colour reads consistently
    /// across the section.
    private func budgetRowTint(percentage: Double, isOver: Bool) -> Color {
        if isOver { return .red }
        if percentage > 0.9 { return .orange }
        return .green
    }

    /// Compact medallion + name eyebrow shown above the hero amount
    /// in the single-budget `verdictCard`. Same medallion treatment
    /// as `stackedBudgetRow` but at 28pt (vs 36pt) so it reads as
    /// a quiet label, not a competing element with the 46pt hero
    /// amount sitting directly under it. Hairline divider above
    /// separates it from the verdict pill row when both are present.
    private func singleBudgetIdentityRow(_ snap: BudgetSnapshot) -> some View {
        let medallion = budgetMedallion(for: snap.categoryFilter)
        return HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(medallion.color.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: medallion.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(medallion.color)
            }

            Text(snap.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Budget: \(snap.name)")
    }

    /// Icon + color for a budget's medallion. Custom categories look
    /// up their stored `colorName`/`icon`; default categories use the
    /// `Expense.Category` enum; the overall budget uses the app
    /// accent so it reads as the headline budget in the list.
    private func budgetMedallion(for filter: Budget.CategoryFilter) -> (icon: String, color: Color) {
        switch filter {
        case .overall:
            return (filter.icon, .appPrimary)
        case .defaultCategory(let raw):
            if let category = Expense.Category(rawValue: raw) {
                return (category.icon, Color.forCategory(category.color))
            }
            return (filter.icon, .appPrimary)
        case .customCategory(let id):
            if let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
                return (custom.icon, Color.forCategory(custom.colorName))
            }
            return (filter.icon, .appPrimary)
        }
    }

    // MARK: - Upcoming bills section
    //
    // Forward-looking content. Today was almost entirely
    // backwards-looking before — verdict, week strip, recent
    // expenses, insight — all describing the past. This section
    // tells the user what's about to hit their account: the next
    // few subscriptions due in the upcoming window.
    //
    // Why this slot (between Budgets and This Week): the user just
    // read "am I OK?" → next question is "what's about to change?"
    // The week strip then answers "what's the recent shape?" and
    // Recent answers "did I log that?". One question per block.
    private func upcomingBillsSection(_ bills: [UpcomingBill]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("Upcoming Subscriptions")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                Spacer()
                Text(upcomingHeaderTotal(bills: bills))
                    .font(Theme.Typography.numericSmall)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                sectionJumpButton(label: "Manage", accessibilityLabel: "Open all subscriptions") {
                    showingSubscriptions = true
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(bills.enumerated()), id: \.element.id) { idx, bill in
                    upcomingBillRow(bill)
                    if idx < bills.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .cardSurface()
        }
    }

    /// Shared trailing-arrow button used by section headers that
    /// jump to a related screen ("Upcoming Subscriptions" → manage
    /// list, "This week" → Insights). Mirrors the existing "See all
    /// →" affordance on Recent so all three headers read as one
    /// consistent navigation pattern instead of three bespoke ones.
    private func sectionJumpButton(
        label: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.lightTap()
            action()
        } label: {
            HStack(spacing: 2) {
                Text(label)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(Theme.Typography.caption.weight(.medium))
            .foregroundColor(.appPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func upcomingHeaderTotal(bills: [UpcomingBill]) -> String {
        let total = bills.reduce(0) { $0 + $1.amount }
        return viewModel.formattedAmount(total)
    }

    private func upcomingBillRow(_ bill: UpcomingBill) -> some View {
        let medallion = upcomingBillMedallion(for: bill)
        let tint = bill.isOverdue
            ? Color.red
            : (bill.daysUntilDue <= 2 ? Color.orange : Color.secondary)

        return HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(medallion.color.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: medallion.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(medallion.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(bill.dueLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(tint)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(viewModel.formattedAmount(bill.amount))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func upcomingBillMedallion(for bill: UpcomingBill) -> (icon: String, color: Color) {
        if bill.category == .custom, let id = bill.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return (custom.icon, Color.forCategory(custom.colorName))
        }
        return (bill.category.icon, Color.forCategory(bill.category.color))
    }

    // MARK: - 7-day strip
    //
    // Horizontal sparkline-by-day. Tinted by each day's dominant
    // category so you don't just see "spent more on Wednesday" —
    // you see "spent more on Wednesday, and it was mostly Food."
    private var weekStripSection: some View {
        // Outside-the-card title pattern, same as Recent / Upcoming.
        // The card body below holds only the chart, no internal
        // header — there's exactly one place to find the title.
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(weekStripHeaderTitle)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                // Streak chip — the design review's #7: StreakCalculator
                // was orphaned (widget-only) since HomeView died; this
                // re-homes the same metric in the week-strip header's
                // empty slot. Hidden while a day is selected so the
                // header doesn't fight the selected-day readout.
                if selectedWeekDay == nil, let streak, streak.isMeaningful, streak.currentStreak >= 1 {
                    streakChip(streak)
                }
                Spacer()
                if let amount = weekStripHeaderAmount {
                    Text(viewModel.formattedAmount(amount))
                        .font(Theme.Typography.numericSmall)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .contentTransition(.numericText())
                        .moneyAnimation(amount: amount, currency: viewModel.selectedCurrency)
                }
                sectionJumpButton(label: "Insights", accessibilityLabel: "Open Insights") {
                    // Preselect the .week timeframe in StatisticsView
                    // so the user lands on the same window they were
                    // glancing at, then perform the tab switch.
                    NotificationCenter.default.post(
                        name: .insightsRequestTimeFrame,
                        object: ExpenseViewModel.TimeFrame.week
                    )
                    onOpenInsights()
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
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xl)
            .cardSurface()
        }
    }

    /// Small flame chip: "3-day streak". Same `StreakCalculator`
    /// numbers the widget renders, so the two surfaces never disagree.
    /// Scale-pops once when the count increments (driven by
    /// `streakPop`, set in the recompute commit) — a single spring,
    /// never a loop.
    private func streakChip(_ s: StreakCalculator.StreakSummary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("\(s.currentStreak)-day streak")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundColor(.orange)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.orange.opacity(0.12)))
        .scaleEffect(streakPop ? 1.12 : 1.0)
        .animation(Theme.Motion.tap, value: streakPop)
        .accessibilityLabel("\(s.currentStreak) day no-spend streak")
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
                // One container, three bare rows separated by a thin
                // indented divider — reads as "one recent cluster"
                // instead of three independently-elevated tiles
                // stacking on top of each other. Cuts visual weight
                // by ~40% without losing per-row tappability.
                let recent = Array(viewModel.expenses.prefix(3))
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, expense in
                        ExpenseCard(
                            expense: expense,
                            viewModel: viewModel,
                            categoryViewModel: categoryViewModel,
                            style: .bare
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.shared.lightTap()
                            editingExpense = expense
                        }
                        if idx < recent.count - 1 {
                            Divider()
                                .padding(.leading, 56) // align with title, past medallion
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private var emptyRecentBlock: some View {
        InlineEmptyState(
            icon: "tray",
            title: "No expenses yet",
            message: "Tap + to log your first one."
        )
        .cardSurface()
    }

    // MARK: - Insight card
    //
    // One observation, picked by the existing SmartInsightsEngine
    // (or a calm fallback). Never more than one — the audit was
    // explicit that "card sprawl" was eroding the screen.
    private func insightCard(for insight: TodayInsight) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md + 2) {
            // Slimmer, lighter-weight icon medallion. The v1 of this
            // card used a 36pt heavy-tinted circle that competed
            // with the verdict ring above; the tighter 32pt treatment
            // reads as "here's a quiet note" instead of "alert".
            ZStack {
                Circle()
                    .fill(insight.tint.opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: insight.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(insight.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
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
        // `currentBudgets`, not `activeBudgets`: an ended custom-window
        // budget (a trip that's over) must not keep anchoring Today's
        // verdict or the stacked rows. It still lives in Manage Budgets.
        let overallBudget = budgetViewModel.currentBudgets.first { $0.categoryFilter.isOverall }
        let overallProgress = overallBudget.map { budgetViewModel.progress(for: $0) }
        let overallPeriodKind: TodayVerdict.PeriodKind? = overallBudget.map { (budget: Budget) -> TodayVerdict.PeriodKind in
            switch budget.period {
            case .weekly:  return .week
            case .monthly: return .month
            case .custom:
                let cal = Calendar.current
                let lastDay = cal.date(byAdding: .day, value: -1, to: budget.dateRange.end) ?? budget.dateRange.end
                return .custom(endDate: lastDay)
            }
        }
        let activeBudgets = budgetViewModel.currentBudgets
        let activeProgress = activeBudgets.map { budgetViewModel.progress(for: $0) }
        let now = Date()
        let categoryMap: [UUID: (name: String, color: String)] = Dictionary(
            uniqueKeysWithValues: categoryViewModel.customCategories.map { ($0.id, (name: $0.name, color: $0.colorName)) }
        )

        // Summary-card needs a richer custom-category map (icon too,
        // since the Top Category medallion uses it). Kept separate
        // from the week-strip map above so each consumer pays only
        // for the fields it reads.
        let summaryCategoryMap: [UUID: SummaryStats.CustomCategoryInfo] = Dictionary(
            uniqueKeysWithValues: categoryViewModel.customCategories.map {
                ($0.id, SummaryStats.CustomCategoryInfo(name: $0.name, icon: $0.icon, color: $0.colorName))
            }
        )
        let currentPeriod = summaryPeriod

        // Build the per-budget snapshot list on the main actor (cheap —
        // it's just an O(N) map of already-published progress values).
        // The list mirrors `activeBudgets` 1:1 so we can render rows
        // without re-asking the view model on every body re-render.
        let snapshots: [BudgetSnapshot] = activeBudgets.map { budget in
            let p = budgetViewModel.progress(for: budget)
            return BudgetSnapshot(
                id: budget.id,
                name: budget.name,
                spent: p.spent,
                limit: p.limit,
                percentage: p.percentage,
                isOver: p.spent > p.limit,
                categoryFilter: budget.categoryFilter
            )
        }

        // Recap-card gating inputs snapshotted on the main actor so the
        // detached task never touches UserDefaults.
        let recapSeenKey = UserDefaults.standard.string(forKey: UserDefaultsKeys.monthlyRecapLastSeenMonth)

        recomputeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let result: (verdict: TodayVerdict, weekStrip: [WeekStripDay], insight: TodayInsight?, summary: SummaryStats, streak: StreakCalculator.StreakSummary, recapMonth: Date?) =
                await Task.detached(priority: .userInitiated) {
                    let v = TodayVerdict.compute(
                        expenses: expensesSnapshot,
                        overallProgress: overallProgress,
                        overallPeriodKind: overallPeriodKind,
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
                    let summaryStats = SummaryStats.compute(
                        expenses: expensesSnapshot,
                        customCategories: summaryCategoryMap,
                        period: currentPeriod,
                        now: now
                    )
                    let streakSummary = StreakCalculator.summary(from: expensesSnapshot, now: now)

                    // Recap invitation: only during the first few days
                    // of a month, only when the previous month hasn't
                    // been viewed yet, and only when it actually has
                    // data to recap. Runs on the same snapshot as
                    // everything else — if the window is still partially
                    // hydrated, the next publish (full hydration)
                    // re-evaluates and self-corrects.
                    let recapCandidate: Date? = {
                        let cal = Calendar.current
                        guard cal.component(.day, from: now) <= MonthlyRecapEngine.todayCardWindowDays,
                              let thisMonthStart = cal.dateInterval(of: .month, for: now)?.start,
                              let prevMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart),
                              let prevInterval = cal.dateInterval(of: .month, for: prevMonthStart)
                        else { return nil }
                        guard MonthlyRecapEngine.monthKey(for: prevMonthStart) != recapSeenKey else { return nil }
                        let hasData = expensesSnapshot.contains {
                            $0.date >= prevInterval.start && $0.date < prevInterval.end
                        }
                        return hasData ? prevMonthStart : nil
                    }()

                    return (v, strip, insight, summaryStats, streakSummary, recapCandidate)
                }.value

            guard !Task.isCancelled else { return }

            // Contextual warning haptic: the moment Today first shows a
            // *worse* verdict (Tight or Over) than the previous pass —
            // at most once per day, so a recompute storm can't buzz
            // repeatedly. This is the one contextual haptic the design
            // review's event map flagged as missing.
            if let old = verdict,
               result.verdict.status.severity > old.status.severity,
               result.verdict.status == .tight || result.verdict.status == .over {
                let todayStart = Calendar.current.startOfDay(for: Date())
                let last = UserDefaults.standard.object(forKey: UserDefaultsKeys.verdictWarningLastDate) as? Date
                if last != todayStart {
                    UserDefaults.standard.set(todayStart, forKey: UserDefaultsKeys.verdictWarningLastDate)
                    HapticManager.shared.warning()
                }
            }

            verdict = result.verdict
            weekStrip = result.weekStrip
            todayInsight = result.insight
            budgetSnapshots = snapshots
            summary = result.summary
            withAnimation(Theme.Motion.emphasized) {
                recapMonth = result.recapMonth
            }

            // One-shot pop when the current streak grows (not on first
            // load — no baseline to celebrate against yet).
            let previousStreak = streak?.currentStreak
            streak = result.streak
            if let previousStreak, result.streak.currentStreak > previousStreak {
                streakPop = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    streakPop = false
                }
            }
        }
    }

    /// Builds the upcoming-bills list for the Today screen. Picks
    /// active subscriptions due in the next `Self.upcomingBillsWindow`
    /// days, oldest-first, capped at `Self.upcomingBillsMax`. Pure
    /// transform — runs synchronously on the main actor because the
    /// active set is typically <100 items.
    private func recomputeUpcomingBills() {
        let now = Date()
        let cal = Calendar.current
        let windowEnd = cal.date(byAdding: .day, value: Self.upcomingBillsWindow, to: now) ?? now

        let upcoming = subscriptionViewModel.subscriptions
            .filter { $0.isActive && $0.nextDueDate <= windowEnd }
            .sorted { $0.nextDueDate < $1.nextDueDate }
            .prefix(Self.upcomingBillsMax)
            .map { sub -> UpcomingBill in
                let days = sub.daysUntilNext
                return UpcomingBill(
                    id: sub.id,
                    name: sub.name,
                    amount: sub.amount,
                    currency: sub.currency,
                    daysUntilDue: days,
                    nextDueDate: sub.nextDueDate,
                    category: sub.category,
                    customCategoryId: sub.customCategoryId,
                    isOverdue: days < 0
                )
            }

        upcomingBills = Array(upcoming)
    }

    /// How far into the future the Today screen surfaces upcoming
    /// bills. 14 days is the same window Copilot/PocketGuard use —
    /// long enough to be useful, short enough that the section never
    /// becomes a wall of distant payments.
    private static let upcomingBillsWindow: Int = 14

    /// Hard cap on the number of upcoming bills to show on Today.
    /// Three keeps the section glance-only; full list lives in the
    /// You → Subscriptions surface.
    private static let upcomingBillsMax: Int = 3
}

// MARK: - Per-budget snapshot model
//
// Lightweight, Sendable copy of a budget + its progress as of the
// last recompute. Lives alongside TodayVerdict so the view doesn't
// hammer the view model from inside its body.

struct BudgetSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let spent: Double
    let limit: Double
    let percentage: Double
    let isOver: Bool
    let categoryFilter: Budget.CategoryFilter

    var remaining: Double { max(0, limit - spent) }
    var overshoot: Double { max(0, spent - limit) }
    var barProgress: Double { min(max(percentage, 0), 1) }
}

// MARK: - Upcoming bill model
//
// Same shape as a subscription row but pre-resolved for the Today
// screen so the view never reaches back into the SubscriptionViewModel
// from inside its body.

struct UpcomingBill: Identifiable, Equatable {
    let id: UUID
    let name: String
    let amount: Double
    let currency: Expense.Currency
    let daysUntilDue: Int
    let nextDueDate: Date
    let category: Expense.Category
    let customCategoryId: UUID?
    let isOverdue: Bool

    /// "Today", "Tomorrow", "in 3 days", "3 days overdue" — the
    /// single line that drives the row's secondary label.
    var dueLabel: String {
        if daysUntilDue < 0 {
            let abs = -daysUntilDue
            return abs == 1 ? "1 day overdue" : "\(abs) days overdue"
        }
        if daysUntilDue == 0 { return "Due today" }
        if daysUntilDue == 1 { return "Due tomorrow" }
        return "Due in \(daysUntilDue) days"
    }
}

// MARK: - Summary period

/// Period the Today summary cards display. Identified by raw
/// strings so the user's choice round-trips through UserDefaults
/// (and survives future enum reorderings).
enum SummaryPeriod: String, CaseIterable, Sendable {
    case today, thisWeek, thisMonth, allTime

    var displayName: String {
        switch self {
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .thisMonth: return "This Month"
        case .allTime:   return "All Time"
        }
    }

    static let userDefaultsKey = "today.summaryPeriod"

    /// Restores the user's persisted choice, defaulting to
    /// `.thisWeek`. Month is deliberately NOT the default: the
    /// verdict hero directly above is already a this-month readout,
    /// so a monthly Summary card duplicated the exact same "spent"
    /// figure twice on one screen. A week lens complements the
    /// monthly verdict instead of echoing it. Users who prefer the
    /// month view pick it once and the choice persists.
    static func restored() -> SummaryPeriod {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey)
        return raw.flatMap(SummaryPeriod.init(rawValue:)) ?? .thisWeek
    }

    /// Half-open date interval for filtering expenses. `.allTime`
    /// uses `distantPast…distantFuture` so the same filter code
    /// works without a special case.
    func dateRange(now: Date) -> DateInterval {
        let cal = Calendar.current
        switch self {
        case .today:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .thisWeek:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .thisMonth:
            return cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)
        case .allTime:
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }
}

// MARK: - Summary stats
//
// Pure value type — produced off-main inside the recompute pipeline,
// rendered by the view. Holds just enough to drive both summary
// cards; resolving icons/colors lives on the SwiftUI side via
// `Color.forCategory` so the snapshot crosses actor boundaries
// cleanly.

struct SummaryStats: Sendable, Equatable {
    let totalSpent: Double
    let transactionCount: Int
    let topCategoryName: String?
    let topCategoryAmount: Double
    let topCategoryPercentage: Double  // 0…1
    let topCategoryIcon: String?
    let topCategoryColor: String?      // color name resolved via `Color.forCategory`

    /// Sendable companion used to ferry custom-category metadata
    /// from the main-actor view model into the detached compute
    /// task. Mirrors the shape `WeekStripDay` uses for the same
    /// reason.
    struct CustomCategoryInfo: Sendable {
        let name: String
        let icon: String
        let color: String
    }

    static func compute(
        expenses: [Expense],
        customCategories: [UUID: CustomCategoryInfo],
        period: SummaryPeriod,
        now: Date
    ) -> SummaryStats {
        let range = period.dateRange(now: now)
        // Refunds (negative signedAmount) deliberately excluded from
        // both the total and the top-category breakdown — a "Top
        // Category" of "Refunds" would read as celebratory nonsense.
        let filtered = expenses.filter {
            $0.date >= range.start && $0.date < range.end && $0.signedAmount > 0
        }
        let total = filtered.reduce(0) { $0 + $1.signedAmount }

        // Aggregate by display key (category name) so default and
        // custom categories with the same display name collapse
        // cleanly.
        var byCategory: [String: (amount: Double, icon: String, color: String)] = [:]
        for e in filtered {
            let key: String
            let icon: String
            let color: String
            if e.category == .custom, let id = e.customCategoryId, let cat = customCategories[id] {
                key = cat.name
                icon = cat.icon
                color = cat.color
            } else {
                key = e.category.displayName
                icon = e.category.icon
                color = e.category.color
            }
            var existing = byCategory[key] ?? (0, icon, color)
            existing.amount += e.signedAmount
            byCategory[key] = existing
        }

        let top = byCategory.max(by: { $0.value.amount < $1.value.amount })
        let topPct = total > 0 ? ((top?.value.amount ?? 0) / total) : 0

        return SummaryStats(
            totalSpent: total,
            transactionCount: filtered.count,
            topCategoryName: top?.key,
            topCategoryAmount: top?.value.amount ?? 0,
            topCategoryPercentage: topPct,
            topCategoryIcon: top?.value.icon,
            topCategoryColor: top?.value.color
        )
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

        /// Ordering used to detect a *worsening* verdict transition
        /// (drives the once-per-day warning haptic). Neutral and
        /// on-track are equally "fine"; tight and over escalate.
        var severity: Int {
            switch self {
            case .neutral, .onTrack: return 0
            case .tight:             return 1
            case .over:              return 2
            }
        }
    }

    /// Which window the anchoring budget runs on — drives the copy
    /// ("this week" / "this month" / "until 27 Jul"). The no-budget
    /// neutral verdict is always month-anchored.
    enum PeriodKind: Equatable, Sendable {
        case week
        case month
        case custom(endDate: Date)

        /// "until 27 Jul" / "this week" / "this month" — the suffix
        /// of the secondary line under the hero amount.
        var windowSuffix: String {
            switch self {
            case .week:  return "this week"
            case .month: return "this month"
            case .custom(let end):
                return "until \(end.formatted(.dateTime.day().month(.abbreviated)))"
            }
        }

        /// "by week's end" / "by month-end" / "by 27 Jul" — the tail
        /// of the projection chip.
        var projectionSuffix: String {
            switch self {
            case .week:  return "by week's end"
            case .month: return "by month-end"
            case .custom(let end):
                return "by \(end.formatted(.dateTime.day().month(.abbreviated)))"
            }
        }
    }

    let status: Status
    let spent: Double
    let limit: Double?            // nil when there's no budget anchor
    let projectedTotal: Double?   // nil when we can't safely project
    let daysLeft: Int?
    let ringPercentage: Double?   // nil → ring renders as empty placeholder
    let periodKind: PeriodKind

    /// Spend logged today (signed, refunds excluded from the positive
    /// total). Drives the "Today" stat in the quick-stats footer.
    let todaySpent: Double

    /// Days elapsed in the current period (1-based — today counts as
    /// elapsed). Used for the "Daily avg" stat. Always ≥ 1 so we never
    /// divide by zero.
    let daysElapsed: Int

    /// Average daily spend over `daysElapsed`. Computed lazily so we
    /// don't store yet another redundant field.
    var dailyAvg: Double {
        guard daysElapsed > 0 else { return 0 }
        return spent / Double(daysElapsed)
    }

    /// Remaining headroom under the budget. `nil` when there's no
    /// budget, clamped to 0 when over (we never show negative
    /// "remaining" — over-state is already communicated by the ring,
    /// pill, and projection chip).
    var remaining: Double? {
        guard let limit = limit else { return nil }
        return max(0, limit - spent)
    }

    /// Forward-looking safe-to-spend: remaining budget spread over
    /// the days left in the period. `nil` without a budget anchor.
    /// On the period's final day (`daysLeft == 0`) the divisor
    /// clamps to 1 so the cell reads "what's left for today" instead
    /// of dividing by zero.
    var leftPerDay: Double? {
        guard let remaining = remaining, let daysLeft = daysLeft else { return nil }
        return remaining / Double(max(1, daysLeft))
    }

    /// Secondary copy under the hero number — depends on whether we
    /// have a budget anchor, worded for the anchor's actual window.
    func secondaryLine(formattedAmount: (Double) -> String) -> String {
        if let limit = limit {
            return "of \(formattedAmount(limit)) \(periodKind.windowSuffix)"
        }
        return "spent \(periodKind.windowSuffix)"
    }

    /// Projection footer — only when we have enough data to be honest
    /// about the prediction.
    func projectionLine(formattedAmount: (Double) -> String) -> String? {
        guard let projection = projectedTotal else { return nil }
        let suffix = periodKind.projectionSuffix
        if let limit = limit {
            let delta = projection - limit
            if delta > 0 {
                return "At this pace → \(formattedAmount(projection)) \(suffix) (\(formattedAmount(delta)) over)"
            }
            return "At this pace → \(formattedAmount(projection)) \(suffix)"
        }
        return "At this pace → \(formattedAmount(projection)) \(suffix)"
    }

    // MARK: - Compute
    static func compute(
        expenses: [Expense],
        overallProgress: BudgetViewModel.BudgetProgress?,
        overallPeriodKind: PeriodKind?,
        categoryProgressList: [BudgetViewModel.BudgetProgress],
        currency: Expense.Currency,
        now: Date
    ) -> TodayVerdict {
        // Compute today's spend once — it's budget-agnostic and the
        // same value powers the "Today" stat regardless of which case
        // we fall into below.
        let todaySpent = todaySpend(from: expenses, now: now)

        // Case 1: explicit overall budget → use it directly, worded
        // for its actual window (week / month / custom trip dates).
        if let p = overallProgress {
            return verdict(from: p, todaySpent: todaySpent, periodKind: overallPeriodKind ?? .month)
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
                ringPercentage: limit > 0 ? min(max(spent / limit, 0), 1) : nil,
                // Mixed category-budget periods aggregate onto the
                // month lens — the dominant real-world case.
                periodKind: .month,
                todaySpent: todaySpent,
                daysElapsed: elapsed
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
            ringPercentage: nil,
            periodKind: .month,
            todaySpent: todaySpent,
            daysElapsed: daysElapsed
        )
    }

    private static func verdict(from p: BudgetViewModel.BudgetProgress, todaySpent: Double, periodKind: PeriodKind) -> TodayVerdict {
        let projection = p.projectedTotal
        let status: Status = {
            if projection > p.limit * 1.05 || p.status == .exceeded { return .over }
            if p.percentage > 0.9 || projection > p.limit * 0.95 { return .tight }
            return .onTrack
        }()
        let elapsed = max(1, p.totalDays - p.daysRemaining)
        return TodayVerdict(
            status: status,
            spent: p.spent,
            limit: p.limit,
            projectedTotal: projection,
            daysLeft: p.daysRemaining,
            ringPercentage: p.limit > 0 ? min(max(p.spent / p.limit, 0), 1) : nil,
            periodKind: periodKind,
            todaySpent: todaySpent,
            daysElapsed: elapsed
        )
    }

    /// Sum of today's logged spend, refunds excluded so the "Today"
    /// stat reflects out-of-pocket. Lives next to `compute(...)` to
    /// keep all verdict math in one file.
    private static func todaySpend(from expenses: [Expense], now: Date) -> Double {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
        return expenses
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .reduce(0) { $0 + max($1.signedAmount, 0) }
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

// MARK: - Entrance motion
//
// The section entrance cascade (`SectionEntrance`) was promoted to
// `Design/ViewModifiers.swift` (Phase R6 as promised) — shared with
// StatisticsView and the Import/Export screens.

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

// MARK: - First-run hero subviews

/// Pins the scrollable VStack's vertical extent to the scroll
/// container's visible height **only** when `active` is true. Used
/// by `TodayView.body` to give the cold-start spacers room to expand
/// (so the first-run hero card centres in the visible viewport)
/// without affecting any non-cold-start render — when the user has
/// any expense logged, this becomes a no-op and the VStack falls
/// back to its natural height, preserving normal scroll behaviour.
private struct ColdStartFillsScreenModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.containerRelativeFrame(.vertical, alignment: .top) { length, _ in length }
        } else {
            content
        }
    }
}

/// Centered, softly-pulsing sparkle in a tinted circle. The single
/// point of motion on the first-run screen — gentle enough to feel
/// breathing rather than nagging, but it's the cue that tells the
/// user "this card is live, the app is working."
private struct FirstRunSparkleIcon: View {
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appPrimary.opacity(0.14))
                .frame(width: 64, height: 64)
                .scaleEffect(pulse ? 1.08 : 1.0)
                .opacity(pulse ? 0.65 : 1.0)
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.appPrimary)
                .scaleEffect(pulse ? 1.06 : 1.0)
        }
        .animation(
            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
    }
}
