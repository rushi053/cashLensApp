import SwiftUI

/// Manage Budgets sheet (presented from Today and Profile).
///
/// v2 pass: the old nav-bar + plain rows read a generation behind the
/// rest of the app. Now:
///   • Canonical `SheetHeader` chrome (same strip as Add Expense /
///     Budget Setup) with the add action in the trailing slot — the
///     free-tier Pro lock treatment is preserved exactly.
///   • A "This period" summary card when 2+ budgets are active
///     (total spent vs total budgeted across all of them).
///   • Rich budget cards: status pill + animated progress bar with a
///     pace tick, spent/limit hero with `numericText` transitions,
///     and a Left / Per day / Days left stats footer — the same
///     visual family as `BudgetProgressCard` on Home.
///   • Last-period comparison per budget, computed off-main via the
///     detached-task pattern (see `scheduleComparisonRecompute`).
///
/// No cascading section entrance here: like Subscriptions, this is a
/// sheet — it already animates in on its own spring, and layering a
/// staggered fade+slide on top reads heavy (the same reasoning that
/// removed `SubEntrance` from SubscriptionsView). Only the progress
/// bars sweep on first render.
struct BudgetListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager

    @State private var showingAddBudget = false
    @State private var editingBudget: Budget?
    @State private var showingPaywall = false

    /// Spend during each budget's *previous* period, keyed by budget id.
    /// Populated off-main once the expense store is fully hydrated;
    /// cards hide the comparison line until then rather than showing a
    /// number computed over a partial window.
    @State private var lastPeriodSpent: [UUID: Double] = [:]
    @State private var comparisonTask: Task<Void, Never>?

    /// One overall budget is free; more budgets are Pro. Users who
    /// accumulated multiple budgets during a Pro trial keep them all
    /// (grandfather — never claw back) but can't add more without Pro.
    private var canCreateBudget: Bool {
        proManager.isPro || budgetViewModel.budgets.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if budgetViewModel.budgets.isEmpty {
                emptyState
                    .frame(maxHeight: .infinity)
            } else {
                budgetList
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showingAddBudget) {
            BudgetSetupView()
                .environmentObject(budgetViewModel)
                .environmentObject(expenseViewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(proManager)
        }
        .sheet(item: $editingBudget) { budget in
            BudgetSetupView(editingBudget: budget)
                .environmentObject(budgetViewModel)
                .environmentObject(expenseViewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(proManager)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(context: .budgets)
        }
        .onAppear { scheduleComparisonRecompute() }
        .onReceive(expenseViewModel.$isFullyHydrated) { hydrated in
            if hydrated { scheduleComparisonRecompute() }
        }
        .onReceive(budgetViewModel.$budgets) { _ in
            scheduleComparisonRecompute()
        }
        .onDisappear { comparisonTask?.cancel() }
    }

    // MARK: - Header (shared SheetHeader convention)

    private var header: some View {
        SheetHeader(
            eyebrow: "Manage",
            title: "Budgets",
            subtitle: headerSubtitle,
            onClose: { dismiss() }
        ) {
            addButton
        }
    }

    private var headerSubtitle: String? {
        let all = budgetViewModel.budgets
        guard !all.isEmpty else { return nil }
        let active = all.filter(\.isActive).count
        let paused = all.count - active
        if paused == 0 {
            return "\(active) active budget\(active == 1 ? "" : "s")"
        }
        return "\(active) active · \(paused) paused"
    }

    /// The "+" in the trailing header slot. Same behavior as the old
    /// toolbar button: free users with ≥1 budget get the Pro lock →
    /// paywall; the list itself stays fully usable either way.
    private var addButton: some View {
        Button {
            if canCreateBudget {
                HapticManager.shared.lightTap()
                showingAddBudget = true
            } else {
                HapticManager.shared.warning()
                showingPaywall = true
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.appPrimary))

                if !canCreateBudget {
                    lockBadge
                        .offset(x: 3, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canCreateBudget ? "Add budget" : "Add budget — requires Pro")
    }

    private var lockBadge: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 16, height: 16)
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.appPrimary)
        }
        .overlay(Circle().stroke(Color.appPrimary.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Budget List

    private var budgetList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Theme.Spacing.md) {
                if activeBudgetsWithProgress.count >= 2 {
                    summaryCard
                        .padding(.bottom, Theme.Spacing.xs)
                }

                ForEach(budgetViewModel.budgets) { budget in
                    BudgetOverviewCard(
                        budget: budget,
                        progress: budgetViewModel.progress(for: budget),
                        lastPeriodSpent: lastPeriodSpent[budget.id],
                        formattedAmount: expenseViewModel.formattedAmount,
                        currency: expenseViewModel.selectedCurrency,
                        onTap: { editingBudget = budget },
                        onToggle: { budgetViewModel.toggleBudgetActive(budget) },
                        onDelete: { budgetViewModel.deleteBudget(budget) }
                    )
                }

                if !canCreateBudget {
                    proTeaserRow
                        .padding(.top, Theme.Spacing.sm)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private var activeBudgetsWithProgress: [(Budget, BudgetViewModel.BudgetProgress)] {
        budgetViewModel.budgets
            .filter(\.isActive)
            .map { ($0, budgetViewModel.progress(for: $0)) }
    }

    // MARK: - Summary card

    /// Roll-up across all active budgets: total spent vs total budgeted
    /// this period. Periods can mix weekly/monthly, so this is framed
    /// as "across your budgets" rather than a single date range.
    private var summaryCard: some View {
        let pairs = activeBudgetsWithProgress
        let totalBudgeted = pairs.reduce(0.0) { $0 + $1.0.amount }
        let totalSpent = pairs.reduce(0.0) { $0 + $1.1.spent }
        let ratio = totalBudgeted > 0 ? totalSpent / totalBudgeted : 0
        let tint: Color = ratio >= 1.0 ? .red : (ratio >= 0.8 ? .orange : .appPrimary)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("ACROSS YOUR BUDGETS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(pairs.count) active")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(expenseViewModel.formattedAmount(totalSpent))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .moneyAnimation(amount: totalSpent, currency: expenseViewModel.selectedCurrency)

                Text("of \(expenseViewModel.formattedAmount(totalBudgeted))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: Theme.Spacing.sm)

                Text("\(Int(min(ratio * 100, 999)))%")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(tint)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.snappy, value: ratio)
            }

            AnimatedProgressBar(fraction: ratio, tint: tint, paceTick: nil)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Pro teaser

    /// Quiet, tappable hint under the list for free users who already
    /// hold a budget — same paywall as the locked "+", just easier to
    /// discover. Presentation only; the gating decision is unchanged.
    private var proTeaserRow: some View {
        Button {
            HapticManager.shared.lightTap()
            showingPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock more budgets")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(.primary)
                    Text("Set per-category limits with Pro")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(Theme.Spacing.lg)
            .cardSurface(
                fill: Color.appPrimary.opacity(0.06),
                stroke: Color.appPrimary.opacity(0.15),
                strokeWidth: Theme.Stroke.hairline
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStatePanel(
            icon: "gauge.with.needle",
            title: "Give Your Money a Plan",
            message: "Set a weekly or monthly cap — or custom dates for a trip — and CashLens will track your pace and nudge you before you overshoot."
        ) {
            PrimaryGradientButton(title: "Create Your First Budget", width: .hug) {
                HapticManager.shared.heavyTap()
                showingAddBudget = true
            }
        }
    }

    // MARK: - Last-period comparison (off-main)

    /// Computes what each active budget's slice spent in the *previous*
    /// period (last week / last month). Same debounce + detached-task
    /// shape as `BudgetViewModel.scheduleRecompute` so the expense scan
    /// never runs on the main thread inside a view body. Gated on
    /// `isFullyHydrated`: the previous period can predate the hot
    /// launch window, and a partial scan would understate the number.
    private func scheduleComparisonRecompute() {
        comparisonTask?.cancel()
        comparisonTask = Task { @MainActor [weak expenseViewModel, weak budgetViewModel] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            guard let expenseViewModel, let budgetViewModel,
                  expenseViewModel.isFullyHydrated else { return }

            let expenses = expenseViewModel.expenses
            let budgets = budgetViewModel.budgets.filter(\.isActive)
            guard !budgets.isEmpty else {
                lastPeriodSpent = [:]
                return
            }

            let result: [UUID: Double] = await Task.detached(priority: .utility) { [expenses, budgets] in
                let calendar = Calendar.current
                var map: [UUID: Double] = [:]
                for budget in budgets {
                    let currentStart = budget.dateRange.start
                    let previousStart: Date
                    switch budget.period {
                    case .weekly:
                        previousStart = calendar.date(byAdding: .day, value: -7, to: currentStart) ?? currentStart
                    case .monthly:
                        previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
                    case .custom:
                        // A one-off window has no "previous period" —
                        // the comparison line simply doesn't render.
                        continue
                    }

                    // Refund-aware and floored at 0, mirroring the live
                    // progress computation in BudgetViewModel.
                    let raw = expenses.reduce(0.0) { partial, expense in
                        guard expense.date >= previousStart && expense.date < currentStart else { return partial }
                        let matches: Bool
                        switch budget.categoryFilter {
                        case .overall:
                            matches = true
                        case .defaultCategory(let rawValue):
                            matches = expense.category.rawValue == rawValue
                        case .customCategory(let id):
                            matches = expense.category == .custom && expense.customCategoryId == id
                        }
                        guard matches else { return partial }
                        return partial + (expense.amount.isFinite ? expense.signedAmount : 0)
                    }
                    map[budget.id] = max(0, raw)
                }
                return map
            }.value

            guard !Task.isCancelled else { return }
            lastPeriodSpent = result
        }
    }
}

// MARK: - Budget card

/// One budget in the manage list. Active budgets get the full readout
/// (status pill, hero amounts, pace bar, stats footer); paused budgets
/// collapse to a compact muted row since no progress is computed for
/// them.
private struct BudgetOverviewCard: View {
    let budget: Budget
    let progress: BudgetViewModel.BudgetProgress
    /// Spend in the previous period, or `nil` while not yet computed
    /// (store still hydrating) — the comparison line simply hides.
    let lastPeriodSpent: Double?
    let formattedAmount: (Double) -> String
    let currency: Expense.Currency
    let onTap: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    // MARK: Status mapping (mirrors BudgetProgressCard / BudgetMiniCard
    // so the manage list and the Home cards read as one family).

    private var statusColor: Color {
        if budget.hasEnded {
            return progress.status == .exceeded ? .red : .green
        }
        switch progress.status {
        case .safe:     return .appPrimary
        case .warning:  return .orange
        case .exceeded: return .red
        }
    }

    private var statusLabel: String {
        // A finished custom window gets a verdict, not a live status —
        // "Heads Up" on a trip that's over would be nonsense.
        if budget.hasEnded {
            return progress.status == .exceeded ? "Went Over" : "Stayed Under"
        }
        switch progress.status {
        case .safe:     return "On Track"
        case .warning:  return "Heads Up"
        case .exceeded: return "Over Budget"
        }
    }

    private var statusIcon: String {
        if budget.hasEnded {
            return progress.status == .exceeded ? "exclamationmark.octagon.fill" : "checkmark.seal.fill"
        }
        switch progress.status {
        case .safe:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .exceeded: return "exclamationmark.octagon.fill"
        }
    }

    /// Fraction of the period already gone (0…1) — the pace reference
    /// the tick on the progress bar marks.
    private var elapsedFraction: Double {
        guard progress.totalDays > 0 else { return 0 }
        let elapsed = Double(progress.totalDays - progress.daysRemaining)
        return min(1, max(0, elapsed / Double(progress.totalDays)))
    }

    /// Spent % vs period-elapsed %: more than ~8 points apart in either
    /// direction reads as genuinely ahead/under rather than noise.
    private var paceLabel: String {
        let diff = progress.percentage - elapsedFraction
        if diff > 0.08 { return "Ahead of pace" }
        if diff < -0.08 { return "Under pace" }
        return "On pace"
    }

    private var periodNoun: String {
        switch budget.period {
        case .weekly:  return "week"
        case .monthly: return "month"
        case .custom:  return "period"
        }
    }

    /// Second caption line: period name for the rolling cases, the
    /// actual date window for a custom budget ("20 Jul – 27 Jul") —
    /// the word "Custom" alone tells the user nothing at a glance.
    private var periodCaption: String {
        switch budget.period {
        case .weekly, .monthly:
            return budget.period.rawValue
        case .custom:
            return Self.formattedWindow(budget)
        }
    }

    static func formattedWindow(_ budget: Budget) -> String {
        let cal = Calendar.current
        let start = budget.dateRange.start
        let lastDay = cal.date(byAdding: .day, value: -1, to: budget.dateRange.end) ?? start
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(start.formatted(style)) – \(lastDay.formatted(style))"
    }

    // MARK: Body

    var body: some View {
        Button(action: onTap) {
            if budget.isActive {
                activeCard
            } else {
                pausedRow
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                HapticManager.shared.selectionChanged()
                onToggle()
            } label: {
                Label(budget.isActive ? "Pause" : "Resume", systemImage: budget.isActive ? "pause.circle" : "play.circle")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Budget?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                HapticManager.shared.success()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(budget.name)\" will be removed. Your expenses stay untouched.")
        }
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Active layout

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            headerRow
            heroRow
            AnimatedProgressBar(
                fraction: progress.percentage,
                tint: statusColor,
                paceTick: elapsedFraction
            )
            paceRow

            Divider()
                .overlay(Color.primary.opacity(0.06))
                .padding(.top, Theme.Spacing.xxs)

            footerRow
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Warning/over states paint a tinted ring over the default
        // glass edge — same treatment as BudgetProgressCard on Home.
        .cardSurface(
            stroke: progress.status == .safe ? nil : statusColor.opacity(0.35),
            strokeWidth: 1
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: budget.categoryFilter.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(budget.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(budget.categoryFilter.displayName) · \(periodCaption)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(statusColor)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(Capsule().fill(statusColor.opacity(0.12)))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(formattedAmount(progress.spent))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .moneyAnimation(amount: progress.spent, currency: currency)

            Text("of \(formattedAmount(progress.limit))")
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: Theme.Spacing.sm)

            Text("\(Int(min(progress.percentage * 100, 999)))%")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundColor(statusColor)
                .contentTransition(.numericText())
                .animation(Theme.Motion.snappy, value: progress.percentage)
        }
    }

    /// Pace readout under the bar ("On pace · 55% of month gone") plus
    /// the last-period comparison when available. Deliberately quiet —
    /// the tick on the bar and the status pill carry the urgency.
    private var paceRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: budget.hasEnded ? "flag.checkered" : "gauge.with.needle")
                    .font(.system(size: 10, weight: .semibold))
                if budget.hasEnded {
                    // A finished window has no "pace" — report the
                    // outcome instead ("Ended · finished at 84%").
                    Text("Ended · finished at \(Int(min(progress.percentage * 100, 999)))%")
                        .font(.caption2.weight(.medium))
                } else {
                    Text("\(paceLabel) · \(Int((elapsedFraction * 100).rounded()))% of \(periodNoun) gone")
                        .font(.caption2.weight(.medium))
                }
            }
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: Theme.Spacing.sm)

            if let lastPeriodSpent, lastPeriodSpent > 0 {
                Text("Last \(periodNoun): \(formattedAmount(lastPeriodSpent))")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var footerRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            if progress.status == .exceeded {
                footerStat(
                    value: formattedAmount(progress.spent - progress.limit),
                    label: "Over by",
                    valueColor: .red
                )
            } else {
                footerStat(
                    value: formattedAmount(progress.remainingBudget),
                    label: "Left"
                )
            }

            statDivider

            footerStat(
                value: formattedAmount(progress.dailyAllowance),
                label: "Per day"
            )

            statDivider

            footerStat(
                value: "\(progress.daysRemaining)",
                label: progress.daysRemaining == 1 ? "Day left" : "Days left"
            )
        }
    }

    private func footerStat(value: String, label: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    // MARK: Paused layout

    /// No progress is computed for paused budgets, so the card drops
    /// to a compact muted row: identity + limit, with the Resume
    /// affordance living in the context menu.
    private var pausedRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: budget.categoryFilter.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(budget.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("\(formattedAmount(budget.amount)) · \(periodCaption) limit")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text("Paused")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, Theme.Spacing.sm + 2)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.Radius.row)
        .opacity(0.85)
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        guard budget.isActive else {
            return "\(budget.name), paused, \(formattedAmount(budget.amount)) \(budget.period.rawValue.lowercased()) limit"
        }
        var parts = [
            budget.name,
            "\(formattedAmount(progress.spent)) of \(formattedAmount(progress.limit))",
            statusLabel,
            paceLabel
        ]
        if progress.daysRemaining > 0 {
            parts.append("\(progress.daysRemaining) days left")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Animated progress bar

/// Capsule progress bar with a first-appear sweep and an optional
/// pace tick marking how much of the period has elapsed — spent-fill
/// ahead of the tick means spending ahead of schedule, behind means
/// breathing room. Shared by the summary card and the budget cards.
private struct AnimatedProgressBar: View {
    let fraction: Double
    let tint: Color
    /// 0…1 position of the pace tick, or `nil` to omit it.
    let paceTick: Double?

    /// Drives the first-render sweep: fill animates 0 → value instead
    /// of snapping (next-runloop flip, same trick as the verdict ring).
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(CGFloat(fraction), 1.0))
            let fillWidth = appeared ? geo.size.width * clamped : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.12))

                Capsule()
                    .fill(tint)
                    .frame(width: fillWidth)
                    .animation(Theme.Motion.emphasized, value: fillWidth)

                if let paceTick, paceTick > 0.03, paceTick < 0.97 {
                    Capsule()
                        .fill(Color.primary.opacity(0.3))
                        .frame(width: 2, height: 6)
                        .offset(x: geo.size.width * CGFloat(paceTick) - 1)
                }
            }
        }
        .frame(height: 6)
        .onAppear {
            if !appeared {
                Task { @MainActor in appeared = true }
            }
        }
    }
}
