import SwiftUI

// MARK: - Activity on regular width (iPad, iPhone Duo inner display)
//
// Phase A gave Activity two panes on regular width (ledger | inline
// editor). This file adds the third region and the details that make
// the two-pane layout feel designed rather than assembled:
//
//   ┌ FILTERS ─┐┌ Activity ────────── Select (+) ┐┌ EXPENSE · Editing ┐
//   │ ● All    ││ [search]                 [≣][▦]││                   │
//   │ ○ Subs   ││                     34 · ₹12,450││  form (≤ 640pt)   │
//   │ ○ Food   ││ ┌ Today ──────────────────────┐ ││                   │
//   │ …        ││ │ Coffee               ₹120  │ ││                   │
//   │ TAGS     ││ │ Metro                 ₹60  │ ││                   │
//   │ SORT     ││ └────────────────────────────┘ ││  [Update Expense] │
//   │ RANGE    ││                                ││                   │
//   └──────────┘└────────────────────────────────┘└───────────────────┘
//     240pt         300…480pt                        rest
//
//   • Filter rail (≥ `LargeScreenLayout.threeRegionMinimumWidth`
//     measured): every filter the chip scroller offered — All,
//     Subscriptions, each category, tags (Pro), sort, date range — as a
//     vertical list, so the whole filter state is visible at once. The
//     ledger drops its chip row and sort/range pills while the rail is
//     up; the count · total stays in the ledger header.
//   • Empty detail column: a summary of the filtered ledger (count, net
//     total, the active filter) plus the "Add expense" action, instead
//     of a blank "Select an expense" placeholder.
//   • Selected-row tint so the ledger and the editor read as one
//     selection.
//
// Everything mutates the same `@State` the chips mutate (same
// animation, same `scrollToTop` signal), so the rail appearing or
// disappearing — Split View drag, Duo fold, rotation — never loses a
// filter, the selection, or bulk-select mode. Only reached when
// `showsEditorInDetailColumn` (root tab + regular width).
extension AllExpensesView {

    /// Third region on wide regular layouts only. Duo inner landscape
    /// (~830pt usable) and 11" portrait stay two-pane with the chip row.
    var showsFilterRail: Bool {
        showsEditorInDetailColumn
            && !dynamicTypeSize.isAccessibilitySize
            && largeScreenMeasuredWidth >= LargeScreenLayout.threeRegionMinimumWidth
    }

    // MARK: Selection tint

