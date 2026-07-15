import SwiftUI

struct AllExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bulkSelectionBinding) private var bulkSelectionBinding
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
    /// Guards the `.onAppear` work (entrance animation + initial
    /// recompute). As a tab root this view stays mounted across tab
    /// switches, so without the guard every revisit re-ran a full
    /// recompute with `resetPagination: true` — trashing the user's
    /// scroll depth past 250 rows and re-flashing the list. Data
    /// freshness while the tab is hidden is already covered by
    /// `.onReceive(viewModel.$expenses)` below.
    @State private var hasAppeared = false
    /// PERF: TabView keeps this view permanently mounted, so the
    /// `.onReceive(viewModel.$expenses)` below used to run a full
    /// filter+sort+group recompute on **every** expense publish even
    /// while the user was on another tab — invisible work contending
    /// for the main actor right when they tap around. Mirror
    /// StatisticsView's pattern: skip recomputes while hidden, flag
    /// them pending, and run one catch-up pass on the next appear.
    @State private var isTabVisible = false
    @State private var recomputePending = false
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
    /// position, selection) is preserved on dismiss. Kept for the iPad
    /// header button and any legacy deep-links; on iPhone the calendar
    /// is now a first-class view mode (see `viewMode`).
    @State private var showingCalendar = false

    /// First-class Activity view mode — List (chronological ledger) or
    /// Calendar (month-grid browse). Promoted from a buried toolbar
    /// icon to a visible header toggle; the calendar renders embedded
    /// (`ExpenseCalendarView(isEmbedded: true)`) so switching modes
    /// doesn't lose tab context. List state (filters, scroll position)
    /// is preserved across switches because the list stays mounted in
    /// state, just not rendered.
    enum ViewMode: String, CaseIterable {
        case list
        case calendar

        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .calendar: return "calendar"
            }
        }

        var label: String {
            switch self {
            case .list: return "List"
            case .calendar: return "Calendar"
            }
        }
    }
    @State private var viewMode: ViewMode = .list

    // Performance: cache computed results + paginate rendering for large datasets
    @State private var computedExpenses: [Expense] = []
    @State private var computedDateGroups: [(Date, [Expense])] = []
    @State private var totalMatchCount: Int = 0
    /// Refund-aware net total of the *entire* filtered result set (not
    /// just the visible pagination window). Shown next to the match
    /// count so the screen answers "how much?" — the number users come
    /// to a ledger to verify — without them summing rows in their head.
    @State private var totalNetAmount: Double = 0
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
    
    // NOTE: Removed the dead `sortExpenses(_:)` helper. The live sort
    // path runs inside `recomputeResults` (off-main, against snapshot
    // data); the dead copy's `.category` branch also called
    // `viewModel.categoryDisplayName(for:)` inside the sort comparator —
    // at the time a Core Data fetch per comparison — making it a
    // performance landmine if ever wired back up.
    
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
            let netTotal = sorted.netTotal()
            await MainActor.run {
                guard !Task.isCancelled else { return }
                totalMatchCount = sorted.count
                totalNetAmount = netTotal
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
                // "All" is a *true* reset — it also clears the tag and
                // date-range filters (it used to leave those active
                // while lighting up as selected, which read as a lie).
                // Its lit state now means exactly "nothing is filtered".
                PillChip(
                    title: "All",
                    icon: "line.3.horizontal.decrease.circle",
                    isSelected: !hasActiveFilters,
                    shape: .rounded
                ) {
                    HapticManager.shared.selectionChanged()
                    withAnimation(Theme.Motion.snappy) {
                        filterCategory = nil
                        filterCustomCategoryId = nil
                        showOnlySubscriptions = false
                        filterTag = nil
                        useDateRangeFilter = false
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

                // Tags chip — only appears when the user has at least
                // one tag in use. Collapses the entire former tags row
                // into one menu-backed pill, eliminating an extra
                // strip of horizontal scrolling at the top of the
                // screen. For free users it's a paywall entry point;
                // for Pro users it's a quick switcher.
                tagsFilterChip
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xs + 2)
        }
    }

    /// Compact replacement for the old always-visible tags row.
    /// Behaviour matrix:
    ///   • No tags exist anywhere      → chip hidden entirely
    ///   • Pro user, no active filter  → "Tags ▾" → menu to pick
    ///   • Pro user, active filter     → "#test ✕" → tap to clear,
    ///                                   long-press menu to swap
    ///   • Free user                   → "Tags ✨" → paywall
    @ViewBuilder
    private var tagsFilterChip: some View {
        let stats = viewModel.tagStats
        let orderedTags = stats.popularTags

        if !orderedTags.isEmpty {
            if proManager.isPro {
                Menu {
                    if filterTag != nil {
                        Button(role: .destructive) {
                            HapticManager.shared.selectionChanged()
                            withAnimation(Theme.Motion.snappy) {
                                filterTag = nil
                                scrollToTop = true
                            }
                        } label: {
                            Label("Clear tag filter", systemImage: "xmark.circle")
                        }
                        Divider()
                    }
                    ForEach(orderedTags, id: \.self) { tag in
                        Button {
                            HapticManager.shared.selectionChanged()
                            withAnimation(Theme.Motion.snappy) {
                                filterTag = (filterTag == tag) ? nil : tag
                                scrollToTop = true
                            }
                        } label: {
                            if let count = stats.usageCounts[tag] {
                                Label("#\(tag) (\(count))", systemImage: filterTag == tag ? "checkmark" : "number")
                            } else {
                                Label("#\(tag)", systemImage: filterTag == tag ? "checkmark" : "number")
                            }
                        }
                    }
                } label: {
                    tagChipLabel
                }
                // No haptic on the Menu label — the system menu fires
                // its own feedback on open, and the old lightTap here
                // double-buzzed (design review haptic map).
            } else {
                Button {
                    HapticManager.shared.lightTap()
                    showingTagPaywall = true
                } label: {
                    tagChipLabelProUpsell
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    /// Pill label for the Pro tags-filter chip. Renders the active
    /// `#tag` inline (with an X-circle to communicate "tap to dismiss
    /// via menu") when a filter is set, or a plain "Tags ▾" affordance
    /// when nothing is active.
    private var tagChipLabel: some View {
        HStack(spacing: 6) {
            if let activeTag = filterTag {
                Text("#\(activeTag)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .opacity(0.8)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: 13, weight: .semibold))
                Text("Tags")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
            }
        }
        .foregroundColor(filterTag != nil ? .white : .appPrimary)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            Group {
                if filterTag != nil {
                    Color.appPrimary
                } else {
                    Color.tertiarySystemBackground
                }
            }
        )
        .clipShape(Capsule())
        .animation(nil, value: filterTag)
    }

    /// Free-tier label for the tags chip — same shape, sparkle icon
    /// instead of chevron, hairline outlined treatment to signal "Pro".
    private var tagChipLabelProUpsell: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
            Text("Tags")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.appPrimary)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            Capsule().fill(Color.appPrimary.opacity(0.08))
        )
        .overlay(
            Capsule().stroke(Color.appPrimary.opacity(0.25), lineWidth: 1)
        )
    }

    /// Promoted search + view-mode header row. Search used to hide
    /// behind a toolbar magnifying glass; it's now a visible
    /// field-styled button that opens `QuickSearchView` (kept as the
    /// app's single search surface rather than embedding a second
    /// search implementation). The List | Calendar toggle promotes
    /// the month-grid from a buried toolbar icon to a first-class
    /// view mode.
    private var searchAndModeRow: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            searchFieldButton
            viewModeToggle
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var searchFieldButton: some View {
        Button {
            HapticManager.shared.lightTap()
            showingQuickSearch = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Search expenses")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.sm + 2)
            .padding(.horizontal, Theme.Spacing.md)
            .fieldCard(radius: Theme.Radius.row)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search expenses")
    }

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    guard viewMode != mode else { return }
                    HapticManager.shared.selectionChanged()
                    withAnimation(Theme.Motion.snappy) {
                        // Bulk selection only exists in list mode — exit
                        // it cleanly before the mode swap so the FAB and
                        // action bar can't get stranded.
                        if isSelecting {
                            selectedIds.removeAll()
                            isSelecting = false
                        }
                        viewMode = mode
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewMode == mode ? .white : .secondary)
                        .frame(width: 40, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.chip - 2, style: .continuous)
                                .fill(viewMode == mode ? Color.appPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.label) view")
                .accessibilityAddTraits(viewMode == mode ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Color.tertiarySystemBackground)
        )
    }

    /// In-content page header for the Activity tab root — pageTitle
    /// on the leading edge (matching Today's and Insights' in-content
    /// titles) with the Select toggle where the toolbar button used
    /// to live. Only rendered when `isRootTab` on iPhone; the sheet
    /// presentation keeps its inline nav bar, and iPad keeps its own
    /// custom header.
    private var activityPageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Activity")
                .font(Theme.Typography.pageTitle)
                .foregroundColor(.primary)

            Spacer()

            if viewMode == .list {
                selectModeButton
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
    }

    /// "Select" / "Done" toggle shared by the in-content header
    /// (tab root) and the nav-bar toolbar (sheet presentation).
    private var selectModeButton: some View {
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

    private var sortBar: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            sortPill
            dateRangePill

            Spacer(minLength: Theme.Spacing.sm)

            Text(countLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(Theme.Motion.snappy, value: totalMatchCount)
                .accessibilityLabel(countAccessibilityLabel)
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
        // No haptic on the Menu label — the system menu fires its own
        // feedback on open; the old lightTap double-buzzed.
    }

    /// Date-range button. Compact icon-only chip when no range is
    /// active — saves horizontal real estate in the sort bar and
    /// avoids competing visually with the sort pill. When a range is
    /// active, the button expands inline to show the picked window
    /// (e.g. "Apr 1 – Apr 22") so the user can see the active state
    /// without opening the picker.
    ///
    /// Icon sized at 16pt (vs the 13pt used inside the sort pill) so
    /// the icon-only form has roughly the same visual weight as the
    /// pill sitting next to it — the previous 13pt looked deflated
    /// and easy to miss as a tappable target.
    private var dateRangePill: some View {
        Button {
            HapticManager.shared.lightTap()
            showingDateRangePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: useDateRangeFilter ? "calendar.badge.checkmark" : "calendar")
                    .font(.system(size: useDateRangeFilter ? 13 : 16, weight: .semibold))
                    .contentTransition(.identity)
                if useDateRangeFilter {
                    Text(dateRangeLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .contentTransition(.identity)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(useDateRangeFilter ? .white : .appPrimary)
            .padding(.vertical, useDateRangeFilter ? Theme.Spacing.xs + 2 : 8)
            .padding(.horizontal, useDateRangeFilter ? Theme.Spacing.md : 14)
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
        .accessibilityLabel(useDateRangeFilter ? "Date range: \(dateRangeLabel)" : "Filter by date range")
    }

    private var dateRangeLabel: String {
        guard useDateRangeFilter else { return "Date range" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: rangeStartDate)) – \(formatter.string(from: rangeEndDate))"
    }

    /// "34 · ₹12,450" — match count plus the refund-aware net total of
    /// the filtered set. The word "expenses" is dropped in favor of the
    /// amount because "how much?" is the question users actually bring
    /// to a ledger; the count alone made them sum rows mentally.
    private var countLabel: String {
        guard totalMatchCount > 0 else { return "No results" }
        return "\(totalMatchCount) · \(viewModel.formattedAmount(totalNetAmount))"
    }

    private var countAccessibilityLabel: String {
        guard totalMatchCount > 0 else { return "No results" }
        let noun = totalMatchCount == 1 ? "expense" : "expenses"
        return "\(totalMatchCount) \(noun) totaling \(viewModel.formattedAmount(totalNetAmount))"
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
                    
                    // v2 nav fix: as the Activity tab root the screen
                    // draws its own in-content page title (same
                    // treatment as Today and Insights) instead of a
                    // UIKit large-title bar. The legacy NavigationView
                    // large title was the only one of the four tabs
                    // whose chrome re-laid itself out on every tab
                    // switch — the "different animation" on Activity.
                    if isRootTab && !isIPad {
                        activityPageHeader
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : -10)
                    }

                    // Promoted header — visible search field + List |
                    // Calendar toggle. Always on screen in both view
                    // modes so switching back is one tap.
                    searchAndModeRow
                        .padding(.top, Theme.Spacing.sm)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : -10)

                    if viewMode == .calendar {
                        // First-class calendar mode — embedded month grid
                        // (no NavigationView / sheet chrome of its own).
                        ExpenseCalendarView(isEmbedded: true)
                            .padding(.top, Theme.Spacing.sm)
                            .transition(.opacity)
                    } else {
                    // Compacted filter header. The former tags row is
                    // gone — tags now live as a single chip at the end
                    // of `quickFiltersRow`, cutting one full strip of
                    // horizontal scrolling. Tighter vertical spacing
                    // (md instead of lg) since there are fewer rows.
                    VStack(spacing: Theme.Spacing.md) {
                        sortBar
                        quickFiltersRow
                    }
                    .padding(.top, Theme.Spacing.md)
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
                }
                .animation(Theme.Motion.snappy, value: viewMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(isIPad || isRootTab ? "" : "All Expenses")
            .navigationBarTitleDisplayMode(.inline)
            // Hidden on iPad (custom header above) AND as the tab
            // root, where the in-content `activityPageHeader` draws
            // the title. The old UIKit large-title bar re-ran its
            // expand/settle layout on every tab switch — the one tab
            // whose appearance visibly animated.
            .navigationBarHidden(isIPad || isRootTab)
            .toolbar {
                if !isIPad && !isRootTab {
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

                    // Calendar + search toolbar icons are gone on iPhone —
                    // both are promoted to the always-visible header row
                    // (`searchAndModeRow`). Select only applies to the
                    // list, so it hides in calendar mode.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if viewMode == .list {
                            selectModeButton
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
                isTabVisible = true
                // A publish arrived while this tab was hidden — run the
                // single catch-up pass now that the work is visible.
                if recomputePending {
                    recomputePending = false
                    recomputeResults(resetPagination: false)
                }
                // Once per view lifetime (≈ once per session for the
                // tab root, which stays mounted across tab switches).
                // Re-running this on every tab revisit replayed the
                // entrance motion window and reset pagination/scroll —
                // the other tabs guard their appearance work the same
                // way (see StatisticsView's onAppear PERF note).
                guard !hasAppeared else { return }
                hasAppeared = true
                // Consume the deep-link / notification filter before the
                // first recompute so the list renders pre-filtered. This
                // must live on the main view's appearance (it used to sit
                // on the date-range sheet's content, which deep-link
                // presentations never open — so their filter was ignored).
                applyInitialFilterIfNeeded()
                withAnimation(Theme.Motion.emphasized.delay(0.1)) {
                    animateContent = true
                }
                recomputeResults(resetPagination: true)
            }
            .onReceive(viewModel.$expenses) { latest in
                // PERF: while the tab is hidden, don't burn a full
                // filter+sort+group pass the user can't see — just flag
                // it; `onAppear` runs one catch-up recompute. While
                // visible, use the value the publisher just emitted
                // instead of reading `viewModel.expenses` again —
                // `@Published` sends in `willSet`, so the property could
                // still be momentarily stale on the receive tick.
                if isTabVisible {
                    recomputeResults(resetPagination: false, using: latest)
                } else {
                    recomputePending = true
                }
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
                PaywallView(context: .tags)
            }
            .onChange(of: categoryViewModel.customCategories) {
                // Only affects display names in the category sort — no
                // reason to pay for it while hidden either.
                if isTabVisible {
                    recomputeResults(resetPagination: false)
                } else {
                    recomputePending = true
                }
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
        // Mirror the local selection flag up to the root tab view so it
        // can hide the floating "+" button while the inline action bar
        // is on screen (otherwise the FAB sits on top of the Delete
        // button and steals the tap).
        .onChange(of: isSelecting) { _, newValue in
            bulkSelectionBinding.wrappedValue = newValue
        }
        .onDisappear {
            isTabVisible = false
            // Safety net: if the user navigates away while still in
            // selection mode (rare but possible), reset the root flag
            // so the FAB reappears on the next tab.
            if bulkSelectionBinding.wrappedValue {
                bulkSelectionBinding.wrappedValue = false
            }
        }
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
            PaywallView(context: .tags)
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

    /// Long-press menu shared by both row styles (date-grouped and
    /// flat amount/category sorts) — previously only the date-grouped
    /// rows had Edit / Select / Delete, so switching to "Highest
    /// Amount" silently lost row actions. Empty while selecting.
    @ViewBuilder
    private func rowContextMenuItems(for expense: Expense) -> some View {
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
        let removedNet = computedExpenses.filter { ids.contains($0.id) }.netTotal()
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
        totalNetAmount -= removedNet
        if totalMatchCount == 0 { totalNetAmount = 0 }
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

    /// One-tap windows for the ranges people actually reach for —
    /// two wheel-picker interactions collapse into a single tap and
    /// the sheet dismisses itself with the filter applied.
    private var dateRangePresets: [(label: String, range: () -> (Date, Date))] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return [
            ("Last 7 days", { (cal.date(byAdding: .day, value: -6, to: today) ?? today, Date()) }),
            ("Last 30 days", { (cal.date(byAdding: .day, value: -29, to: today) ?? today, Date()) }),
            ("This month", {
                let start = cal.dateInterval(of: .month, for: Date())?.start ?? today
                return (start, Date())
            }),
            ("Last month", {
                let thisMonthStart = cal.dateInterval(of: .month, for: Date())?.start ?? today
                let start = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? today
                let end = cal.date(byAdding: .day, value: -1, to: thisMonthStart) ?? today
                return (start, end)
            })
        ]
    }

    private func applyPresetRange(_ preset: (label: String, range: () -> (Date, Date))) {
        HapticManager.shared.selectionChanged()
        let (start, end) = preset.range()
        rangeStartDate = start
        rangeEndDate = end
        useDateRangeFilter = true
        showingDateRangePicker = false
        scrollToTop = true
    }

    private var dateRangeSheet: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(dateRangePresets, id: \.label) { preset in
                        Button {
                            applyPresetRange(preset)
                        } label: {
                            HStack {
                                Text(preset.label)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.appPrimary)
                            }
                        }
                    }
                } header: {
                    Text("Quick ranges")
                }

                Section {
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
                } header: {
                    Text("Custom range")
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
    }

    /// One-shot application of the deep-link / notification filter
    /// (`initialFilter`), run from the main view's first appearance —
    /// covers both the Activity tab root and the sheet presentation
    /// deep links use. Once-per-lifetime via `didApplyInitialFilter`
    /// (same pattern as `hasAppeared`).
    private func applyInitialFilterIfNeeded() {
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
                icon: "line.3.horizontal.decrease",
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
            // Copy matched to Today's first-run tone (the review
            // flagged this state as flat next to Today's "Start with
            // one expense." hero).
            EmptyStatePanel(
                icon: "list.bullet.rectangle.portrait",
                title: "Nothing here yet",
                message: "Your ledger starts with one tap — hit + to log the first one."
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
                                .contextMenu {
                                    rowContextMenuItems(for: expense)
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
            // `scrollToTop` is the one-shot signal every filter/sort
            // mutation raises (chips, sort menu, date-range Done, tag
            // menu, Clear Filters). It previously had no listener, so
            // changing filters while scrolled deep left the user
            // stranded mid-way through a *different* result set.
            .onChange(of: scrollToTop) { _, needsScroll in
                guard needsScroll else { return }
                scrollToTop = false
                withAnimation {
                    scrollView.scrollTo("top", anchor: .top)
                }
            }
            // NOTE: removed a dead `.onChange(of: viewModel.selectedCategory)`
            // scroll-to-top — that property is the *Home* screen's filter;
            // Activity's own filters live in local @State and already
            // raise `scrollToTop`. The listener just added an equality
            // check on every Home filter change while this tab stayed
            // mounted, and could yank Activity's scroll position for a
            // filter it doesn't even apply.
        }
    }
    
    private func dateGroupView(index: Int, dateGroup: (Date, [Expense])) -> some View {
        let (date, expenses) = dateGroup

        // Header + rows are wrapped in one elevated `.cardSurface()`
        // tile (same as Today's Recent block). Rows underneath use
        // `.bare` style with hairline separators between them so the
        // group reads as one cohesive day — not several nested
        // shadow stacks (the old structure painted shadows on each
        // ExpenseCard AND on the wrapper, the visible weight of
        // which was the audit's #1 visual-noise finding).
        return VStack(spacing: 0) {
            dateHeaderView(date: date, expenses: expenses)
            Divider()
                .padding(.leading, Theme.Spacing.lg)
            expensesListView(date: date, expenses: expenses, groupIndex: index)
        }
        .cardSurface()
        .padding(.horizontal)
        .padding(.top, index == 0 ? 8 : 14)
    }

    private func dateHeaderView(date: Date, expenses: [Expense]) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            dateBadgeView(date: date)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(date))
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)

                // Refund-aware day total so a return on a busy day actually
                // reduces the header number.
                let totalForDay = expenses.netTotal()
                let count = expenses.count
                Text("\(count) \(count == 1 ? "expense" : "expenses") · \(viewModel.formattedAmount(totalForDay))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
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
        // Softer treatment — tinted background + colored numerals
        // instead of the old fully-filled appPrimary square. Reads
        // as a calendar chip, not a callout pill, which matches the
        // new "data first, decoration second" rhythm.
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.appPrimary.opacity(0.12))
                .frame(width: 42, height: 42)

            VStack(spacing: 0) {
                Text(Self.badgeDayFormatter.string(from: date))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appPrimary)
                    .monospacedDigit()

                Text(Self.badgeMonthFormatter.string(from: date))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(Color.appPrimary.opacity(0.8))
            }
        }
    }

    private func expensesListView(date: Date, expenses: [Expense], groupIndex: Int) -> some View {
        // Rows use the `.bare` ExpenseCard style. Each row is
        // separated by a leading-inset hairline so the group reads
        // as one cohesive day (instead of N visually-elevated tiles
        // stacked on each other). No background here — the parent
        // `.cardSurface()` provides it.
        VStack(spacing: 0) {
            ForEach(Array(expenses.enumerated()), id: \.element.id) { expenseIndex, expense in
                expenseRowView(expense: expense, groupIndex: groupIndex, expenseIndex: expenseIndex)
                if expenseIndex < expenses.count - 1 {
                    Divider()
                        .padding(.leading, Theme.Spacing.lg + 42 + Theme.Spacing.md)
                }
            }
        }
    }

    private func expenseRowView(expense: Expense, groupIndex: Int, expenseIndex: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isSelecting {
                selectionCheckbox(for: expense)
                    .padding(.leading, Theme.Spacing.lg)
            }
            ExpenseCard(
                expense: expense,
                viewModel: viewModel,
                categoryViewModel: categoryViewModel,
                style: .bare
            )
                .equatable()
        }
            .contentShape(Rectangle())
            .onTapGesture {
                handleRowTap(expense: expense)
            }
            .contextMenu {
                rowContextMenuItems(for: expense)
            }
            // NOTE: no `.swipeActions` here — that modifier only works
            // inside a `List`; on this LazyVStack it was silently dead
            // code. Row deletion lives in the context menu and bulk
            // select instead.
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