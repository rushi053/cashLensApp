import SwiftUI

/// Modal "Quick Search" presented from the Home header magnifying glass.
///
/// Redesigned to match the rest of the app's premium look:
///
/// - Custom header (X close button + centered "Search" title) instead of the
///   default `NavigationView` chrome.
/// - Hero search field uses the same `.fieldCard(isFocused:)` modifier as the
///   "Add" screens so focus glow + border are consistent.
/// - Empty-query state gives users *useful* affordances:
///     * persisted Recent Searches (last 5)
///     * one-tap quick tips ("this month", "$50", popular tag)
///     * Browse by Category strip
///     * Browse by Tag strip (when tags exist)
///     * Recent Activity preview rows
/// - Active-query state shows a result-count summary chip, date-grouped result
///   sections (Today / Yesterday / This week / Earlier), and rows that
///   **highlight the matched substring** in the title.
/// - Smarter ranking: title-prefix beats title-contains beats tag/category
///   beats notes beats amount. Amounts are parsed numerically (`$50` ≈ `50.00`)
///   instead of being matched as a brittle `String(format: "%.2f")`.
/// - Tag-only mode: queries beginning with `#` search tags exclusively.
///
/// All the existing functionality (auto-focus, edit-on-tap sheet, debounce,
/// off-main filtering) is preserved.
struct QuickSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    @State private var searchText = ""
    @State private var selectedExpense: Expense?
    @FocusState private var isSearchFocused: Bool

    @State private var searchResults: [Expense] = []
    @State private var searchTask: Task<Void, Never>?

    @State private var recentSearches: [String] = []

    @State private var animateSections = false

    /// Active *direct* filters driven by tapping a chip in the browse view.
    /// These are intentionally separate from `searchText` so chip taps can be
    /// instant (no 150ms debounce, no `Task.detached`, no view-tree thrash).
    @State private var activeCategoryFilter: Expense.Category? = nil
    @State private var activeCustomCategoryFilter: UUID? = nil
    @State private var activeTagFilter: String? = nil

    /// When `true` the next `searchText` change skips the typing debounce.
    /// Set right before mutating `searchText` from a chip tap (Quick Tip,
    /// Recent Search) so the user gets instant feedback instead of a 150ms
    /// pause followed by a sudden view swap.
    @State private var skipNextDebounce = false

    private static let recentsCap = 5

    /// Anything narrowing the result set right now — typed text or a chip
    /// filter. Drives the empty-vs-results view swap so chip-only filtering
    /// surfaces the results view even with no typed query.
    private var isQueryActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || activeCategoryFilter != nil
            || activeTagFilter != nil
    }

    private var hasActiveChipFilter: Bool {
        activeCategoryFilter != nil || activeTagFilter != nil
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                customHeader

                searchField
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.lg)
                    .modifier(SearchEntrance(order: 0, animate: animateSections))

                Group {
                    if isQueryActive {
                        if searchResults.isEmpty {
                            noResultsView
                                .transition(.opacity)
                        } else {
                            resultsView
                                .transition(.opacity)
                        }
                    } else {
                        emptyQueryView
                            .transition(.opacity)
                    }
                }
                .animation(Theme.Motion.snappy, value: isQueryActive)
                .animation(Theme.Motion.snappy, value: searchResults.isEmpty)
            }
        }
        .onAppear {
            loadRecentSearches()
            // PERF: Defer keyboard focus + cascade entrance until the
            // sheet has lifted. Previously the `withAnimation { ... }`
            // fired in the same runloop tick as the sheet present,
            // making the iOS spring fight a SwiftUI implicit animation;
            // the visible result was a slightly "sticky" feeling lift.
            // ~320 ms is just past the system sheet spring settle time
            // (~280–300 ms on iPhone) without being noticeable to the
            // user.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                isSearchFocused = true
                withAnimation { animateSections = true }
            }
        }
        .onChange(of: searchText) { _, newValue in
            performQuery(textChanged: true, instant: skipNextDebounce)
            skipNextDebounce = false
            _ = newValue // hush unused-var warning
        }
        .onChange(of: activeCategoryFilter) { _, _ in
            performQuery(textChanged: false, instant: true)
        }
        .onChange(of: activeCustomCategoryFilter) { _, _ in
            performQuery(textChanged: false, instant: true)
        }
        .onChange(of: activeTagFilter) { _, _ in
            performQuery(textChanged: false, instant: true)
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
                    performQuery(textChanged: false, instant: true)
                }
            )
            .environmentObject(categoryViewModel)
        }
    }

    // MARK: - Custom Header

    private var customHeader: some View {
        HStack(alignment: .center) {
            Button {
                HapticManager.shared.lightTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close search")

            Spacer()

            VStack(spacing: 2) {
                Text("Search")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("Find any expense, fast")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Invisible spacer that's the same size as the X button so the
            // title stays perfectly centered.
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(isSearchFocused ? .appPrimary : .secondary)
                .animation(Theme.Motion.snappy, value: isSearchFocused)

            TextField("Search title, tag, category…", text: $searchText)
                .font(.system(size: 16, weight: .regular))
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    saveRecentSearchIfNeeded(searchText)
                }

            if !searchText.isEmpty {
                Button {
                    HapticManager.shared.lightTap()
                    withAnimation(Theme.Motion.snappy) {
                        searchText = ""
                    }
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md + 2)
        .fieldCard(isFocused: isSearchFocused)
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = true }
    }

    // MARK: - Empty Query (browse) view

    @ViewBuilder
    private var emptyQueryView: some View {
        if viewModel.expenses.isEmpty {
            // Brand-new install. Nothing to search.
            nothingToSearchView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if !recentSearches.isEmpty {
                        recentSearchesSection
                            .modifier(SearchEntrance(order: 1, animate: animateSections))
                    }

                    quickTipsSection
                        .modifier(SearchEntrance(order: 2, animate: animateSections))

                    categoriesSection
                        .modifier(SearchEntrance(order: 3, animate: animateSections))

                    if !topTagsForBrowse.isEmpty {
                        tagsBrowseSection
                            .modifier(SearchEntrance(order: 4, animate: animateSections))
                    }

                    recentExpensesSection
                        .modifier(SearchEntrance(order: 5, animate: animateSections))

                    Spacer(minLength: Theme.Spacing.xxxl)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.tabBarInset)
            }
        }
    }

    // MARK: - Recent searches

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            HStack {
                sectionLabel("Recent Searches")
                Spacer()
                Button {
                    HapticManager.shared.lightTap()
                    clearRecentSearches()
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.appPrimary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(recentSearches, id: \.self) { term in
                        recentSearchChip(term)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
    }

    private func recentSearchChip(_ term: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Button {
                HapticManager.shared.selectionChanged()
                applyTextQueryInstantly(term)
            } label: {
                Text(term)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.lightTap()
                removeRecentSearch(term)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove recent search \(term)")
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Capsule().fill(Color.secondarySystemBackground)
        )
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Quick tips

    /// One-tap suggestions that show users *what* they can search for.
    /// Built dynamically from real data so it never feels like dead copy.
    private var quickTipChips: [(label: String, query: String, icon: String)] {
        var chips: [(String, String, String)] = []

        // Time-window tip — always available.
        chips.append(("This month", "this month", "calendar"))

        // Round-amount example based on the user's median spend so it feels real.
        if let amountSample = roundAmountSample {
            chips.append((amountSample.label, amountSample.query, "dollarsign.circle"))
        }

        // Most-popular tag — only if user has tags.
        if let topTag = viewModel.tagStats.popularTags.first {
            chips.append((Tag.displayForm(topTag), "#\(topTag)", "tag"))
        }

        // Top category fallback when there are no tags yet.
        if viewModel.tagStats.popularTags.isEmpty,
           let topCategory = viewModel
            .cachedTotalsByCategory
            .filter({ $0.key != .custom && $0.value > 0 })
            .max(by: { $0.value < $1.value })?.key {
            chips.append((topCategory.displayName, topCategory.rawValue, topCategory.icon))
        }

        return chips.map { (label: $0.0, query: $0.1, icon: $0.2) }
    }

    /// Returns a "$50" / "$100" / "$500" style example anchored to the user's
    /// own data, so the tip feels grounded.
    private var roundAmountSample: (label: String, query: String)? {
        let amounts = viewModel.expenses.map { $0.amount }.filter { $0 > 0 }.sorted()
        guard !amounts.isEmpty else { return nil }
        let median = amounts[amounts.count / 2]
        // Snap to a friendly round number so the tip looks intentional.
        let rounded: Double
        switch median {
        case ..<25:    rounded = 10
        case ..<75:    rounded = 50
        case ..<175:   rounded = 100
        case ..<375:   rounded = 250
        case ..<750:   rounded = 500
        default:       rounded = 1000
        }
        let symbol = viewModel.selectedCurrency.symbol
        let intValue = Int(rounded)
        return (label: "\(symbol)\(intValue)", query: "\(symbol)\(intValue)")
    }

    private var quickTipsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            sectionLabel("Try")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(quickTipChips.enumerated()), id: \.offset) { _, tip in
                        Button {
                            HapticManager.shared.selectionChanged()
                            applyTextQueryInstantly(tip.query)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tip.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(tip.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(LinearGradient.appPrimaryDiagonal)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                Capsule().fill(Color.appPrimary.opacity(0.10))
                            )
                            .overlay(
                                Capsule().stroke(Color.appPrimary.opacity(0.20), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
    }

    // MARK: - Categories browse

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            sectionLabel("Browse by Category")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm + 2) {
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        categoryBrowseChip(
                            label: category.rawValue,
                            icon: category.icon,
                            colorName: category.color,
                            isSelected: activeCategoryFilter == category && activeCustomCategoryFilter == nil
                        ) {
                            toggleCategoryFilter(category, customId: nil)
                        }
                    }
                    ForEach(categoryViewModel.customCategories) { custom in
                        categoryBrowseChip(
                            label: custom.name,
                            icon: custom.icon,
                            colorName: custom.colorName,
                            isSelected: activeCategoryFilter == .custom && activeCustomCategoryFilter == custom.id
                        ) {
                            toggleCategoryFilter(.custom, customId: custom.id)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
    }

    /// Browse chip used for both default and custom categories. Renders a
    /// muted neutral capsule when idle and switches to a tinted, gradient-bg
    /// capsule when the user has selected this chip as the active filter —
    /// gives clear "I tapped this and it's now filtering" feedback without
    /// any keyboard or view-tree thrash.
    private func categoryBrowseChip(
        label: String,
        icon: String,
        colorName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint = Color.forCategory(colorName)
        return Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.22) : tint.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tint)
                }

                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.95))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, Theme.Spacing.xs + 2)
            .padding(.trailing, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(Color.appPrimary)
                    } else {
                        Capsule().fill(Color.secondarySystemBackground)
                    }
                }
            )
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.clear : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
            )
            .if(isSelected) { $0.primaryGlow(strength: 0.18) }
        }
        .buttonStyle(.plain)
    }

    /// Toggle the active category filter. Same chip again clears it.
    /// All state mutations happen in one `withAnimation` block so the chip's
    /// fill, the keyboard, and the empty-vs-results swap stay in lockstep
    /// instead of stacking three separate animations.
    private func toggleCategoryFilter(_ category: Expense.Category, customId: UUID?) {
        HapticManager.shared.selectionChanged()
        let isAlreadyActive = (activeCategoryFilter == category && activeCustomCategoryFilter == customId)
        withAnimation(Theme.Motion.snappy) {
            if isAlreadyActive {
                activeCategoryFilter = nil
                activeCustomCategoryFilter = nil
            } else {
                activeCategoryFilter = category
                activeCustomCategoryFilter = customId
            }
        }
    }

    // MARK: - Tags browse

    private var topTagsForBrowse: [String] {
        Array(viewModel.tagStats.popularTags.prefix(8))
    }

    private var tagsBrowseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            sectionLabel("Browse by Tag")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(topTagsForBrowse, id: \.self) { tag in
                        TagChip(
                            tag,
                            style: activeTagFilter == tag ? .selected : .standard,
                            count: viewModel.tagStats.usageCounts[tag],
                            onTap: {
                                toggleTagFilter(tag)
                            }
                        )
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
        }
    }

    /// Toggle the active tag filter. Tapping the same tag again clears it.
    private func toggleTagFilter(_ tag: String) {
        let isAlreadyActive = (activeTagFilter == tag)
        withAnimation(Theme.Motion.snappy) {
            activeTagFilter = isAlreadyActive ? nil : tag
        }
    }

    /// Set the search field text from an *explicit* tap (Quick Tip, Recent
    /// Search). Bypasses the typing debounce so the result swap feels
    /// instantaneous, and intentionally doesn't change keyboard focus
    /// (preventing the keyboard-dismiss animation that previously stacked
    /// onto the result-view transition and produced a perceptible stutter).
    private func applyTextQueryInstantly(_ text: String) {
        skipNextDebounce = true
        withAnimation(Theme.Motion.snappy) {
            searchText = text
        }
    }

    // MARK: - Recent activity

    private var recentExpensesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Recent Activity")

            VStack(spacing: Theme.Spacing.sm + 2) {
                ForEach(viewModel.expenses.prefix(5)) { expense in
                    Button {
                        HapticManager.shared.lightTap()
                        selectedExpense = expense
                    } label: {
                        compactExpenseRow(expense: expense, query: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Results view

    @ViewBuilder
    private var resultsView: some View {
        ScrollView {
            // LazyVStack so only the rows actually visible in the viewport
            // are laid out / materialized. The old plain `VStack` here
            // eagerly built **every** result row even when the user had
            // hundreds of matches scrolling off-screen — the audit caught
            // this as a P0 reason search felt sluggish.
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if hasActiveChipFilter {
                    activeFiltersStrip
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                resultSummaryRow
                    .padding(.horizontal, Theme.Spacing.lg)

                let groups = groupedResults()
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
                        Text(group.title)
                            .font(Theme.Typography.subsectionTitle)
                            .foregroundColor(.primary)

                        VStack(spacing: Theme.Spacing.sm + 2) {
                            ForEach(group.expenses) { expense in
                                Button {
                                    HapticManager.shared.lightTap()
                                    saveRecentSearchIfNeeded(searchText)
                                    selectedExpense = expense
                                } label: {
                                    compactExpenseRow(expense: expense, query: searchText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer(minLength: Theme.Spacing.tabBarInset)
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    /// Compact strip of removable pills shown above the result list whenever
    /// a chip filter is active. Mirrors how Photos / Mail surface "you're
    /// currently filtering by X" so users always know — and can clear —
    /// what's narrowing their view.
    private var activeFiltersStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let cat = activeCategoryFilter {
                        activeFilterPill(
                            label: activeCategoryDisplayLabel(cat),
                            icon: activeCategoryDisplayIcon(cat)
                        ) {
                            HapticManager.shared.lightTap()
                            withAnimation(Theme.Motion.snappy) {
                                activeCategoryFilter = nil
                                activeCustomCategoryFilter = nil
                            }
                        }
                    }

                    if let tag = activeTagFilter {
                        activeFilterPill(
                            label: Tag.displayForm(tag),
                            icon: "tag.fill"
                        ) {
                            HapticManager.shared.lightTap()
                            withAnimation(Theme.Motion.snappy) {
                                activeTagFilter = nil
                            }
                        }
                    }
                }
            }

            if hasActiveChipFilter {
                Button {
                    HapticManager.shared.lightTap()
                    withAnimation(Theme.Motion.snappy) {
                        activeCategoryFilter = nil
                        activeCustomCategoryFilter = nil
                        activeTagFilter = nil
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear all filters")
            }
        }
    }

    private func activeFilterPill(
        label: String,
        icon: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(3)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.xs + 2)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(Capsule().fill(Color.appPrimary))
    }

    /// Resolve display label for the active category pill. Custom categories
    /// look up their user-given name; defaults use the rawValue.
    private func activeCategoryDisplayLabel(_ category: Expense.Category) -> String {
        if category == .custom, let id = activeCustomCategoryFilter,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return custom.name
        }
        return category.rawValue
    }

    private func activeCategoryDisplayIcon(_ category: Expense.Category) -> String {
        if category == .custom, let id = activeCustomCategoryFilter,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return custom.icon
        }
        return category.icon
    }

    private var resultSummaryRow: some View {
        let count = searchResults.count
        // Refund-aware so the search summary matches the net amount the
        // user would expect after a returned purchase.
        let total = searchResults.reduce(0.0) { $0 + (($1.amount.isFinite ? $1.signedAmount : 0)) }
        return HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(count == 1 ? "expense" : "expenses")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(LinearGradient.appPrimaryDiagonal)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(
                Capsule().fill(Color.appPrimary.opacity(0.10))
            )

            Text("·")
                .foregroundColor(.secondary)

            Text("\(viewModel.formattedAmount(total)) total")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
    }

    /// Group search results by relative date bucket.
    private func groupedResults() -> [(title: String, expenses: [Expense])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(from: calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: now
        )) ?? startOfToday

        var today: [Expense] = []
        var yesterday: [Expense] = []
        var thisWeek: [Expense] = []
        var earlier: [Expense] = []

        for expense in searchResults {
            if expense.date >= startOfToday {
                today.append(expense)
            } else if expense.date >= startOfYesterday {
                yesterday.append(expense)
            } else if expense.date >= startOfWeek {
                thisWeek.append(expense)
            } else {
                earlier.append(expense)
            }
        }

        var groups: [(title: String, expenses: [Expense])] = []
        if !today.isEmpty     { groups.append((title: "Today",     expenses: today)) }
        if !yesterday.isEmpty { groups.append((title: "Yesterday", expenses: yesterday)) }
        if !thisWeek.isEmpty  { groups.append((title: "This Week", expenses: thisWeek)) }
        if !earlier.isEmpty   { groups.append((title: "Earlier",   expenses: earlier)) }
        return groups
    }

    // MARK: - No-results / no-data states

    private var noResultsView: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: Theme.Spacing.xxl)

            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimarySoft)
                    .frame(width: 80, height: 80)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LinearGradient.appPrimaryDiagonal)
            }

            VStack(spacing: Theme.Spacing.xs + 2) {
                if !trimmed.isEmpty {
                    Text("No matches for \"\(trimmed)\"")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("Nothing matches your filters")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Text("Try a different word, a category name, an amount like \"\(viewModel.selectedCurrency.symbol)50\", or a tag like \"#travel\".")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            if hasActiveChipFilter {
                Button {
                    HapticManager.shared.lightTap()
                    withAnimation(Theme.Motion.snappy) {
                        activeCategoryFilter = nil
                        activeCustomCategoryFilter = nil
                        activeTagFilter = nil
                    }
                } label: {
                    Text("Clear filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm + 2)
                        .background(Capsule().fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var nothingToSearchView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: Theme.Spacing.xxl)

            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimarySoft)
                    .frame(width: 80, height: 80)
                Image(systemName: "tray")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(LinearGradient.appPrimaryDiagonal)
            }

            VStack(spacing: Theme.Spacing.xs + 2) {
                Text("Nothing to search yet")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Add a few expenses and they'll show up here instantly.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result row

    /// One row used for both Recent Activity and Result lists. When `query`
    /// is non-nil the matched substring in the title is rendered in
    /// `appPrimary` so the user sees *why* a result matched.
    private func compactExpenseRow(expense: Expense, query: String?) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(categoryColor(for: expense).opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon(for: expense))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor(for: expense))
            }

            VStack(alignment: .leading, spacing: 3) {
                highlightedTitle(expense.title, query: query)

                HStack(spacing: 6) {
                    Text(categoryName(for: expense))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(expense.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let tags = expense.tags, !tags.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TagChip(tags[0], style: .inline)
                    }
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(viewModel.formattedAmount(expense.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, Theme.Spacing.sm + 2)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    /// Renders the expense title with the matched substring tinted in
    /// `appPrimary` semibold so the match is glanceable. Falls back to a
    /// plain title when there's no usable query (or the substring isn't in
    /// the title — e.g. matched on tag/notes/amount).
    @ViewBuilder
    private func highlightedTitle(_ title: String, query: String?) -> some View {
        if let q = query?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !q.isEmpty,
           let range = title.range(of: q, options: .caseInsensitive) {
            let lower = title.distance(from: title.startIndex, to: range.lowerBound)
            let upper = title.distance(from: title.startIndex, to: range.upperBound)

            let prefix = String(title.prefix(lower))
            let middle = String(title.prefix(upper).dropFirst(lower))
            let suffix = String(title.dropFirst(upper))

            (
                Text(prefix)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                + Text(middle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.appPrimary)
                + Text(suffix)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            )
            .lineLimit(1)
        } else {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Section label helper

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .textCase(.uppercase)
    }

    // MARK: - Search Logic

    /// Single entry point for recomputing `searchResults`. Composes:
    ///
    /// 1. **Direct chip filters** (`activeCategoryFilter`, `activeTagFilter`)
    ///    — applied first, synchronously, so they feel instant.
    /// 2. **Typed text query** — applied second, scored & ranked across the
    ///    chip-filtered subset (or the whole expense list when no chip is
    ///    active).
    ///
    /// `instant: true` skips the 150ms typing debounce. Use it for explicit
    /// user gestures (chip tap, recent-search tap, post-edit refresh) so they
    /// never feel laggy. Plain typing still debounces.
    private func performQuery(textChanged: Bool, instant: Bool) {
        searchTask?.cancel()

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty

        // Nothing's narrowing the list → clear results, swap back to browse.
        guard hasText || hasActiveChipFilter else {
            searchResults = []
            return
        }

        // Pure chip filter, no text. Direct, synchronous, O(n). No debounce,
        // no Task.detached — eliminates the 150ms "stutter" the user noticed.
        if !hasText && hasActiveChipFilter {
            let filtered = applyChipFilters(to: viewModel.expenses)
                .sorted { $0.date > $1.date }
            searchResults = filtered
            return
        }

        // Text query (with or without chip filters). Debounced when typing,
        // immediate for chip-driven taps. Always ranks off-main.
        let expensesSnapshot = viewModel.expenses
        let customCategoriesSnapshot = categoryViewModel.customCategories
        let categoryFilter = activeCategoryFilter
        let customCategoryFilter = activeCustomCategoryFilter
        let tagFilter = activeTagFilter
        let needsDebounce = textChanged && !instant

        searchTask = Task { @MainActor in
            if needsDebounce {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }

            let results = await Task.detached(priority: .userInitiated) {
                let pre = Self.applyChipFilters(
                    to: expensesSnapshot,
                    category: categoryFilter,
                    customCategoryId: customCategoryFilter,
                    tag: tagFilter
                )
                return Self.rankedSearch(
                    query: trimmed,
                    expenses: pre,
                    customCategories: customCategoriesSnapshot
                )
            }.value

            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }

    /// Synchronous, main-actor convenience: applies the *current* chip
    /// filters to a list of expenses. Used for the no-text path so users
    /// see chip-driven results without the async hop.
    private func applyChipFilters(to expenses: [Expense]) -> [Expense] {
        Self.applyChipFilters(
            to: expenses,
            category: activeCategoryFilter,
            customCategoryId: activeCustomCategoryFilter,
            tag: activeTagFilter
        )
    }

    /// Pure version of `applyChipFilters` so it can run inside a
    /// `Task.detached` without crossing actor boundaries.
    nonisolated private static func applyChipFilters(
        to expenses: [Expense],
        category: Expense.Category?,
        customCategoryId: UUID?,
        tag: String?
    ) -> [Expense] {
        var base = expenses
        if let cat = category {
            if cat == .custom, let id = customCategoryId {
                base = base.filter { $0.category == .custom && $0.customCategoryId == id }
            } else {
                base = base.filter { $0.category == cat }
            }
        }
        if let tag {
            base = base.filter { ($0.tags ?? []).contains(tag) }
        }
        return base
    }

    /// Score-based search. Higher scores mean better matches; ties break by
    /// most-recent date so the most relevant *and* recent expenses win.
    nonisolated private static func rankedSearch(
        query rawQuery: String,
        expenses: [Expense],
        customCategories: [CustomCategory]
    ) -> [Expense] {
        let lowered = rawQuery.lowercased()
        let customNameById: [UUID: String] = Dictionary(
            uniqueKeysWithValues: customCategories.map { ($0.id, $0.name.lowercased()) }
        )

        // Tag-only mode: queries that begin with `#` only search tags.
        let isTagOnly = lowered.hasPrefix("#")
        let tagQuery: String? = {
            guard isTagOnly else { return nil }
            return Tag.normalize(String(lowered.dropFirst()))
        }()

        // Date-keyword mode: filter results to a date range.
        let dateRange = parseDateRange(from: lowered)

        // Amount mode: strip currency-y characters and try to parse a Double.
        let amountQuery: Double? = parseAmount(from: lowered)

        struct Scored {
            let expense: Expense
            let score: Int
        }

        var scored: [Scored] = []
        scored.reserveCapacity(expenses.count)

        for expense in expenses {
            // Apply hard filters first.
            if let dateRange, !(expense.date >= dateRange.start && expense.date < dateRange.end) {
                continue
            }
            if let tagQuery {
                guard let tags = expense.tags else { continue }
                if !tags.contains(where: { $0.lowercased().contains(tagQuery) }) { continue }
            }

            var score = 0
            let titleLower = expense.title.lowercased()

            // 1. Title prefix is the strongest signal.
            if titleLower.hasPrefix(lowered) { score += 100 }
            else if titleLower.contains(lowered) { score += 60 }

            // 2. Tag match (any tag).
            if let tags = expense.tags {
                for tag in tags where tag.lowercased().contains(lowered) {
                    score += 50
                    break
                }
            }

            // 3. Category name (default + custom).
            if expense.category.rawValue.lowercased().contains(lowered) {
                score += 40
            } else if expense.category == .custom,
                      let id = expense.customCategoryId,
                      let customName = customNameById[id],
                      customName.contains(lowered) {
                score += 40
            }

            // 4. Notes.
            if let notes = expense.notes?.lowercased(), notes.contains(lowered) {
                score += 25
            }

            // 5. Amount (numeric, exact-to-cents match).
            if let amountQuery {
                let cents = Int((expense.amount * 100).rounded())
                let queryCents = Int((amountQuery * 100).rounded())
                if cents == queryCents { score += 70 }
            }

            // 6. Date-only filter mode (no scored matches required) — include.
            if score == 0 && dateRange != nil && !isTagOnly && amountQuery == nil {
                score = 10
            }

            // 7. Tag-only mode — already filtered above; assign a baseline score.
            if isTagOnly && score == 0 {
                score = 30
            }

            if score > 0 {
                scored.append(Scored(expense: expense, score: score))
            }
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.expense.date > rhs.expense.date
            }
            .map { $0.expense }
    }

    // MARK: - Query parsing helpers

    /// Parses simple money text like `$50`, `$ 50.00`, `50`, `1,234.56` into a
    /// Double. Returns nil if the cleaned-up string isn't a valid number.
    nonisolated private static func parseAmount(from query: String) -> Double? {
        // Strip everything except digits, decimal separator, and minus.
        let allowed = Set("0123456789.,-")
        let cleaned = query.filter { allowed.contains($0) }
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    /// Recognizes a few natural date keywords. Anything we can't recognize
    /// returns `nil` so the rest of the ranker still runs as a text search.
    nonisolated private static func parseDateRange(from query: String) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()

        if query.contains("today") {
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return (start, end)
        }
        if query.contains("yesterday") {
            let startOfToday = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return (start, startOfToday)
        }
        if query.contains("this week") {
            let start = calendar.date(from: calendar.dateComponents(
                [.yearForWeekOfYear, .weekOfYear], from: now
            )) ?? now
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return (start, end)
        }
        if query.contains("this month") {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
        }
        if query.contains("this year") {
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
            return (start, end)
        }
        return nil
    }

    // MARK: - Recent searches persistence

    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.quickSearchRecents),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            recentSearches = []
            return
        }
        recentSearches = decoded
    }

    private func saveRecentSearchIfNeeded(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        // Move to front, dedupe (case-insensitive), cap.
        var next = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        next.insert(trimmed, at: 0)
        if next.count > Self.recentsCap {
            next = Array(next.prefix(Self.recentsCap))
        }
        recentSearches = next
        persistRecentSearches()
    }

    private func removeRecentSearch(_ term: String) {
        withAnimation(Theme.Motion.snappy) {
            recentSearches.removeAll { $0 == term }
        }
        persistRecentSearches()
    }

    private func clearRecentSearches() {
        withAnimation(Theme.Motion.snappy) {
            recentSearches = []
        }
        persistRecentSearches()
    }

    private func persistRecentSearches() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.quickSearchRecents)
        }
    }

    // MARK: - Category resolution helpers

    private func categoryColor(for expense: Expense) -> Color {
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            return Color.forCategory(custom.colorName)
        }
        return Color.forCategory(expense.category.color)
    }

    private func categoryIcon(for expense: Expense) -> String {
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            return custom.icon
        }
        return expense.category.icon
    }

    private func categoryName(for expense: Expense) -> String {
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            return custom.name
        }
        return expense.category.rawValue
    }
}

// MARK: - Entrance animation

/// Cascading spring-based entrance, mirroring Statistics / Subscriptions / Home
/// so the whole app shares one "section appears" motion.
private struct SearchEntrance: ViewModifier {
    let order: Int
    let animate: Bool

    private var delay: Double { Double(order) * 0.05 }

    func body(content: Content) -> some View {
        content
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 10)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0)
                    .delay(delay),
                value: animate
            )
    }
}

// MARK: - Preview

struct QuickSearchView_Previews: PreviewProvider {
    static var previews: some View {
        QuickSearchView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
    }
}
