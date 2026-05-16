import SwiftUI

/// Subscriptions tab. Shows a glanceable hero (monthly total + what's next + mini
/// stats), a segmented filter strip, and a sectioned list of subscriptions
/// (Due Soon / Later / Paused).
struct SubscriptionsView: View {
    @ObservedObject var expenseViewModel: ExpenseViewModel
    @StateObject private var subscriptionViewModel: SubscriptionViewModel
    @State private var showingAddSubscription = false
    @State private var selectedSubscription: Subscription?
    @State private var showingMonthlyBreakdown = false
    @State private var animateCards = false

    @Namespace private var filterNamespace

    init(expenseViewModel: ExpenseViewModel) {
        self.expenseViewModel = expenseViewModel
        _subscriptionViewModel = StateObject(
            wrappedValue: SubscriptionViewModel(expenseViewModel: expenseViewModel)
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection

                    VStack(spacing: Theme.Spacing.xl) {
                        heroCard
                            .modifier(SubEntrance(order: 0, animate: animateCards))

                        filterStrip
                            .modifier(SubEntrance(order: 1, animate: animateCards))

                        listSection
                            .modifier(SubEntrance(order: 2, animate: animateCards))
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.tabBarInset)
                }
            }
            .background(Color.systemBackground)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            guard !animateCards else { return }
            withAnimation(Theme.Motion.emphasized) { animateCards = true }
        }
        .sheet(isPresented: $showingAddSubscription) {
            AddSubscriptionView(subscriptionViewModel: subscriptionViewModel)
                .environmentObject(expenseViewModel)
        }
        .sheet(item: $selectedSubscription) { subscription in
            AddSubscriptionView(
                subscriptionViewModel: subscriptionViewModel,
                editingSubscription: subscription
            )
            .environmentObject(expenseViewModel)
        }
        .sheet(isPresented: $showingMonthlyBreakdown) {
            MonthlySpendingBreakdownSheet(
                subscriptions: subscriptionViewModel.subscriptions.filter { $0.isActive },
                currency: expenseViewModel.selectedCurrency,
                formattedTotal: subscriptionViewModel
                    .formattedTotalMonthlyAmount(currency: expenseViewModel.selectedCurrency)
            )
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Theme.Spacing.xl)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Subscriptions")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(.primary)

                    Text(activeCountLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .contentTransition(.numericText())
                }

                Spacer()

                addButton
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Color.systemBackground)
    }

    private var activeCountLabel: String {
        let active = subscriptionViewModel.activeSubscriptionsCount
        return "\(active) active subscription\(active == 1 ? "" : "s")"
    }

    private var addButton: some View {
        Button {
            HapticManager.shared.lightTap()
            showingAddSubscription = true
        } label: {
            HStack(spacing: Theme.Spacing.xs + 2) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(Color.appPrimary)
            .clipShape(Capsule())
            .primaryGlow()
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Hero

    /// The "what does all this cost?" card. Shows:
    /// 1. Monthly total (headline, animated) + info button → breakdown sheet.
    /// 2. Next-up preview ("Next: Netflix · tomorrow · $15.99") — highest
    ///    value glance info answering the common "what's coming out next?".
    /// 3. Three mini stats: Yearly cost, Due this week, Per-sub average.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Per month")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                Button {
                    HapticManager.shared.lightTap()
                    showingMonthlyBreakdown = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Monthly Spending")
            }

            Text(subscriptionViewModel
                .formattedTotalMonthlyAmount(currency: expenseViewModel.selectedCurrency))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .moneyAnimation(amount: subscriptionViewModel.totalMonthlyAmount,
                                currency: expenseViewModel.selectedCurrency)

            if let next = nextUpSubscription {
                nextUpRow(next)
            }

            if !subscriptionViewModel.subscriptions.filter({ $0.isActive }).isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.06))

                miniStatsRow
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .softShadow()
    }

    private func nextUpRow(_ sub: Subscription) -> some View {
        let tint = Color.forCategory(sub.category.color)
        let whenText = relativeDueText(for: sub)

        return HStack(spacing: Theme.Spacing.sm + 2) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 30, height: 30)
                Image(systemName: sub.category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Next up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Text("\(sub.name) · \(whenText)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Text(sub.formattedAmount)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    private var miniStatsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            miniStat(
                label: "Yearly",
                value: yearlyFormatted,
                icon: "calendar"
            )

            divider

            miniStat(
                label: "Due 7d",
                value: "\(subscriptionViewModel.upcomingSubscriptions.count)",
                icon: "clock"
            )

            divider

            miniStat(
                label: "Average",
                value: averageFormatted,
                icon: "arrow.up.arrow.down"
            )
        }
    }

    private func miniStat(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 28)
    }

    // MARK: - Filter strip

    /// Segmented pill filter replacing the old KPI-looking chip row. Uses
    /// `matchedGeometryEffect` so the selection moves between chips instead of
    /// fading in and out.
    private var filterStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            filterPill(.all, title: "All", count: subscriptionViewModel.subscriptions.count)
            filterPill(.active, title: "Active", count: subscriptionViewModel.activeSubscriptionsCount)
            filterPill(.dueSoon, title: "Due Soon", count: subscriptionViewModel.upcomingSubscriptions.count)
        }
    }

    private func filterPill(
        _ filter: SubscriptionViewModel.SubscriptionFilter,
        title: String,
        count: Int
    ) -> some View {
        let isSelected = subscriptionViewModel.activeFilter == filter

        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                if filter == .all {
                    subscriptionViewModel.clearFilter()
                } else if subscriptionViewModel.activeFilter == filter {
                    subscriptionViewModel.clearFilter()
                } else {
                    subscriptionViewModel.setFilter(filter)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? Color.white.opacity(0.25)
                                    : Color.primary.opacity(0.08)
                            )
                        )
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.appPrimary)
                            .matchedGeometryEffect(id: "filterSelection", in: filterNamespace)
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
            .shadow(
                color: isSelected ? Color.appPrimary.opacity(0.25) : .clear,
                radius: isSelected ? 6 : 0,
                x: 0,
                y: isSelected ? 3 : 0
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    @ViewBuilder
    private var listSection: some View {
        if subscriptionViewModel.subscriptions.isEmpty {
            emptyStateView
                .padding(.top, Theme.Spacing.xl)
        } else {
            let results = filteredResults

            if results.isEmpty {
                filterEmptyState
            } else {
                subscriptionsList(results)
            }
        }
    }

    private var filteredResults: [Subscription] {
        subscriptionViewModel.activeFilter == .all
            ? subscriptionViewModel.subscriptions
            : subscriptionViewModel.filteredSubscriptions
    }

    private func subscriptionsList(_ subs: [Subscription]) -> some View {
        let dueSoon = subs.filter { $0.isActive && $0.daysUntilNext <= 7 }
        let later = subs.filter { $0.isActive && $0.daysUntilNext > 7 }
        let paused = subs.filter { !$0.isActive }

        return LazyVStack(spacing: Theme.Spacing.md) {
            if subscriptionViewModel.activeFilter == .all {
                if !dueSoon.isEmpty {
                    subsectionHeader("Due Soon", count: dueSoon.count)
                    rows(for: dueSoon)
                }
                if !later.isEmpty {
                    subsectionHeader("Later", count: later.count)
                    rows(for: later)
                }
                if !paused.isEmpty {
                    subsectionHeader("Paused", count: paused.count)
                    rows(for: paused)
                }
            } else {
                rows(for: subs)
            }
        }
    }

    private func rows(for subs: [Subscription]) -> some View {
        ForEach(subs) { subscription in
            SubscriptionRow(
                subscription: subscription,
                monthlyEquivalentText: subscriptionViewModel
                    .formattedMonthlyEquivalent(for: subscription),
                onToggle: {
                    Task { await subscriptionViewModel.toggleSubscriptionStatus(subscription) }
                },
                onEdit: {
                    selectedSubscription = subscription
                },
                onMarkPaid: subscription.isActive && subscription.daysUntilNext <= 0 ? {
                    Task { await subscriptionViewModel.markSubscriptionAsPaid(subscription) }
                } : nil,
                onDelete: {
                    subscriptionViewModel.deleteSubscription(subscription)
                }
            )
        }
    }

    private func subsectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )

            Spacer()
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, 2)
    }

    // MARK: - Empty states

    private var emptyStateView: some View {
        EmptyStatePanel(
            icon: "creditcard.and.123",
            title: "No Subscriptions Yet",
            message: "Track recurring expenses like Netflix, Spotify, or the gym — and never miss a payment."
        ) {
            PrimaryGradientButton(title: "Add Your First Subscription", icon: "plus.circle.fill", width: .hug) {
                HapticManager.shared.mediumTap()
                showingAddSubscription = true
            }
        }
    }

    private var filterEmptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: subscriptionViewModel.activeFilter.icon)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, Theme.Spacing.xxl)

            Text("No \(subscriptionViewModel.activeFilter.title.lowercased()) subscriptions")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Button {
                withAnimation(Theme.Motion.snappy) {
                    subscriptionViewModel.clearFilter()
                }
            } label: {
                Text("Show All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.appPrimary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    // MARK: - Derived values

    /// The next upcoming active subscription (earliest `nextDueDate`). `nil`
    /// when nothing is active.
    private var nextUpSubscription: Subscription? {
        subscriptionViewModel.subscriptions
            .filter { $0.isActive }
            .min(by: { $0.nextDueDate < $1.nextDueDate })
    }

    private func relativeDueText(for sub: Subscription) -> String {
        let days = sub.daysUntilNext
        if days < 0 { return "overdue" }
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        if days <= 6 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE"
            return "in \(days) days · \(weekdayFormatter.string(from: sub.nextDueDate))"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: sub.nextDueDate)
    }

    private var yearlyFormatted: String {
        let yearly = subscriptionViewModel.totalMonthlyAmount * 12
        return formatCurrency(yearly)
    }

    private var averageFormatted: String {
        let active = subscriptionViewModel.subscriptions.filter { $0.isActive }
        guard !active.isEmpty else { return formatCurrency(0) }
        let avg = subscriptionViewModel.totalMonthlyAmount / Double(active.count)
        return formatCurrency(avg)
    }

    private func formatCurrency(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = value >= 100 ? 0 : 2
        nf.minimumFractionDigits = value >= 100 ? 0 : 2
        let str = nf.string(from: NSNumber(value: value)) ?? "0"
        return "\(expenseViewModel.selectedCurrency.symbol)\(str)"
    }
}