    /// Background for a ledger row whose editor is open in the detail
    /// column. `Color.clear` everywhere else — including every compact
    /// layout, where the editor is a sheet.
    func largeScreenSelectionTint(for expense: Expense, cornerRadius: CGFloat = 0) -> some View {
        let isSelected = showsEditorInDetailColumn && selectedExpense?.id == expense.id
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isSelected ? Color.appPrimary.opacity(0.08) : Color.clear)
    }

    // MARK: Empty detail column

    var largeScreenEmptyDetail: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)

            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            VStack(spacing: Theme.Spacing.sm) {
                Text(totalMatchCount == 0 ? "Nothing to show" : "Select an expense")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                Text(largeScreenEmptyDetailMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }

            if totalMatchCount > 0 {
                largeScreenLedgerSummary
            }

            if let onRequestAddExpense {
                Button {
                    HapticManager.shared.mediumTap()
                    onRequestAddExpense()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Add expense")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Capsule().fill(LinearGradient.appDuotone))
                    .primaryGlow(strength: 0.22)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .accessibilityLabel("Add expense")
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    private var largeScreenEmptyDetailMessage: String {
        if totalMatchCount == 0 {
            return hasActiveFilters
                ? "No expenses match the current filters."
                : "Your ledger starts with one tap."
        }
        return "Pick a row to view or edit it here. Filters, search and sorting stay on the left."
    }

    /// "34 expenses · ₹12,450" plus the active filter, so the pane
    /// answers "what am I looking at?" before anything is selected.
    private var largeScreenLedgerSummary: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(viewModel.formattedAmount(totalNetAmount))
                .font(Theme.Typography.numeric)
                .monospacedDigit()
                .foregroundColor(.primary)
                .contentTransition(.numericText())
            Text(largeScreenSummaryCaption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .cardSurface()
    }

    private var largeScreenSummaryCaption: String {
        let noun = totalMatchCount == 1 ? "expense" : "expenses"
        var parts: [String] = ["\(totalMatchCount) \(noun)"]
        if showOnlySubscriptions { parts.append("subscriptions") }
        if let category = filterCategory {
            if category == .custom,
               let id = filterCustomCategoryId,
               let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
                parts.append(custom.name)
            } else if category != .custom {
                parts.append(category.rawValue)
            }
        }
        if let tag = filterTag { parts.append("#\(tag)") }
        if useDateRangeFilter { parts.append(dateRangeLabel) }
        return parts.joined(separator: " · ")
    }

    // MARK: Filter rail

    var filterRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                railFilterGroup
                railTagsGroup
                railSortGroup
                railDateRangeGroup
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xl + Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.scrollBottomClearance)
        }
        .background(Color.secondarySystemBackground.opacity(0.45))
        .animation(Theme.Motion.snappy, value: filterCategory)
        .animation(Theme.Motion.snappy, value: filterTag)
        .animation(Theme.Motion.snappy, value: useDateRangeFilter)
    }

    private func applyRailChange(_ change: () -> Void) {
        HapticManager.shared.selectionChanged()
        withAnimation(Theme.Motion.snappy) {
            change()
            scrollToTop = true
        }
    }

    private var railFilterGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            LargeScreenRailHeader(title: "Filters")

            // "All" is the same true reset the chip performs: category,
            // subscriptions, tag and date range all clear together.
            LargeScreenRailRow(
                title: "All",
                icon: "line.3.horizontal.decrease.circle",
                isSelected: !hasActiveFilters
            ) {
                applyRailChange {
                    filterCategory = nil
                    filterCustomCategoryId = nil
                    showOnlySubscriptions = false
                    filterTag = nil
                    useDateRangeFilter = false
                }
            }

            LargeScreenRailRow(
                title: "Subscriptions",
                icon: "arrow.triangle.2.circlepath",
                isSelected: showOnlySubscriptions
            ) {
                applyRailChange { showOnlySubscriptions.toggle() }
            }

            ForEach(viewModel.getAvailableDefaultCategories().filter { $0 != .custom }, id: \.self) { category in
                LargeScreenRailRow(
                    title: category.rawValue,
                    icon: category.icon,
                    iconTint: Color.forCategory(category.color),
                    isSelected: filterCategory == category
                ) {
                    applyRailChange {
                        filterCategory = (filterCategory == category) ? nil : category
                        filterCustomCategoryId = nil
                    }
                }
            }

            ForEach(categoryViewModel.customCategories) { custom in
                LargeScreenRailRow(
                    title: custom.name,
                    icon: custom.icon,
                    iconTint: Color.forCategory(custom.colorName),
                    isSelected: filterCategory == .custom && filterCustomCategoryId == custom.id
                ) {
                    applyRailChange {
                        if filterCategory == .custom && filterCustomCategoryId == custom.id {
                            filterCategory = nil
                            filterCustomCategoryId = nil
                        } else {
                            filterCategory = .custom
                            filterCustomCategoryId = custom.id
                        }
                    }
                }
            }
        }
    }

    /// Same matrix as the chip: hidden with no tags anywhere; Pro users
    /// pick a tag inline; free users get the paywall entry point.
    @ViewBuilder
    private var railTagsGroup: some View {
        let stats = viewModel.tagStats
        let orderedTags = stats.popularTags

        if !orderedTags.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                LargeScreenRailHeader(title: "Tags")

                if proManager.isPro {
                    ForEach(orderedTags, id: \.self) { tag in
                        LargeScreenRailRow(
                            title: "#\(tag)",
                            icon: "number",
                            isSelected: filterTag == tag,
                            action: {
                                applyRailChange {
                                    filterTag = (filterTag == tag) ? nil : tag
                                }
                            },
                            trailing: {
                                if let count = stats.usageCounts[tag] {
                                    Text("\(count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                            }
                        )
                    }
                } else {
                    LargeScreenRailRow(
                        title: "Filter by tag",
                        icon: "sparkles",
                        iconTint: .appPrimary,
                        isSelected: false,
                        action: {
                            HapticManager.shared.lightTap()
                            showingTagPaywall = true
                        },
                        trailing: {
                            Text("PRO")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(0.5)
                                .foregroundColor(.appPrimary)
                        }
                    )
                }
            }
        }
    }

    private var railSortGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            LargeScreenRailHeader(title: "Sort")

            ForEach(SortOption.allCases, id: \.self) { option in
                LargeScreenRailRow(
                    title: option.rawValue,
                    icon: option.icon,
                    isSelected: sortOption == option
                ) {
                    guard sortOption != option else { return }
                    HapticManager.shared.selectionChanged()
                    // Same as the sort menu: no implicit animation, so
                    // the list swaps grouping without interpolating.
                    var txn = Transaction()
                    txn.disablesAnimations = true
                    withTransaction(txn) {
                        sortOption = option
                        scrollToTop = true
                    }
                }
            }
        }
    }

    private var railDateRangeGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            LargeScreenRailHeader(title: "Date range")

            LargeScreenRailRow(
                title: useDateRangeFilter ? dateRangeLabel : "Any dates",
                icon: useDateRangeFilter ? "calendar.badge.checkmark" : "calendar",
                isSelected: useDateRangeFilter,
                action: {
                    HapticManager.shared.lightTap()
                    showingDateRangePicker = true
                },
                trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            )

            if useDateRangeFilter {
                LargeScreenRailRow(
                    title: "Clear date range",
                    icon: "xmark.circle",
                    isSelected: false
                ) {
                    applyRailChange { useDateRangeFilter = false }
                }
            }
        }
    }
}
