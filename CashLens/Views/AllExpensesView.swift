import SwiftUI

struct AllExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager
    let initialFilter: AllExpensesInitialFilter?
    /// v2: when AllExpensesView is the Activity tab root (not pushed
    /// from a Home sheet), there's no presenter to dismiss back to —
    /// so the leading "Back" button must disappear. The legacy
    /// sheet-presented call sites pass `false` (default) and keep
    /// their existing behavior.
    let isRootTab: Bool
    @State private var sortOption: SortOption = .dateDesc
    @State private var animateContent = false
    @State private var scrollToTop = false  // Track when to scroll to top
    @State private var selectedExpense: Expense?
    @State private var didApplyInitialFilter = false

    /// Modal Quick Search. AllExpensesView is the "Library" — it browses,
    /// filters, sorts, and manages. Search lives in `QuickSearchView`, opened
    /// from the toolbar magnifying glass, so the app has exactly one search
    /// surface (smarter parsing, recents, match highlighting, date grouping).
    @State private var showingQuickSearch = false

    /// Modal Calendar — month-grid browse surface that complements the
    /// chronological list. Sheet-presented so list state (filters, scroll
    /// position, selection) is preserved on dismiss.
    @State private var showingCalendar = false

    // Performance: cache computed results + paginate rendering for large datasets
    @State private var computedExpenses: [Expense] = []
    @State private var computedDateGroups: [(Date, [Expense])] = []
    @State private var totalMatchCount: Int = 0
    @State private var displayLimit: Int = 250
    @State private var isRecomputing: Bool = false

    /// Ids the user just deleted. Recompute always filters these out, even if
    /// `viewModel.expenses` momentarily still contains them (Core Data fetches
    /// can briefly return stale rows after a save). The set is pruned the
    /// moment a published `viewModel.expenses` value no longer contains them,
    /// so it never grows or causes ghost-hiding.
    @State private var pendingDeletionIds: Set<UUID> = []

    /// Token for the in-flight recompute. Lets us cancel a stale task so its
    /// late `MainActor.run` can't overwrite a fresher snapshot.
    @State private var recomputeTask: Task<Void, Never>? = nil
    
    // Date range filter
    @State private var useDateRangeFilter = false
    @State private var rangeStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var rangeEndDate = Date()
    @State private var showingDateRangePicker = false
    
    // Quick filters
    @State private var filterCategory: Expense.Category? = nil
    @State private var filterCustomCategoryId: UUID? = nil
    @State private var showOnlySubscriptions = false

    /// Tag filter — Pro-only. Nil means "no tag filter active".
    @State private var filterTag: String? = nil
    @State private var showingTagPaywall = false

    // MARK: - Bulk select state
    //
    // `isSelecting` toggles selection mode; rows then render a leading
    // checkmark and tapping a row toggles it in `selectedIds` instead of
    // opening the editor. The bottom bar appears whenever `isSelecting` is
    // true, regardless of whether anything is selected yet, so the user
    // always sees how to exit.
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showingBulkDeleteConfirm: Bool = false
    @State private var showingBulkCategoryPicker: Bool = false
    @State private var showingBulkTagSheet: Bool = false
    @State private var bulkTagText: String = ""
    @State private var showingBulkTagPaywall: Bool = false
    
    enum SortOption: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case amountDesc = "Highest Amount"
        case amountAsc = "Lowest Amount"
        case category = "Category"

        var icon: String {
            switch self {
            case .dateDesc: return "calendar.badge.clock"
            case .dateAsc: return "calendar"
            case .amountDesc: return "arrow.down.circle"
            case .amountAsc: return "arrow.up.circle"
            case .category: return "folder"
            }
        }

        /// Compact label used inside the sort pill. Full `rawValue` is still
        /// shown in the menu for clarity.
        var shortLabel: String {
            switch self {
            case .dateDesc: return "Newest"
            case .dateAsc: return "Oldest"
            case .amountDesc: return "Highest"
            case .amountAsc: return "Lowest"
            case .category: return "Category"
            }
        }
    }
    
    private var visibleExpenses: [Expense] {
        Array(computedExpenses.prefix(max(0, min(displayLimit, computedExpenses.count))))
    }
    
    // Sort expenses based on selected sort option
    private func sortExpenses(_ expenses: [Expense]) -> [Expense] {
        switch sortOption {
        case .dateDesc:
            return expenses.sorted { $0.date > $1.date }
        case .dateAsc:
            return expenses.sorted { $0.date < $1.date }
        case .amountDesc:
            return expenses.sorted { $0.amount > $1.amount }
        case .amountAsc:
            return expenses.sorted { $0.amount < $1.amount }
        case .category:
            return expenses.sorted { viewModel.categoryDisplayName(for: $0) < viewModel.categoryDisplayName(for: $1) }
        }
    }
    
    private var shouldGroupByDate: Bool {
        sortOption == .dateAsc || sortOption == .dateDesc
    }
    
    private var visibleDateGroups: [(Date, [Expense])] {
        var out: [(Date, [Expense])] = []
        out.reserveCapacity(min(computedDateGroups.count, 60))
        var running = 0
        for g in computedDateGroups {
            if running >= displayLimit { break }
            out.append(g)
            running += g.1.count
        }
        return out
    }
    
    private func recomputeResults(resetPagination: Bool, using snapshot: [Expense]? = nil) {
        isRecomputing = true

        // Cancel any in-flight recompute so a late `MainActor.run` from a
        // stale snapshot can't overwrite a fresher one (e.g. the recompute
        // we triggered after deleting can finish *before* a queued one that
        // captured pre-delete data).
        recomputeTask?.cancel()

        let expensesSnapshot = snapshot ?? viewModel.expenses
        let customCategoriesSnapshot = categoryViewModel.customCategories
        let sort = sortOption
        let useRange = useDateRangeFilter
        let start = rangeStartDate
        let end = rangeEndDate
        let filterCat = filterCategory
        let filterCustomId = filterCustomCategoryId
        let subsOnly = showOnlySubscriptions
        let filterTagValue = filterTag
        let suppressed = pendingDeletionIds

        recomputeTask = Task.detached(priority: .userInitiated) {
            let customNameById: [UUID: String] = Dictionary(uniqueKeysWithValues: customCategoriesSnapshot.map { ($0.id, $0.name) })

            // Defense in depth — even if Core Data briefly hands us a stale
            // snapshot containing a just-deleted row, we filter it here so it
            // can never reappear in the list.
            var base: [Expense] = suppressed.isEmpty
                ? expensesSnapshot
                : expensesSnapshot.filter { !suppressed.contains($0.id) }
            // If the suppression set is fully resolved by this snapshot
            // (none of its ids appear), we can drop it now so it doesn't
            // hide future re-adds with the same id.
            let suppressionResolved = !suppressed.isEmpty &&
                !expensesSnapshot.contains(where: { suppressed.contains($0.id) })

            if useRange {
                base = ExpenseFilter.apply(
                    expenses: base,
                    category: nil,
                    customCategoryId: nil,
                    timeFrame: .all,
                    dateRangeStart: start,
                    dateRangeEnd: end
                )
            }
            
            if subsOnly {
                base = base.filter { $0.isFromSubscription }
            }
            
            if let cat = filterCat {
                if cat == .custom {
                    if let id = filterCustomId {
                        base = base.filter { $0.category == .custom && $0.customCategoryId == id }
                    } else {
                        base = base.filter { $0.category == .custom }
                    }
                } else {
                    base = base.filter { $0.category == cat }
                }
            }

            if let tag = filterTagValue {
                base = base.filter { ($0.tags ?? []).contains(tag) }
            }

            let sorted: [Expense]
            switch sort {
            case .dateDesc:
                sorted = base.sorted { $0.date > $1.date }
            case .dateAsc:
                sorted = base.sorted { $0.date < $1.date }
            case .amountDesc:
                sorted = base.sorted { $0.amount > $1.amount }
            case .amountAsc:
                sorted = base.sorted { $0.amount < $1.amount }
            case .category:
                sorted = base.sorted {
                    let a = ($0.category == .custom && $0.customCategoryId != nil) ? (customNameById[$0.customCategoryId!] ?? "Custom") : $0.category.rawValue
                    let b = ($1.category == .custom && $1.customCategoryId != nil) ? (customNameById[$1.customCategoryId!] ?? "Custom") : $1.category.rawValue
                    if a == b { return $0.date > $1.date }
                    return a < b
                }
            }
            
            let calendar = Calendar.current
            var groups: [(Date, [Expense])] = []
            if sort == .dateAsc || sort == .dateDesc {
                var currentDay: Date? = nil
                for e in sorted {
                    let day = calendar.startOfDay(for: e.date)
                    if currentDay != day {
                        groups.append((day, [e]))
                        currentDay = day
                    } else {
                        groups[groups.count - 1].1.append(e)
                    }
                }
            }
            
            let finalGroups = groups
            await MainActor.run {
                guard !Task.isCancelled else { return }
                totalMatchCount = sorted.count
                computedExpenses = sorted
                computedDateGroups = finalGroups
                if resetPagination {
                    displayLimit = 250
                } else {
                    displayLimit = min(max(250, displayLimit), max(250, sorted.count))
                }
                if suppressionResolved {
                    pendingDeletionIds = []
                }
                isRecomputing = false
            }
        }
    }
    
    private func loadMoreIfNeeded() {
        guard displayLimit < totalMatchCount else { return }
        displayLimit = min(totalMatchCount, displayLimit + 250)
    }
    
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private var quickFiltersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                PillChip(
                    title: "All",
                    icon: "line.3.horizontal.decrease.circle",
                    isSelected: filterCategory == nil && !showOnlySubscriptions,
                    shape: .rounded
                ) {
                    HapticManager.shared.selectionChanged()
                    withAnimation(Theme.Motion.snappy) {
                        filterCategory = nil
                        filterCustomCategoryId = nil
                        showOnlySubscriptions = false
                        scrollToTop = true
                    }
                }

                PillChip(
                    title: "Subscriptions",
                    icon: "arrow.triangle.2.circlepath",
                    isSelected: showOnlySubscriptions,
                    shape: .rounded
                ) {
                    HapticManager.shared.selectionChanged()
                    withAnimation(Theme.Motion.snappy) {
                        showOnlySubscriptions.toggle()
                        scrollToTop = true
                    }
                }

                ForEach(viewModel.getAvailableDefaultCategories().filter { $0 != .custom }, id: \.self) { category in
                    PillChip(
                        title: category.rawValue,
                        icon: category.icon,
                        isSelected: filterCategory == category,
                        shape: .rounded
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(Theme.Motion.snappy) {
                            if filterCategory == category {
                                filterCategory = nil
                            } else {
                                filterCategory = category
                            }
                            filterCustomCategoryId = nil
                            scrollToTop = true
                        }
                    }
                }

                ForEach(categoryViewModel.customCategories) { custom in
                    PillChip(
                        title: custom.name,
                        icon: custom.icon,
                        isSelected: filterCategory == .custom && filterCustomCategoryId == custom.id,
                        shape: .rounded
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(Theme.Motion.snappy) {
                            if filterCategory == .custom && filterCustomCategoryId == custom.id {
                                filterCategory = nil
                                filterCustomCategoryId = nil
                            } else {
                                filterCategory = .custom
                                filterCustomCategoryId = custom.id
                            }
                            scrollToTop = true
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xs + 2)
        }
    }

    /// Pro-only tag filter strip. Appears only when there is at least one tag in use.
    /// Free users see a subtle upgrade nudge in its place.
    @ViewBuilder
    private var tagsFilterRow: some View {
        let stats = viewModel.tagStats
        let orderedTags = stats.popularTags

        if orderedTags.isEmpty {
            EmptyView()
        } else if proManager.isPro {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    TagChip(
                        "all",
                        style: filterTag == nil ? .selected : .standard,
                        onTap: {
                            withAnimation(Theme.Motion.snappy) {
                                filterTag = nil
                                scrollToTop = true
                            }
                        }
                    )

                    ForEach(orderedTags, id: \.self) { tag in
                        TagChip(
                            tag,
                            style: filterTag == tag ? .selected : .standard,
                            count: stats.usageCounts[tag],
                            onTap: {
                                HapticManager.shared.selectionChanged()
                                withAnimation(Theme.Motion.snappy) {
                                    filterTag = (filterTag == tag) ? nil : tag
                                    scrollToTop = true
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xs + 2)
            }
        } else {
            Button {
                HapticManager.shared.lightTap()
                showingTagPaywall = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appPrimary)
                    Text("Filter by tag with Pro")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.md + 2)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(LinearGradient.appPrimarySoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .stroke(Color.appPrimary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xs + 2)
        }
    }

    private var sortBar: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            sortPill
            dateRangePill

            Spacer(minLength: Theme.Spacing.sm)

            Text(countLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    /// Sort dropdown — native SwiftUI `Menu` sits just below the pill so the
    /// interaction feels instant instead of hijacking the screen with an action sheet.
    private var sortPill: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    HapticManager.shared.selectionChanged()
                    // Update without kicking implicit animations that would
                    // interpolate the pill's width during the Menu dismiss.
                    var txn = Transaction()
                    txn.disablesAnimations = true
                    withTransaction(txn) {
                        sortOption = option
                        scrollToTop = true
                    }
                } label: {
                    Label(option.rawValue, systemImage: option.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sortOption.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.identity)
                Text(sortOption.shortLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .contentTransition(.identity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.9)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(.white)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .padding(.horizontal, Theme.Spacing.md)
            .background(Color.appPrimary)
            .clipShape(Capsule())
            .primaryGlow(strength: 0.2)
            // Ensure layout (pill width) never animates when the label changes.
            .animation(nil, value: sortOption)
        }
        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.lightTap() })
    }

    /// Date-range pill. Shows the active range inline (e.g. "Apr 1 – Apr 22") when
    /// filtering is on, giving users clear feedback without opening the picker.
    private var dateRangePill: some View {
        Button {
            HapticManager.shared.lightTap()
            showingDateRangePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: useDateRangeFilter ? "calendar.badge.checkmark" : "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.identity)
                Text(dateRangeLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .contentTransition(.identity)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(useDateRangeFilter ? .white : .appPrimary)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .padding(.horizontal, Theme.Spacing.md)
            .background(
                Group {
                    if useDateRangeFilter {
                        Color.appPrimary
                    } else {
                        Color.tertiarySystemBackground
                    }
                }
            )
            .clipShape(Capsule())
            .animation(nil, value: useDateRangeFilter)
            .animation(nil, value: rangeStartDate)
            .animation(nil, value: rangeEndDate)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var dateRangeLabel: String {
        guard useDateRangeFilter else { return "Date range" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: rangeStartDate)) – \(formatter.string(from: rangeEndDate))"
    }

    private var countLabel: String {
        switch totalMatchCount {
        case 0: return "No results"
        case 1: return "1 expense"
        default: return "\(totalMatchCount) expenses"
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.systemBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    if isIPad {
                        HStack {
                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back")
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.appPrimary)
                            }

                            Spacer()

                            Text("All Expenses")
                                .font(Theme.Typography.sectionTitle)

                            Spacer()

                            HStack(spacing: Theme.Spacing.xl) {
                                Button {
                                    HapticManager.shared.lightTap()
                                    showingCalendar = true
                                } label: {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.appPrimary)
                                }
                                .accessibilityLabel("Browse by calendar")

                                Button {
                                    HapticManager.shared.lightTap()
                                    showingQuickSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.appPrimary)
                                }
                                .accessibilityLabel("Search expenses")
                            }
                            .frame(height: 32)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    
                    VStack(spacing: Theme.Spacing.lg) {
                        sortBar
                        quickFiltersRow
                        tagsFilterRow
                    }
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.sm)
                    .background(Color.systemBackground)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : -10)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)
                        .padding(.horizontal)
                    
                    // Expense list
                    if totalMatchCount == 0 && !isRecomputing {
                        // Center the empty state in the space below the filter bar
                        // while keeping the filter bar pinned to the top.
                        emptyStateView
                            .opacity(animateContent ? 1 : 0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        expenseList
                            .opacity(animateContent ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(isIPad ? "" : (isRootTab ? "Activity" : "All Expenses"))
            .navigationBarTitleDisplayMode(isRootTab ? .large : .inline)
            .navigationBarHidden(isIPad) // Hide navigation bar on iPad
            .toolbar {
                if !isIPad {
                    if !isRootTab {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back")
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.appPrimary)
                            }
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: Theme.Spacing.md) {
                            if !isSelecting {
                                Button {
                                    HapticManager.shared.lightTap()
                                    showingCalendar = true
                                } label: {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.appPrimary)
                                }
                                .accessibilityLabel("Browse by calendar")

                                Button {
                                    HapticManager.shared.lightTap()
                                    showingQuickSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.appPrimary)
                                }
                                .accessibilityLabel("Search expenses")
                            }

                            Button {
                                HapticManager.shared.lightTap()
                                withAnimation(Theme.Motion.snappy) {
                                    if isSelecting {
                                        // Leaving select mode — also clear any picks.
                                        selectedIds.removeAll()
                                    }
                                    isSelecting.toggle()
                                }
                            } label: {
                                Text(isSelecting ? "Done" : "Select")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.appPrimary)
                            }
                            .accessibilityLabel(isSelecting ? "Exit select mode" : "Select expenses")
                            .disabled(totalMatchCount == 0 && !isSelecting)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingQuickSearch) {
                QuickSearchView()
                    .environmentObject(viewModel)
                    .environmentObject(categoryViewModel)
                    .environmentObject(proManager)
            }
            .sheet(isPresented: $showingCalendar) {
                ExpenseCalendarView()
                    .environmentObject(viewModel)
                    .environmentObject(categoryViewModel)
            }
            .onAppear {
                withAnimation(Theme.Motion.emphasized.delay(0.1)) {
                    animateContent = true
                }
                scrollToTop = false
                recomputeResults(resetPagination: true)
            }
            .onReceive(viewModel.$expenses) { latest in
                // Use the value the publisher just emitted instead of reading
                // `viewModel.expenses` again — `@Published` sends in `willSet`,
                // so the property could still be momentarily stale on the
                // receive tick.
                recomputeResults(resetPagination: false, using: latest)
            }
            .onChange(of: sortOption) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: useDateRangeFilter) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: rangeStartDate) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: rangeEndDate) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: filterCategory) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: filterCustomCategoryId) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: showOnlySubscriptions) {
                recomputeResults(resetPagination: true)
            }
            .onChange(of: filterTag) {
                recomputeResults(resetPagination: true)
            }
            .sheet(isPresented: $showingTagPaywall) {
                PaywallView()
            }
            .onChange(of: categoryViewModel.customCategories) {
                recomputeResults(resetPagination: false)
            }
        }
        .if(isIPad) { view in
            view.navigationViewStyle(StackNavigationViewStyle())
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
        .sheet(isPresented: $showingDateRangePicker) {
            dateRangeSheet
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                bulkActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snappy, value: isSelecting)
        .alert("Delete \(selectedIds.count) expense\(selectedIds.count == 1 ? "" : "s")?", isPresented: $showingBulkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                bulkDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingBulkCategoryPicker) {
            bulkCategoryPickerSheet
        }
        .sheet(isPresented: $showingBulkTagSheet) {
            bulkTagSheet
        }
        .sheet(isPresented: $showingBulkTagPaywall) {
            PaywallView()
        }
    }

    // MARK: - Bulk Select UI

    /// Tap on a row in selection mode toggles its membership; outside of
    /// selection mode opens the editor as before. Centralised so both row
    /// styles (date-grouped and flat) share identical behaviour.
    private func handleRowTap(expense: Expense) {
        if isSelecting {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.tap) {
                if selectedIds.contains(expense.id) {
                    selectedIds.remove(expense.id)
                } else {
                    selectedIds.insert(expense.id)
                }
            }
        } else {
            HapticManager.shared.lightTap()
            selectedExpense = expense
        }
    }

    private func selectionCheckbox(for expense: Expense) -> some View {
        let isOn = selectedIds.contains(expense.id)
        return Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(isOn ? .appPrimary : .secondary.opacity(0.5))
            .accessibilityLabel(isOn ? "Selected" : "Not selected")
            .accessibilityAddTraits(.isButton)
    }

    private var bulkActionBar: some View {
        let count = selectedIds.count
        return HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) selected")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                Button {
                    HapticManager.shared.lightTap()
                    withAnimation(Theme.Motion.snappy) {
                        if selectedIds.count == visibleSelectableExpenseIds.count {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = visibleSelectableExpenseIds
                        }
                    }
                } label: {
                    Text(selectedIds.count == visibleSelectableExpenseIds.count && !visibleSelectableExpenseIds.isEmpty
                         ? "Clear all"
                         : "Select all visible")
                        .font(.caption)
                        .foregroundColor(.appPrimary)
                }
            }

            Spacer(minLength: 0)

            bulkActionButton(icon: "folder.fill", label: "Category") {
                guard !selectedIds.isEmpty else { return }
                showingBulkCategoryPicker = true
            }

            bulkActionButton(icon: "tag.fill", label: "Tag") {
                guard !selectedIds.isEmpty else { return }
                if !proManager.isPro {
                    showingBulkTagPaywall = true
                    return
                }
                bulkTagText = ""
                showingBulkTagSheet = true
            }

            bulkActionButton(icon: "trash.fill", label: "Delete", tint: .red) {
                guard !selectedIds.isEmpty else { return }
                showingBulkDeleteConfirm = true
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        // Solid `systemBackground` instead of `.ultraThinMaterial`. The
        // bar sits **above the scrolling expenses list**, so a live blur
        // would force a fullscreen re-blur on every scroll frame — that
        // alone tanks the 120 Hz ProMotion fast path while the bar is
        // visible. Solid + the existing drop shadow still reads as a
        // floating bar without the GPU cost.
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 6)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func bulkActionButton(icon: String, label: String, tint: Color = .appPrimary, action: @escaping () -> Void) -> some View {
        let disabled = selectedIds.isEmpty
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(disabled ? .secondary.opacity(0.4) : tint)
            .frame(width: 56, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(disabled ? Color.clear : tint.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// IDs of the rows currently visible in the list — used as the universe
    /// for "Select all visible". We use the visible window (not the full
    /// filtered set) so the user gets a predictable, observable result.
    private var visibleSelectableExpenseIds: Set<UUID> {
        Set(visibleExpenses.map(\.id))
    }

    private func bulkDelete() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        HapticManager.shared.success()

        // Optimistic UI — drop the rows from the local snapshot in the same
        // frame the user taps Delete. `pendingDeletionIds` then keeps the
        // recompute pipeline honest so a stale `viewModel.expenses` snapshot
        // (Core Data fetches can briefly return just-saved rows) can't
        // reintroduce the row before the next clean fetch lands.
        withAnimation(Theme.Motion.snappy) {
            pendingDeletionIds.formUnion(ids)
            removeFromLocalSnapshot(ids: ids)
            selectedIds.removeAll()
            isSelecting = false
        }

        viewModel.deleteExpenses(ids: ids)
    }

    /// Strip the given expense ids from the view's cached `computedExpenses`
    /// and `computedDateGroups` so list updates render instantly. Keeps the
    /// match counter and any empty date sections in sync.
    private func removeFromLocalSnapshot(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let beforeCount = computedExpenses.count
        computedExpenses.removeAll { ids.contains($0.id) }
        let removedCount = beforeCount - computedExpenses.count

        if !computedDateGroups.isEmpty {
            var pruned: [(Date, [Expense])] = []
            pruned.reserveCapacity(computedDateGroups.count)
            for (day, items) in computedDateGroups {
                let kept = items.filter { !ids.contains($0.id) }
                if !kept.isEmpty {
                    pruned.append((day, kept))
                }
            }
            computedDateGroups = pruned
        }

        totalMatchCount = max(0, totalMatchCount - removedCount)
    }

    // MARK: - Bulk Category Picker

    private var bulkCategoryPickerSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        bulkCategoryRow(
                            label: category.displayName,
                            icon: category.icon,
                            color: Color.forCategory(category.color)
                        ) {
                            applyBulkCategory(category, customId: nil)
                        }
                    }

                    if !categoryViewModel.customCategories.isEmpty {
                        Divider().padding(.vertical, Theme.Spacing.sm)
                        ForEach(categoryViewModel.customCategories) { custom in
                            bulkCategoryRow(
                                label: custom.name,
                                icon: custom.icon,
                                color: Color.forCategory(custom.colorName)
                            ) {
                                applyBulkCategory(.custom, customId: custom.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .navigationTitle("Change category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingBulkCategoryPicker = false }
                }
            }
        }
    }

    private func bulkCategoryRow(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func applyBulkCategory(_ category: Expense.Category, customId: UUID?) {
        let ids = selectedIds
        viewModel.bulkChangeCategory(ids: ids, to: category, customCategoryId: customId)
        HapticManager.shared.success()
        showingBulkCategoryPicker = false
        withAnimation(Theme.Motion.snappy) {
            selectedIds.removeAll()
            isSelecting = false
        }
    }

    // MARK: - Bulk Tag Sheet

    private var bulkTagSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Add this tag to \(selectedIds.count) expense\(selectedIds.count == 1 ? "" : "s"). Existing tags are kept.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.lg)

                TextField("e.g. work, holiday, refund", text: $bulkTagText)
                    .padding(Theme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .submitLabel(.done)
                    .onSubmit { applyBulkTag() }

                Spacer()
            }
            .navigationTitle("Add tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingBulkTagSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyBulkTag() }
                        .disabled(bulkTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private func applyBulkTag() {
        let trimmed = bulkTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ids = selectedIds
        viewModel.bulkAddTag(ids: ids, tag: trimmed)
        HapticManager.shared.success()
        showingBulkTagSheet = false
        withAnimation(Theme.Motion.snappy) {
            selectedIds.removeAll()
            isSelecting = false
        }
    }

    private var dateRangeSheet: some View {
        NavigationView {
            Form {
                Toggle("Filter by date range", isOn: $useDateRangeFilter)
                
                DatePicker("Start", selection: $rangeStartDate, displayedComponents: [.date])
                    .disabled(!useDateRangeFilter)
                DatePicker("End", selection: $rangeEndDate, displayedComponents: [.date])
                    .disabled(!useDateRangeFilter)
                
                if useDateRangeFilter {
                    Button("Clear Date Filter") {
                        HapticManager.shared.selectionChanged()
                        useDateRangeFilter = false
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDateRangePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if rangeEndDate < rangeStartDate {
                            let tmp = rangeStartDate
                            rangeStartDate = rangeEndDate
                            rangeEndDate = tmp
                        }
                        showingDateRangePicker = false
                        scrollToTop = true
                    }
                }
            }
        }
        .onAppear {
            guard !didApplyInitialFilter, let initialFilter else { return }
            didApplyInitialFilter = true
            
            if initialFilter.useDateRangeFilter,
               let start = initialFilter.rangeStartDate,
               let end = initialFilter.rangeEndDate {
                useDateRangeFilter = true
                rangeStartDate = start
                rangeEndDate = end
            }
            
            showOnlySubscriptions = initialFilter.showOnlySubscriptions
            
            if let raw = initialFilter.filterCategoryRawValue,
               let cat = Expense.Category(rawValue: raw) {
                filterCategory = cat
                filterCustomCategoryId = initialFilter.filterCustomCategoryId
            } else {
                filterCategory = nil
                filterCustomCategoryId = nil
            }
        }
    }
    
    // MARK: - Subviews
    
    /// Are any browse-time filters narrowing the list right now? Used to
    /// distinguish "you have no expenses at all" from "your filters are too tight".
    private var hasActiveFilters: Bool {
        useDateRangeFilter
            || showOnlySubscriptions
            || filterCategory != nil
            || filterTag != nil
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if hasActiveFilters {
            EmptyStatePanel(
                icon: "line.3.horizontal.decrease.circle",
                title: "No expenses match these filters",
                message: "Try clearing a filter, or search for something specific."
            ) {
                VStack(spacing: Theme.Spacing.sm) {
                    PrimaryGradientButton(title: "Clear Filters", width: .hug) {
                        HapticManager.shared.lightTap()
                        withAnimation(Theme.Motion.snappy) {
                            useDateRangeFilter = false
                            showOnlySubscriptions = false
                            filterCategory = nil
                            filterCustomCategoryId = nil
                            filterTag = nil
                            scrollToTop = true
                        }
                    }

                    Button {
                        HapticManager.shared.lightTap()
                        showingQuickSearch = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Search instead")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.appPrimary)
                        .padding(.vertical, Theme.Spacing.xs + 2)
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            EmptyStatePanel(
                icon: "doc.text.magnifyingglass",
                title: "No expenses found",
                message: "Add some expenses to see them here"
            )
        }
    }
    
    private var expenseList: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                // Top indicator view with id for scrolling to top
                HStack {
                    Color.clear.frame(height: 1)
                }
                .id("top")
                
                LazyVStack(spacing: 16) {
                    if isRecomputing && totalMatchCount == 0 {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    
                    if shouldGroupByDate {
                        ForEach(Array(visibleDateGroups.enumerated()), id: \.element.0) { index, dateGroup in
                            dateGroupView(index: index, dateGroup: dateGroup)
                                .onAppear {
                                    if index == max(0, visibleDateGroups.count - 1) {
                                        loadMoreIfNeeded()
                                    }
                                }
                        }
                    } else {
                        ForEach(Array(visibleExpenses.enumerated()), id: \.element.id) { idx, expense in
                            HStack(spacing: Theme.Spacing.sm) {
                                if isSelecting {
                                    selectionCheckbox(for: expense)
                                }
                                ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
                                    .equatable()
                            }
                                .padding(.horizontal)
                                .padding(.top, idx == 0 ? 12 : 0)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleRowTap(expense: expense)
                                }
                                .onAppear {
                                    if idx == max(0, visibleExpenses.count - 1) {
                                        loadMoreIfNeeded()
                                    }
                                }
                        }
                    }
                    
                    // Bottom padding — extra room when the bulk action bar is visible.
                    Color.clear.frame(height: isSelecting ? 96 : 40)
                }
            }
            .onChange(of: sortOption) {
                withAnimation {
                    scrollView.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: viewModel.selectedCategory) {
                withAnimation {
                    scrollView.scrollTo("top", anchor: .top)
                }
            }
        }
    }
    
    private func dateGroupView(index: Int, dateGroup: (Date, [Expense])) -> some View {
        let (date, expenses) = dateGroup
        
        return VStack(spacing: 0) {
            // Date header with gradient background
            dateHeaderView(date: date, expenses: expenses)
            
            // Expenses for this date
            expensesListView(date: date, expenses: expenses, groupIndex: index)
        }
        .padding(.horizontal)
        .padding(.top, index == 0 ? 8 : 16)
    }
    
    private func dateHeaderView(date: Date, expenses: [Expense]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(formatDate(date))
                    .font(Theme.Typography.subsectionTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                // Refund-aware day total so a return on a busy day actually
                // reduces the header number.
                let totalForDay = expenses.netTotal()
                Text("Total: \(viewModel.formattedAmount(totalForDay))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            dateBadgeView(date: date)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        // Match the body so the whole day-group reads as one cohesive
        // white card (header + rows + footer) rather than a grey-capped
        // tile.
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(Theme.Radius.card, corners: [.topLeft, .topRight])
    }

    /// Hoisted so the day header doesn't allocate two `DateFormatter`s
    /// per group on every redraw. Format strings are stable; main-actor
    /// reads only.
    private static let badgeDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    private static let badgeMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private func dateBadgeView(date: Date) -> some View {
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.Spacing.sm, style: .continuous)
                .fill(Color.appPrimary)
                .opacity(0.85)
                .frame(width: 40, height: 40)

            VStack(spacing: 0) {
                Text(Self.badgeDayFormatter.string(from: date))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text(Self.badgeMonthFormatter.string(from: date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private func expensesListView(date: Date, expenses: [Expense], groupIndex: Int) -> some View {
        // NOTE: The `.softShadow()` that used to live here stacked with the
        // shadow each `ExpenseCard` inside already paints — two shadow
        // passes per visible cell when scrolling, which is the #1 cause
        // of jitter for users with many expenses. The cards' built-in
        // elevation now carries the depth; this container is just the
        // bottom corner-rounded white slab beneath them.
        VStack(spacing: 1) {
            ForEach(Array(expenses.enumerated()), id: \.element.id) { expenseIndex, expense in
                expenseRowView(expense: expense, groupIndex: groupIndex, expenseIndex: expenseIndex)
            }
        }
        .background(Color.systemBackground)
        .cornerRadius(Theme.Radius.card, corners: [.bottomLeft, .bottomRight])
    }

    private func expenseRowView(expense: Expense, groupIndex: Int, expenseIndex: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isSelecting {
                selectionCheckbox(for: expense)
            }
            ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
                .equatable()
        }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Color.systemBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                handleRowTap(expense: expense)
            }
            .contextMenu {
                if !isSelecting {
                    Button {
                        selectedExpense = expense
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        HapticManager.shared.lightTap()
                        withAnimation(Theme.Motion.snappy) {
                            isSelecting = true
                            selectedIds.insert(expense.id)
                        }
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        HapticManager.shared.mediumTap()
                        deleteExpense(expense)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .swipeActions(edge: .trailing) {
                if !isSelecting {
                    Button(role: .destructive) {
                        HapticManager.shared.mediumTap()
                        deleteExpense(expense)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)
            // Simplified animation - only for initial appearance, not for every change
            .animation(
                totalMatchCount <= 50
                    ? .easeOut(duration: 0.25).delay(0.02 * Double(min(groupIndex * 3 + expenseIndex, 15)))
                    : .none,
                value: animateContent
            )
    }
    // Grouping is precomputed in `recomputeResults` for date sorts; display limiting is applied by `visibleDateGroups`.
    
    // Delete an expense - using the safer method to prevent index-related crashes.
    // Mirrors the bulk path: optimistic local removal + `pendingDeletionIds`
    // suppression so the row animates out instantly and never reappears via a
    // briefly-stale Core Data fetch.
    private func deleteExpense(_ expense: Expense) {
        HapticManager.shared.success()
        withAnimation(Theme.Motion.snappy) {
            pendingDeletionIds.insert(expense.id)
            removeFromLocalSnapshot(ids: [expense.id])
        }
        viewModel.deleteExpenseById(expense.id)
    }
    
    /// Hoisted so day-group headers don't allocate a fresh formatter on
    /// every render. Medium date style is locale-stable; main-actor only.
    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    // Format date for section headers
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return Self.mediumDateFormatter.string(from: date)
        }
    }

    init(initialFilter: AllExpensesInitialFilter? = nil, isRootTab: Bool = false) {
        self.initialFilter = initialFilter
        self.isRootTab = isRootTab
    }
}

struct AllExpensesView_Previews: PreviewProvider {
    static var previews: some View {
        AllExpensesView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
            .environmentObject(ProManager.shared)
    }
} 