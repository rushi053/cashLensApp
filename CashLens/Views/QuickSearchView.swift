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
///   (Browse-by-Category/Tag strips and the Recent Activity preview were
///   removed — they duplicated Activity's filter strip and the tab itself.)
/// - Active-query state shows a result-count + net-total summary chip,
///   date-grouped result sections (Today / Yesterday / This week / Earlier),
///   and rows that **highlight the matched substring** in the title.
/// - Smarter ranking: title-prefix beats title-contains beats tag/category
///   beats notes beats amount. Amounts are parsed numerically (`$50` ≈ `50.00`)
///   instead of being matched as a brittle `String(format: "%.2f")`.
/// - Tag-only mode: queries beginning with `#` search tags exclusively.
///
/// PERF architecture: a pre-lowered `SearchIndexEntry` array is built
/// off-main once per `expenses` snapshot; each (debounced) keystroke ranks
/// against that index in a detached task which also prebakes the date
/// groups and refund-aware net total, so `body` never walks the dataset.
struct QuickSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    @State private var searchText = ""
    @State private var selectedExpense: Expense?
    @FocusState private var isSearchFocused: Bool

    @State private var searchResults: [Expense] = []
    /// Date-bucketed groups + refund-aware net total, computed in the
    /// same detached pass as the ranking. These used to be derived on
    /// the main thread inside `body` (a full O(N) walk of the results
    /// per redraw, twice); now the view just renders prebaked state.
    @State private var resultGroups: [(title: String, expenses: [Expense])] = []
    @State private var resultNetTotal: Double = 0
    @State private var searchTask: Task<Void, Never>?

    /// Pre-lowered searchable fields for the whole dataset. Built
    /// off-main once per `expenses` snapshot, so the per-keystroke
    /// ranker never calls `.lowercased()` on every title / tag / note
    /// in the store again (that repeated re-lowercasing was the
    /// single biggest cost of a keystroke with a few thousand rows).
    @State private var searchIndex: [SearchIndexEntry] = []
    @State private var indexTask: Task<Void, Never>?

    @State private var recentSearches: [String] = []

    /// Quick-tip "$50" example. Computed once per presentation (see
    /// `computeRoundAmountSample`), never per body evaluation.
    @State private var roundAmountSample: (label: String, query: String)?

    @State private var animateSections = false

    /// Active *direct* filters driven by tapping a chip in the browse view.
    /// These are intentionally separate from `searchText` so chip taps can be
    /// instant (no 150ms debounce, no `Task.detached`, no view-tree thrash).
    // Phase 1 cleanup: chip-filter state removed. The Browse-by-
    // Category and Browse-by-Tag chips in the empty state were the
    // only setters for `activeCategoryFilter` / `activeTagFilter`,
    // and that filter functionality already exists in Activity's
    // category-pill + Tags-chip strip. Search now focuses on its
    // unique value (free-text + smart query parsing); category /
    // tag-via-text still works through the ranker (a typed category
    // name still ranks high, and `#tag` still triggers tag-only
    // mode).

    /// When `true` the next `searchText` change skips the typing debounce.
    /// Set right before mutating `searchText` from a chip tap (Quick Tip,
    /// Recent Search) so the user gets instant feedback instead of a 150ms
    /// pause followed by a sudden view swap.
    @State private var skipNextDebounce = false

    private static let recentsCap = 5

    /// Drives the empty-vs-results view swap. Post-Phase-1 the only
    /// thing that narrows the result set is the typed text query —
    /// see the `activeCategoryFilter` removal comment above.
    private var isQueryActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
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
        // App-wide sheet convention: visible grab handle on every
        // custom-chrome sheet, with the header giving it clear air.
        .presentationDragIndicator(.visible)
        .onAppear {
            loadRecentSearches()
            computeRoundAmountSample()
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
        .onChange(of: searchText) {
            performQuery(textChanged: true, instant: skipNextDebounce)
            skipNextDebounce = false
        }
        // @Published re-emits the current value on subscribe, so this
        // both builds the initial index on presentation and rebuilds
        // it after any save (e.g. editing a result) — which then
        // re-runs the active query against fresh data.
        .onReceive(viewModel.$expenses) { latest in
            rebuildIndex(expenses: latest)
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
                    // No manual requery — the save publishes a fresh
                    // `expenses` value, which rebuilds the index and
                    // re-runs the active query (see `.onReceive`).
                    // The old explicit call here double-ranked every
                    // edit against the stale snapshot first.
                }
            )
            .environmentObject(categoryViewModel)
        }
    }

    // MARK: - Custom Header

    private var customHeader: some View {
        // Shared SheetHeader — divider off because the hero search
        // field directly below provides the visual break.
        SheetHeader(
            title: "Search",
            subtitle: "Find any expense, fast",
            showsDivider: false,
            onClose: { dismiss() }
        )
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
            // Phase 1 cleanup: dropped `categoriesSection`,
            // `tagsBrowseSection`, and `recentExpensesSection`.
            // - Browse by Category duplicated Activity's category pill
            //   strip — the same filter, on a different surface.
            // - Browse by Tag duplicated Activity's `Tags ▾` chip
            //   (and the popular tags were the same ones surfaced
            //   inside the `quickTipsSection` chip set anyway).
            // - Recent Activity preview duplicated the Activity tab
            //   itself, one tap away on the tab bar.
            //
            // Search now reads as one focused surface — type, see
            // ranked results — with just the two affordances that
            // *only* live here: persisted recent searches, and the
            // "Try" chips that teach users about smart query syntax
            // (`#tag`, `$50`, `this month`).
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if !recentSearches.isEmpty {
                        recentSearchesSection
                            .modifier(SearchEntrance(order: 1, animate: animateSections))
                    }

                    quickTipsSection
                        .modifier(SearchEntrance(order: 2, animate: animateSections))

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

    /// "$50" / "$100" / "$500" style example anchored to the user's own
    /// data, so the tip feels grounded.
    ///
    /// PERF: this used to be a computed property that mapped, filtered,
    /// and sorted **every** amount (O(N log N) on main) on each body
    /// evaluation of the empty-query state — including right at sheet
    /// presentation, mid lift animation. It's now computed once per
    /// presentation, off-main, into state (see `computeRoundAmountSample`
    /// called from `onAppear`). An exact live median is irrelevant for a
    /// "Try $50" chip.
    private func computeRoundAmountSample() {
        let amountsSnapshot = viewModel.expenses.map { $0.amount }
        let symbol = viewModel.selectedCurrency.symbol
        Task { @MainActor in
            let value: Int? = await Task.detached(priority: .utility) {
                let amounts = amountsSnapshot.filter { $0 > 0 }.sorted()
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
                return Int(rounded)
            }.value
            guard let value else { return }
            roundAmountSample = (label: "\(symbol)\(value)", query: "\(symbol)\(value)")
        }
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
                            .foregroundColor(.appPrimary)
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

    /// Set the search field text from an *explicit* tap (Quick Tip,
    /// Recent Search). Bypasses the typing debounce so the result
    /// swap feels instantaneous, and intentionally doesn't change
    /// keyboard focus (preventing the keyboard-dismiss animation
    /// that previously stacked onto the result-view transition and
    /// produced a perceptible stutter).
    private func applyTextQueryInstantly(_ text: String) {
        skipNextDebounce = true
        withAnimation(Theme.Motion.snappy) {
            searchText = text
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
                resultSummaryRow
                    .padding(.horizontal, Theme.Spacing.lg)

                // Groups are prebaked off-main by the search task —
                // no per-redraw bucketing here.
                ForEach(resultGroups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
                        Text(group.title)
                            .font(Theme.Typography.subsectionTitle)
                            .foregroundColor(.primary)
                            .padding(.horizontal, Theme.Spacing.xs)

                        // v2: bare rows clustered into a single white
                        // card with hairline dividers — matches the
                        // Activity day-group and calendar day-detail
                        // treatments, so all three "list of expenses"
                        // surfaces feel like one component.
                        VStack(spacing: 0) {
                            ForEach(Array(group.expenses.enumerated()), id: \.element.id) { idx, expense in
                                Button {
                                    HapticManager.shared.lightTap()
                                    saveRecentSearchIfNeeded(searchText)
                                    selectedExpense = expense
                                } label: {
                                    compactExpenseRow(expense: expense, query: searchText)
                                }
                                .buttonStyle(.plain)

                                if idx < group.expenses.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                        .opacity(0.4)
                                }
                            }
                        }
                        .cardSurface()
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer(minLength: Theme.Spacing.tabBarInset)
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private var resultSummaryRow: some View {
        let count = searchResults.count
        // Refund-aware net total, prebaked by the search task.
        let total = resultNetTotal
        return HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(count == 1 ? "expense" : "expenses")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.appPrimary)
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

    /// Group ranked results by relative date bucket. Runs inside the
    /// detached search task (never on the main thread per redraw).
    nonisolated private static func groupResults(_ results: [Expense]) -> [(title: String, expenses: [Expense])] {
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

        for expense in results {
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

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: Theme.Spacing.xs + 2) {
                // Post-Phase-1 the only narrowing input is typed
                // text, so `trimmed` is always non-empty in this
                // branch — but we keep the guard so a future caller
                // doesn't crash on edge cases.
                Text(trimmed.isEmpty ? "No matches" : "No matches for \"\(trimmed)\"")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("Try a different word, a category name, an amount like \"\(viewModel.selectedCurrency.symbol)50\", or a tag like \"#travel\".")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var nothingToSearchView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: Theme.Spacing.xxl)

            Image(systemName: "tray")
                .font(.system(size: 36, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

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
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

    /// Pre-lowered searchable fields for one expense. The ranker only
    /// ever compares against these, so `.lowercased()` runs once per
    /// data snapshot instead of once per field per expense *per
    /// keystroke*.
    private struct SearchIndexEntry: Sendable {
        let expense: Expense
        let titleLower: String
        let tagsLower: [String]
        let notesLower: String?
        /// Default-category raw value, lowered (this is "custom" for
        /// custom-category expenses — kept so behavior matches the old
        /// `rawValue.contains` check exactly).
        let categoryLower: String
        /// Resolved custom-category name, lowered. Nil for defaults.
        let customNameLower: String?
        let amountCents: Int
    }

    /// Everything the results UI needs, computed in one detached pass.
    private struct SearchOutput: Sendable {
        let results: [Expense]
        let groups: [(title: String, expenses: [Expense])]
        let netTotal: Double
    }

    /// (Re)build the search index off-main. Called from `.onReceive`
    /// on the expenses publisher — once at presentation and again after
    /// any save. If a query is active when a fresh index lands, it is
    /// re-run so visible results always reflect current data.
    private func rebuildIndex(expenses: [Expense]) {
        indexTask?.cancel()
        let customCategoriesSnapshot = categoryViewModel.customCategories
        indexTask = Task { @MainActor in
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildIndex(expenses: expenses, customCategories: customCategoriesSnapshot)
            }.value
            guard !Task.isCancelled else { return }
            searchIndex = built
            if isQueryActive {
                performQuery(textChanged: false, instant: true)
            }
        }
    }

    nonisolated private static func buildIndex(
        expenses: [Expense],
        customCategories: [CustomCategory]
    ) -> [SearchIndexEntry] {
        let customNameById: [UUID: String] = Dictionary(
            uniqueKeysWithValues: customCategories.map { ($0.id, $0.name.lowercased()) }
        )
        return expenses.map { e in
            SearchIndexEntry(
                expense: e,
                titleLower: e.title.lowercased(),
                tagsLower: (e.tags ?? []).map { $0.lowercased() },
                notesLower: e.notes?.lowercased(),
                categoryLower: e.category.rawValue.lowercased(),
                customNameLower: e.customCategoryId.flatMap { customNameById[$0] },
                amountCents: Int((e.amount * 100).rounded())
            )
        }
    }

    /// Single entry point for recomputing search state.
    ///
    /// The only input is the typed text query. The ranker understands
    /// `#tag`, `$50`, and date keywords through `rankedSearch`, so
    /// power users keep every filtering primitive — expressed inline
    /// in the query.
    ///
    /// `instant: true` skips the 150ms typing debounce. Use it for
    /// explicit user gestures (Quick Tip tap, recent-search tap,
    /// post-save refresh) so they never feel laggy. Plain typing
    /// still debounces to keep the ranker off the keystroke path.
    private func performQuery(textChanged: Bool, instant: Bool) {
        searchTask?.cancel()

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // No text → clear results, swap back to the browse view.
        guard !trimmed.isEmpty else {
            searchResults = []
            resultGroups = []
            resultNetTotal = 0
            return
        }

        let indexSnapshot = searchIndex
        let needsDebounce = textChanged && !instant

        searchTask = Task { @MainActor in
            if needsDebounce {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }

            let output = await Task.detached(priority: .userInitiated) {
                let results = Self.rankedSearch(query: trimmed, index: indexSnapshot)
                return SearchOutput(
                    results: results,
                    groups: Self.groupResults(results),
                    netTotal: results.netTotal()
                )
            }.value

            guard !Task.isCancelled else { return }
            searchResults = output.results
            resultGroups = output.groups
            resultNetTotal = output.netTotal
        }
    }

    /// Score-based search over the prebuilt index. Higher scores mean
    /// better matches; ties break by most-recent date so the most
    /// relevant *and* recent expenses win.
    nonisolated private static func rankedSearch(
        query rawQuery: String,
        index: [SearchIndexEntry]
    ) -> [Expense] {
        let lowered = rawQuery.lowercased()

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
        let queryCents: Int? = amountQuery.map { Int(($0 * 100).rounded()) }

        struct Scored {
            let expense: Expense
            let score: Int
        }

        var scored: [Scored] = []
        scored.reserveCapacity(index.count)

        for entry in index {
            // Apply hard filters first.
            if let dateRange, !(entry.expense.date >= dateRange.start && entry.expense.date < dateRange.end) {
                continue
            }
            if let tagQuery {
                if !entry.tagsLower.contains(where: { $0.contains(tagQuery) }) { continue }
            }

            var score = 0

            // 1. Title prefix is the strongest signal.
            if entry.titleLower.hasPrefix(lowered) { score += 100 }
            else if entry.titleLower.contains(lowered) { score += 60 }

            // 2. Tag match (any tag).
            if entry.tagsLower.contains(where: { $0.contains(lowered) }) {
                score += 50
            }

            // 3. Category name (default + custom).
            if entry.categoryLower.contains(lowered) {
                score += 40
            } else if let customName = entry.customNameLower, customName.contains(lowered) {
                score += 40
            }

            // 4. Notes.
            if let notes = entry.notesLower, notes.contains(lowered) {
                score += 25
            }

            // 5. Amount (numeric, exact-to-cents match).
            if let queryCents, entry.amountCents == queryCents {
                score += 70
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
                scored.append(Scored(expense: entry.expense, score: score))
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
