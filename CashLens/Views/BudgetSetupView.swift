import SwiftUI
import UserNotifications

/// Add / Edit Budget screen.
///
/// v2 design — visual twin of `AddExpenseView` and `AddSubscriptionView`.
/// Same polished header, same centered hero amount tile (with the
/// **period** selector pill where AddExpense puts the payment pill
/// and AddSubscription puts the frequency pill), same placeholder-
/// driven name field, same usage-sorted horizontal "Apply To" row
/// (with an "All Spending" lead tile in place of the Browse tile),
/// and the same solid bottom CTA strip.
///
/// Alerts stay visible (not in a collapsible) — they're the *raison
/// d'être* of a budget, so hiding them behind a "More options"
/// disclosure would undersell the feature. They render in the same
/// elevated card style More options uses elsewhere so the visual
/// rhythm matches the other add-sheets.
struct BudgetSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager

    // MARK: - State

    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var period: Budget.Period = .monthly
    @State private var categoryFilter: Budget.CategoryFilter = .overall

    /// Custom-window dates, only persisted when `period == .custom`.
    /// Defaults: today → a week out (a typical short trip), adjusted
    /// in `loadEditingData` when editing an existing custom budget.
    @State private var customStart: Date = Calendar.current.startOfDay(for: Date())
    @State private var customEnd: Date = Calendar.current.date(
        byAdding: .day, value: 6,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var alertAt80 = true
    @State private var alertAt100 = true
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var showingCategoryPicker = false
    @State private var showingProPaywall = false

    /// In-context notification ask (moved here from onboarding in
    /// Wave 3): after the user saves a budget *with alerts enabled*
    /// and the system permission has never been requested, a brief
    /// pre-permission card explains why before the one-shot iOS
    /// prompt. Shown at most once ever — the `.notDetermined` gate
    /// clears permanently after the first system prompt.
    @State private var showingNotificationPrePermission = false

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, amount }

    // MARK: - Init

    var editingBudget: Budget?
    var isEditing: Bool { editingBudget != nil }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerStrip
                formScrollContent
                saveButton
            }

            if showingNotificationPrePermission {
                notificationPrePermissionOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
        }
        .animation(Theme.Motion.tap, value: showingNotificationPrePermission)
        .navigationBarHidden(true)
        // App-wide sheet convention: visible grab handle on every
        // custom-chrome sheet, with the header giving it clear air.
        .presentationDragIndicator(.visible)
        .onAppear {
            // One overall budget is free. Setup only bounces a
            // non-Pro user when they'd be *creating* a second
            // budget — editing an existing budget (including
            // grandfathered extras from a lapsed trial) is always
            // allowed. Per-category filters and weekly periods
            // stay Pro and are gated inline with lock chips.
            if !proManager.isPro && !isEditing && !budgetViewModel.budgets.isEmpty {
                dismiss()
                return
            }
            loadEditingData()
        }
        .alert("Delete Budget?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let budget = editingBudget {
                    budgetViewModel.deleteBudget(budget)
                }
                HapticManager.shared.success()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showingCategoryPicker) {
            categoryPickerSheet
        }
        .sheet(isPresented: $showingProPaywall) {
            PaywallView(context: .budgets)
        }
    }

    // MARK: - Free-tier gating

    /// Free tier: budgets apply to All Spending only. A non-Pro user
    /// may still keep the category filter their existing budget
    /// already targets (grandfathered — never claw back).
    private func canSelectFilter(_ filter: Budget.CategoryFilter) -> Bool {
        if proManager.isPro { return true }
        if filter == .overall { return true }
        return filter == editingBudget?.categoryFilter
    }

    /// Free tier: monthly is the free period; weekly stays Pro.
    /// A budget that is already weekly keeps its period (grandfather).
    private func canSelectPeriod(_ p: Budget.Period) -> Bool {
        if proManager.isPro { return true }
        if p == .monthly { return true }
        return editingBudget?.period == p
    }

    private func presentProPaywall() {
        HapticManager.shared.warning()
        showingProPaywall = true
    }

    /// Tiny lock badge for Pro-locked tiles — same visual as the
    /// theme / icon picker lock badges.
    private var tileLockBadge: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 18, height: 18)
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.appPrimary)
        }
        .overlay(Circle().stroke(Color.appPrimary.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Header (shared SheetHeader convention)

    private var headerStrip: some View {
        SheetHeader(
            eyebrow: "Budget",
            title: isEditing ? "Editing" : "Add New",
            onClose: { dismiss() }
        ) {
            headerTrailingSlot
        }
    }

    @ViewBuilder
    private var headerTrailingSlot: some View {
        if isEditing {
            Button {
                HapticManager.shared.warning()
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.red.opacity(0.22), lineWidth: 0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete this budget")
        } else {
            SheetHeaderSpacer()
        }
    }

    // MARK: - Form scroll content

    private var formScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.xxxl) {
                heroAmountTile
                if period == .custom {
                    customDatesCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                compactNameField
                applyToRow
                alertsSection
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Theme.Motion.snappy, value: period)
        .animation(Theme.Motion.snappy, value: alertAt80)
        .animation(Theme.Motion.snappy, value: alertAt100)
    }

    // MARK: - Hero amount tile (twin)

    private var heroAmountTile: some View {
        VStack(spacing: Theme.Spacing.lg) {
            periodSelectorPill
            heroAmountEyebrow
            heroAmountValueRow

            // Inline footnote so the user can read back the budget at
            // a glance: "₹5,000 every week · resets in 3 days". Same
            // pattern as AddSubscription's "Next bill" line.
            Text(periodFootnoteText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xxl)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.lightTap()
            focusedField = .amount
        }
        .animation(Theme.Motion.snappy, value: focusedField == .amount)
    }

    /// Period (Weekly / Monthly) selector — sits where AddExpense
    /// puts the payment pill and AddSubscription puts the frequency
    /// pill. Same shape, same Menu pattern.
    private var periodSelectorPill: some View {
        Menu {
            ForEach(Budget.Period.allCases, id: \.self) { p in
                Button {
                    if canSelectPeriod(p) {
                        HapticManager.shared.lightTap()
                        period = p
                    } else {
                        presentProPaywall()
                    }
                } label: {
                    if period == p {
                        Label(periodDisplayName(p), systemImage: "checkmark")
                    } else if !canSelectPeriod(p) {
                        Label("\(periodDisplayName(p)) — Pro", systemImage: "lock.fill")
                    } else {
                        Label(periodDisplayName(p), systemImage: p.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: period.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text(periodDisplayName(period))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
        .accessibilityLabel("Budget period: \(periodDisplayName(period)). Tap to change.")
    }

    /// "Custom" alone doesn't explain itself in a menu — spell out
    /// what the option does. Weekly/Monthly pass through unchanged.
    private func periodDisplayName(_ p: Budget.Period) -> String {
        p == .custom ? "Custom Dates" : p.rawValue
    }

    // MARK: - Custom dates card

    /// Two compact date rows shown only for custom-window budgets.
    /// The End picker's lower bound tracks the Start date so an
    /// inverted range can't be entered in the first place.
    private var customDatesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Starts", systemImage: "calendar")
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Spacer()
                DatePicker(
                    "",
                    selection: $customStart,
                    displayedComponents: .date
                )
                .labelsHidden()
                .onChange(of: customStart) { _, newStart in
                    if customEnd < newStart { customEnd = newStart }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)

            Divider().padding(.leading, Theme.Spacing.xl)

            HStack {
                Label("Ends", systemImage: "calendar.badge.checkmark")
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Spacer()
                DatePicker(
                    "",
                    selection: $customEnd,
                    in: customStart...,
                    displayedComponents: .date
                )
                .labelsHidden()
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
        }
        .cardSurface()
    }

    private var heroAmountEyebrow: some View {
        Text("BUDGET LIMIT")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(1.4)
            .padding(.horizontal, Theme.Spacing.xl)
    }

    /// Centered hero amount with the ghost-mirror optical-centering
    /// trick borrowed from AddExpense.
    private var heroAmountValueRow: some View {
        ZStack {
            TextField("", text: $amount)
                .focused($focusedField, equals: .amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .opacity(0.001)
                .frame(maxWidth: .infinity, minHeight: 80)
                .allowsHitTesting(false)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(expenseViewModel.selectedCurrency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)

                Text(displayAmount)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(displayAmount == "0" ? .primary.opacity(0.25) : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .contentTransition(.numericText())

                Text(expenseViewModel.selectedCurrency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.clear)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var displayAmount: String {
        amount.isEmpty ? "0" : amount
    }

    /// Short read-back of what the user is configuring. Communicates
    /// the period reset cadence and (when editing) the days left in
    /// the current period.
    private var periodFootnoteText: String {
        switch period {
        case .weekly:
            // `Budget.dateRange` anchors weeks on the locale's
            // first weekday, so the copy must match — "Monday" was wrong
            // for US users (Sunday), and others.
            let calendar = Calendar.current
            let index = (calendar.firstWeekday - 1) % 7
            let weekdayName = calendar.standaloneWeekdaySymbols[index]
            return "Resets every \(weekdayName)"
        case .monthly:
            return "Resets on the 1st of every month"
        case .custom:
            let cal = Calendar.current
            let start = cal.startOfDay(for: customStart)
            let end = cal.startOfDay(for: customEnd)
            let days = (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            return "\(start.formatted(style)) – \(end.formatted(style)) · \(days) day\(days == 1 ? "" : "s") · doesn't repeat"
        }
    }

    // MARK: - Compact name field (twin)

    private var compactNameField: some View {
        TextField(namePlaceholder, text: $name)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .fieldCard(isFocused: focusedField == .name)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .name }
    }

    /// Period-aware example so a trip budget suggests itself.
    private var namePlaceholder: String {
        switch period {
        case .weekly:  return "e.g. Weekly Groceries"
        case .monthly: return "e.g. Monthly Spending"
        case .custom:  return "e.g. Goa Trip"
        }
    }

    // MARK: - Apply To row (smart category row)

    /// Horizontal scroll matching AddExpense's `smartCategoryRow` —
    /// uses the same 56pt circle tiles for visual parity. The
    /// **"All Spending"** tile replaces the AddExpense "Browse" tile
    /// at the *front* of the row because it's the recommended
    /// default for a brand-new budget. A Browse tile still lives at
    /// the end for users who want the full picker.
    private var applyToRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Apply To")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                // Surface the current pick as a small descriptor on
                // the right so the user doesn't have to scan the
                // scroll to confirm what's selected.
                Text(currentFilterLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .lineLimit(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md + 2) {
                    allSpendingTile.frame(width: 70)

                    ForEach(expenseViewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        categoryTile(category).frame(width: 70)
                    }

                    ForEach(categoryViewModel.customCategories) { category in
                        customCategoryTile(category).frame(width: 70)
                    }

                    browseCategoriesTile.frame(width: 70)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    /// Friendly read-back of the current categoryFilter for the right-
    /// aligned label above the scroll.
    private var currentFilterLabel: String {
        switch categoryFilter {
        case .overall:
            return "All Spending"
        case .defaultCategory(let raw):
            return Expense.Category(rawValue: raw)?.rawValue.capitalized ?? raw
        case .customCategory(let id):
            return categoryViewModel.customCategories.first(where: { $0.id == id })?.name ?? "Custom"
        }
    }

    /// "All Spending" lead tile — replaces the per-category circles
    /// for budgets that should sum every expense. Renders with the
    /// app's primary tint so it stands apart from the per-category
    /// tiles and reads as "the default".
    private var allSpendingTile: some View {
        let isSelected = categoryFilter == .overall
        return Button {
            HapticManager.shared.selectionChanged()
            categoryFilter = .overall
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(isSelected ? 0.30 : 0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }
                .overlay(
                    Circle().stroke(
                        isSelected ? Color.appPrimary.opacity(0.9) : Color.clear,
                        lineWidth: 2.5
                    )
                )

                Text("All")
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .appPrimary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryTile(_ category: Expense.Category) -> some View {
        let filter = Budget.CategoryFilter.defaultCategory(category.rawValue)
        let isSelected = categoryFilter == filter
        let isLocked = !canSelectFilter(filter)
        let tint = Color.forCategory(category.color)
        return Button {
            if isLocked {
                presentProPaywall()
            } else {
                HapticManager.shared.selectionChanged()
                categoryFilter = filter
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isSelected ? 0.30 : 0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(tint)
                }
                .overlay(
                    Circle().stroke(
                        isSelected ? tint.opacity(0.9) : Color.clear,
                        lineWidth: 2.5
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if isLocked { tileLockBadge }
                }

                Text(category.rawValue.capitalized)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tint : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func customCategoryTile(_ category: CustomCategory) -> some View {
        let filter = Budget.CategoryFilter.customCategory(category.id)
        let isSelected = categoryFilter == filter
        let isLocked = !canSelectFilter(filter)
        let tint = Color.forCategory(category.colorName)
        return Button {
            if isLocked {
                presentProPaywall()
            } else {
                HapticManager.shared.selectionChanged()
                categoryFilter = filter
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isSelected ? 0.30 : 0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(tint)
                }
                .overlay(
                    Circle().stroke(
                        isSelected ? tint.opacity(0.9) : Color.clear,
                        lineWidth: 2.5
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if isLocked { tileLockBadge }
                }

                Text(category.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tint : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Trailing Browse tile — opens the full category picker sheet
    /// when the inline scroll feels too long.
    private var browseCategoriesTile: some View {
        Button {
            HapticManager.shared.lightTap()
            showingCategoryPicker = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.10))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle().stroke(Color.appPrimary.opacity(0.25),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        )
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.appPrimary)
                }
                Text("Browse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse all categories")
    }

    private var categoryPickerSheet: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm + 2, alignment: .top),
                    count: 4
                )

                LazyVGrid(columns: columns, alignment: .center, spacing: Theme.Spacing.lg) {
                    // "All Spending" sits first in the grid too — it's
                    // the budget-screen equivalent of the front-of-row
                    // pinned tile.
                    Button {
                        HapticManager.shared.selectionChanged()
                        categoryFilter = .overall
                        showingCategoryPicker = false
                    } label: {
                        allSpendingTile.allowsHitTesting(false)
                    }
                    .buttonStyle(.plain)

                    ForEach(expenseViewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        Button {
                            let filter = Budget.CategoryFilter.defaultCategory(category.rawValue)
                            if canSelectFilter(filter) {
                                HapticManager.shared.selectionChanged()
                                categoryFilter = filter
                                showingCategoryPicker = false
                            } else {
                                showingCategoryPicker = false
                                presentProPaywall()
                            }
                        } label: {
                            categoryTile(category).allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(categoryViewModel.customCategories, id: \.id) { category in
                        Button {
                            let filter = Budget.CategoryFilter.customCategory(category.id)
                            if canSelectFilter(filter) {
                                HapticManager.shared.selectionChanged()
                                categoryFilter = filter
                                showingCategoryPicker = false
                            } else {
                                showingCategoryPicker = false
                                presentProPaywall()
                            }
                        } label: {
                            customCategoryTile(category).allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Apply Budget To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingCategoryPicker = false }
                        .fontWeight(.semibold)
                        .foregroundColor(.appPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Alerts (always visible — the budget's raison d'être)

    /// Alerts stay out of "More options" because they're the entire
    /// reason most users set a budget. Rendered as bare rows inside
    /// one `cardSurface()` matching More options' contents so the
    /// visual rhythm still aligns with AddExpense / AddSubscription.
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Text("Alerts")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text("(Optional)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                alertRow(
                    label: "At 80% spent",
                    sublabel: "Heads-up as you approach the limit",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    isOn: $alertAt80
                )

                Divider().padding(.leading, 52).opacity(0.35)

                alertRow(
                    label: "At 100% spent",
                    sublabel: "Notify me when I reach the full budget",
                    icon: "xmark.octagon.fill",
                    color: .red,
                    isOn: $alertAt100
                )
            }
            .cardSurface()
        }
    }

    private func alertRow(
        label: String,
        sublabel: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn.wrappedValue ? color : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill((isOn.wrappedValue ? color : .secondary).opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text(sublabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Toggle("", isOn: isOn.animation(Theme.Motion.snappy))
                .labelsHidden()
                .tint(.appPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md + 2)
        .padding(.vertical, Theme.Spacing.md - 2)
    }

    // MARK: - Save button (twin)

    private var saveButton: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)

            Button(action: handleSaveTap) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text(isEditing ? "Save Changes" : "Create Budget")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isValid ? Color.appPrimary : Color.gray.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(
                    color: isValid ? Color.appPrimary.opacity(0.3) : Color.gray.opacity(0.18),
                    radius: 12, x: 0, y: 6
                )
            }
            .disabled(!isValid || isSaving)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func handleSaveTap() {
        guard isValid else { return }
        focusedField = nil
        isSaving = true
        HapticManager.shared.mediumTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticManager.shared.success()
        }
        save()

        // In-context notification ask (the onboarding permission page
        // is gone as of Wave 3): the user just saved a budget with
        // alert thresholds — the one moment "can we notify you?" has
        // an obvious answer. Only when iOS has never been asked;
        // denied/authorized users go straight out as before.
        if alertAt80 || alertAt100 {
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                await MainActor.run {
                    if settings.authorizationStatus == .notDetermined {
                        showingNotificationPrePermission = true
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            dismiss()
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                dismiss()
            }
        }
    }

    // MARK: - Notification pre-permission card

    /// Friendly explanation before the one-shot iOS permission
    /// prompt. Both paths end in `dismiss()` — the budget itself is
    /// already saved either way.
    private var notificationPrePermissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Want an alert at \(lowestAlertThresholdText) of budget?")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text("Your budget is saved. CashLens can also nudge you as spending approaches the limit — iOS will ask once, and you can change your mind anytime in Settings.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        HapticManager.shared.mediumTap()
                        showingNotificationPrePermission = false
                        Task {
                            _ = await NotificationScheduler.ensureAuthorized()
                            await MainActor.run { dismiss() }
                        }
                    } label: {
                        Text("Notify Me")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md + 2)
                            .background(Color.appPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button {
                        HapticManager.shared.lightTap()
                        showingNotificationPrePermission = false
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: 340)
            .cardSurface(radius: Theme.Radius.hero)
            .padding(.horizontal, Theme.Spacing.xxl)
        }
    }

    /// "80%" when the 80% alert is on, otherwise "100%" — the card
    /// only shows when at least one threshold is enabled.
    private var lowestAlertThresholdText: String {
        alertAt80 ? "80%" : "100%"
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard let parsed = expenseViewModel.parseAmount(amount), parsed > 0 else {
            return false
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Persistence

    private func save() {
        // Free tier writes obey the same rules the UI enforces:
        // creating is allowed only for the user's first budget, and
        // it must be an overall (non-category) monthly budget.
        // Editing an existing budget is exempt — grandfathered
        // values (extra budgets, category filters, weekly periods
        // from a lapsed Pro trial) are never clawed back.
        if !proManager.isPro && !isEditing {
            guard budgetViewModel.budgets.isEmpty,
                  categoryFilter == .overall,
                  period == .monthly else {
                dismiss()
                return
            }
        }
        guard let parsedAmount = expenseViewModel.parseAmount(amount) else { return }

        var alertPercentages: [Double] = []
        if alertAt80 { alertPercentages.append(0.8) }
        if alertAt100 { alertPercentages.append(1.0) }

        // Custom windows persist their dates; switching a budget back
        // to weekly/monthly clears them so stale dates can't resurface.
        let startDate: Date? = period == .custom ? Calendar.current.startOfDay(for: customStart) : nil
        let endDate: Date? = period == .custom ? Calendar.current.startOfDay(for: customEnd) : nil

        if var budget = editingBudget {
            budget.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            budget.amount = parsedAmount
            budget.period = period
            budget.categoryFilter = categoryFilter
            budget.alertAtPercentages = alertPercentages
            budget.customStartDate = startDate
            budget.customEndDate = endDate
            budgetViewModel.updateBudget(budget)
        } else {
            let budget = Budget(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: parsedAmount,
                period: period,
                categoryFilter: categoryFilter,
                alertAtPercentages: alertPercentages,
                customStartDate: startDate,
                customEndDate: endDate
            )
            budgetViewModel.addBudget(budget)
        }
    }

    private func loadEditingData() {
        guard let budget = editingBudget else { return }
        name = budget.name
        // Sanitise to numeric-only so the hero amount tile (which
        // injects its own currency symbol) doesn't end up showing
        // the symbol twice on an editing pass. Same fix that
        // AddExpense / AddSubscription apply to incoming amounts.
        amount = Self.sanitizeIncomingAmount(String(format: "%.2f", budget.amount))
        period = budget.period
        categoryFilter = budget.categoryFilter
        alertAt80 = budget.alertAtPercentages.contains(0.8)
        alertAt100 = budget.alertAtPercentages.contains(1.0)
        if budget.period == .custom {
            customStart = budget.customStartDate ?? customStart
            customEnd = budget.customEndDate ?? customEnd
        }
    }

    private static func sanitizeIncomingAmount(_ raw: String) -> String {
        let allowed = Set<Character>("0123456789.,-")
        let cleaned = String(raw.filter { allowed.contains($0) })
        return cleaned.isEmpty ? raw : cleaned
    }
}