// MARK: - Entrance animation

/// Cascading spring-based entrance, mirroring the Statistics page so the whole
/// app shares one "section appears" motion.
private struct SubEntrance: ViewModifier {
    let order: Int
    let animate: Bool
    private var delay: Double { Double(order) * 0.07 }

    func body(content: Content) -> some View {
        content
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 12)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0).delay(delay),
                value: animate
            )
    }
}

// MARK: - Monthly Breakdown Sheet

/// Bottom-sheet for the hero info button. Matches the visual language of
/// `InsightExplanationSheet` (medallion header + "What it means" / "How it's
/// calculated" prose sections) *plus* a grouped breakdown showing every active
/// subscription's contribution to the monthly total, split by billing frequency
/// so the math is glanceable.
private struct MonthlySpendingBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    let subscriptions: [Subscription]
    let currency: Expense.Currency
    let formattedTotal: String

    /// Deterministic order for the frequency groups.
    private static let frequencyOrder: [Subscription.Frequency] = [
        .daily, .weekly, .monthly, .quarterly, .yearly
    ]

    private var grouped: [(Subscription.Frequency, [Subscription])] {
        let dict = Dictionary(grouping: subscriptions, by: { $0.frequency })
        return Self.frequencyOrder.compactMap { freq in
            guard let subs = dict[freq], !subs.isEmpty else { return nil }
            return (freq, subs.sorted { monthlyEquivalent(for: $0).value > monthlyEquivalent(for: $1).value })
        }
    }

    private func monthlyEquivalent(for subscription: Subscription) -> (value: Double, formula: String) {
        switch subscription.frequency {
        case .daily:
            return (subscription.amount * 30, "\(currency.symbol)\(format(subscription.amount)) × 30")
        case .weekly:
            return (subscription.amount * 4.33, "\(currency.symbol)\(format(subscription.amount)) × 4.33")
        case .monthly:
            return (subscription.amount, "\(currency.symbol)\(format(subscription.amount))")
        case .quarterly:
            return (subscription.amount / 3, "\(currency.symbol)\(format(subscription.amount)) ÷ 3")
        case .yearly:
            return (subscription.amount / 12, "\(currency.symbol)\(format(subscription.amount)) ÷ 12")
        }
    }

    private func format(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        return nf.string(from: NSNumber(value: value)) ?? "0.00"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header
                    totalCard
                    explanationSections
                    breakdownSection
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.systemBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            Text("Monthly Spending")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Total Card

    private var totalCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ESTIMATED TOTAL")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.6)

                Text(formattedTotal)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(subscriptions.count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(subscriptions.count == 1 ? "active sub" : "active subs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .softShadow()
    }

    // MARK: - Explanation

    private var explanationSections: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            explanationRow(
                label: "What it means",
                body: "Your recurring costs normalized to a single month — so a $120 yearly sub counts as $10/mo alongside your $15/mo subscriptions, and the total reflects the true monthly drag."
            )

            explanationRow(
                label: "How it's calculated",
                body: "Daily × 30, weekly × 4.33 (average weeks per month), monthly as-is, quarterly ÷ 3, yearly ÷ 12. Only active subscriptions are counted — paused ones are excluded."
            )
        }
    }

    private func explanationRow(label: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.6)

            Text(body)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Breakdown

    @ViewBuilder
    private var breakdownSection: some View {
        if !subscriptions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("BREAKDOWN")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.6)

                VStack(spacing: Theme.Spacing.lg) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { _, pair in
                        frequencyGroupCard(frequency: pair.0, subs: pair.1)
                    }
                }
            }
        }
    }

    private func frequencyGroupCard(frequency: Subscription.Frequency, subs: [Subscription]) -> some View {
        let groupTotal = subs.reduce(0.0) { $0 + monthlyEquivalent(for: $1).value }

        return VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: frequency.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.appPrimary)

                Text(frequency.rawValue)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("·")
                    .foregroundColor(.secondary)

                Text(subs.count == 1 ? "1 sub" : "\(subs.count) subs")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(currency.symbol)\(format(groupTotal))/mo")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.appPrimary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)

            Divider().padding(.horizontal, Theme.Spacing.lg)

            VStack(spacing: 0) {
                ForEach(Array(subs.enumerated()), id: \.element.id) { idx, sub in
                    breakdownRow(sub)

                    if idx < subs.count - 1 {
                        Divider().padding(.leading, Theme.Spacing.lg)
                    }
                }
            }
        }
        .cardSurface()
        .softShadow()
    }

    private func breakdownRow(_ sub: Subscription) -> some View {
        let eq = monthlyEquivalent(for: sub)
        let tint = Color.forCategory(sub.category.color)

        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 32, height: 32)

                Image(systemName: sub.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if sub.frequency != .monthly {
                    Text(eq.formula)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text("\(currency.symbol)\(format(eq.value))")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }
}

// MARK: - Preview

#Preview {
    SubscriptionsView(expenseViewModel: ExpenseViewModel())
        .environmentObject(CategoryViewModel())
}
