import SwiftUI

/// Month-grid calendar for browsing expenses by day.
///
/// Complements the existing `SpendingHeatmap` which shows *intensity* — the
/// calendar is a *browsing* surface: tap a day to see its expenses, edit them,
/// or jump back to the editor. The view never mutates Core Data directly;
/// edits and deletes round-trip through `ExpenseViewModel` exactly the way
/// `AllExpensesView` does, so the two surfaces stay perfectly consistent.
///
/// Performance: the per-day aggregation runs on a `Task.detached` whenever
/// the visible month changes, so swiping between months never blocks the
/// main thread even with thousands of expenses. We dedupe and cache the
/// month payload so re-rendering the grid is just a dictionary lookup.
struct ExpenseCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    @State private var visibleMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: Date? = nil
    @State private var monthAggregate: MonthAggregate = .empty
    @State private var aggregationTask: Task<Void, Never>? = nil
    @State private var editingExpense: Expense? = nil
    @State private var animateGridIn = false

    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = Calendar.current.firstWeekday
        return c
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return f
    }()

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.lg) {
                        monthNavRow
                        weekdayHeader
                        monthGrid
                            .opacity(animateGridIn ? 1 : 0)
                            .animation(Theme.Motion.snappy, value: animateGridIn)

                        monthSummaryStrip

                        if let day = selectedDay {
                            dayDetailSection(for: day)
                                .transition(
                                    .move(edge: .bottom)
                                    .combined(with: .opacity)
                                )
                        } else {
                            calendarHintCard
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.xxxl)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close calendar")
                }

                if selectedDay != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            HapticManager.shared.lightTap()
                            withAnimation(Theme.Motion.snappy) { selectedDay = nil }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Month")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.appPrimary)
                        }
                    }
                }
            }
        }
        .onAppear {
            recompute()
            withAnimation(Theme.Motion.emphasized.delay(0.05)) {
                animateGridIn = true
            }
        }
        .onChange(of: visibleMonth) { _, _ in recompute() }
        .onReceive(viewModel.$expenses) { _ in recompute() }
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

    // MARK: - Month Nav

    private var monthNavRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.appPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.appPrimary.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                HapticManager.shared.lightTap()
                withAnimation(Theme.Motion.snappy) {
                    visibleMonth = calendar.startOfMonth(for: Date())
                    selectedDay = nil
                }
            } label: {
                VStack(spacing: 2) {
                    Text(Self.monthFormatter.string(from: visibleMonth))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                    if !calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month) {
                        Text("Tap to return to today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Self.monthFormatter.string(from: visibleMonth)). Tap to jump to current month")

            Spacer(minLength: 0)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(canMoveForward ? .appPrimary : .secondary.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(canMoveForward
                                      ? Color.appPrimary.opacity(0.1)
                                      : Color(.systemGray6))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canMoveForward)
        }
        .padding(.horizontal, Theme.Spacing.sm)
    }

    private var canMoveForward: Bool {
        let nowMonth = calendar.startOfMonth(for: Date())
        return visibleMonth < nowMonth
    }

    private func shiftMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        if offset > 0 {
            // Never allow stepping past the current month.
            let nowMonth = calendar.startOfMonth(for: Date())
            if next > nowMonth { return }
        }
        HapticManager.shared.selectionChanged()
        withAnimation(Theme.Motion.snappy) {
            visibleMonth = next
            selectedDay = nil
        }
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        let symbols = orderedWeekdaySymbols()
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols // ["S","M","T","W","T","F","S"]
        let firstIdx = calendar.firstWeekday - 1 // 1-indexed -> 0-indexed
        guard firstIdx >= 0, firstIdx < symbols.count else { return symbols }
        return Array(symbols[firstIdx...] + symbols[..<firstIdx])
    }

    // MARK: - Grid

    private var monthGrid: some View {
        let cells = monthCells()
        let columns: [GridItem] = Array(
            repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs),
            count: 7
        )
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(cells.indices, id: \.self) { idx in
                let cell = cells[idx]
                if let date = cell {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 56)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .cardSurface()
    }

    /// Builds an array of optional dates representing the month grid layout
    /// (with `nil` for leading / trailing padding cells). Always returns a
    /// multiple of 7.
    private func monthCells() -> [Date?] {
        let first = calendar.startOfMonth(for: visibleMonth)
        let weekdayOfFirst = calendar.component(.weekday, from: first) // 1 = Sunday
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let range = calendar.range(of: .day, in: .month, for: first) ?? 1..<31
        let dayCount = range.count

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: offset, to: first) {
                cells.append(date)
            }
        }
        // Pad to a clean multiple of 7 so the grid doesn't shift height
        // between months (some months span 5 weeks, some 6).
        while cells.count % 7 != 0 { cells.append(nil) }
        if cells.count < 42 { // always show 6 rows for stable layout
            while cells.count < 42 { cells.append(nil) }
        }
        return cells
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let key = calendar.startOfDay(for: date)
        let snapshot = monthAggregate.byDay[key]
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        Button {
            guard !isFuture else { return }
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                if isSelected {
                    selectedDay = nil
                } else {
                    selectedDay = key
                }
            }
        } label: {
            VStack(spacing: 3) {
                Text(dayNumber(for: date))
                    .font(.system(size: 14, weight: isToday ? .bold : .semibold, design: .rounded))
                    .foregroundColor(dayNumberColor(isFuture: isFuture, isSelected: isSelected, isToday: isToday))

                dotRow(for: snapshot)

                if let amount = snapshot?.netTotal, amount > 0 {
                    Text(compactAmount(amount))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(amountColor(isSelected: isSelected))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(" ")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip - 2, style: .continuous)
                    .fill(cellBackground(isSelected: isSelected, isToday: isToday))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip - 2, style: .continuous)
                    .stroke(cellStroke(isSelected: isSelected, isToday: isToday),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .opacity(isFuture ? 0.35 : 1.0)
            .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityLabel(for: date, snapshot: snapshot))
    }

    private func dayNumber(for date: Date) -> String {
        let comp = calendar.component(.day, from: date)
        return "\(comp)"
    }

    private func dayNumberColor(isFuture: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .appPrimary }
        return .primary
    }

    private func amountColor(isSelected: Bool) -> Color {
        isSelected ? .white.opacity(0.95) : .secondary
    }

    private func cellBackground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .appPrimary }
        if isToday { return Color.appPrimary.opacity(0.12) }
        return Color(.tertiarySystemBackground)
    }

    private func cellStroke(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return Color.appPrimary }
        if isToday { return Color.appPrimary.opacity(0.5) }
        return Color.primary.opacity(0.05)
    }

    @ViewBuilder
    private func dotRow(for snapshot: DayAggregate?) -> some View {
        if let snap = snapshot, !snap.dotColors.isEmpty {
            HStack(spacing: 3) {
                ForEach(0..<snap.dotColors.count, id: \.self) { i in
                    Circle()
                        .fill(snap.dotColors[i])
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        } else {
            Color.clear.frame(height: 6)
        }
    }

    /// Compact dollar formatting for a tiny calendar cell. Locale-aware via
    /// the view model's currency symbol; avoids decimals to keep the cell
    /// uncluttered.
    private func compactAmount(_ value: Double) -> String {
        let symbol = viewModel.selectedCurrency.symbol
        let abs = Swift.abs(value)
        if abs >= 1_000_000 {
            return "\(symbol)\(String(format: "%.1f", abs / 1_000_000))M"
        }
        if abs >= 1_000 {
            return "\(symbol)\(String(format: "%.1f", abs / 1_000))k"
        }
        return "\(symbol)\(Int(abs.rounded()))"
    }

    private func accessibilityLabel(for date: Date, snapshot: DayAggregate?) -> String {
        let dayString = Self.dayFormatter.string(from: date)
        guard let snap = snapshot, snap.netTotal > 0 else {
            return "\(dayString), no expenses"
        }
        let amount = viewModel.formattedAmount(snap.netTotal)
        return "\(dayString), \(snap.transactionCount) transaction\(snap.transactionCount == 1 ? "" : "s"), total \(amount)"
    }

    // MARK: - Month summary strip

    private var monthSummaryStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            summaryPill(
                icon: "creditcard.fill",
                value: viewModel.formattedAmount(monthAggregate.netTotal),
                label: "Spent"
            )
            summaryPill(
                icon: "chart.bar.fill",
                value: "\(monthAggregate.transactionCount)",
                label: "Entries"
            )
            summaryPill(
                icon: "calendar",
                value: "\(monthAggregate.activeDays)",
                label: "Active"
            )
        }
    }

    private func summaryPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.appPrimary)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .padding(.horizontal, Theme.Spacing.sm)
        .cardSurface()
    }

    // MARK: - Day detail

    private var calendarHintCard: some View {
        VStack(spacing: Theme.Spacing.xs + 2) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.appPrimary.opacity(0.7))
            Text("Pick a day to view its expenses")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text("Dots show category mix · amount shows net spend")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.lg)
        .cardSurface(fill: Color.appPrimary.opacity(0.06))
    }

    private func dayDetailSection(for day: Date) -> some View {
        let entries = viewModel.expenses
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
        let net = entries.netTotal()

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dayFormatter.string(from: day))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies") · net \(viewModel.formattedAmount(net))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            if entries.isEmpty {
                emptyDayState
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(entries) { expense in
                        Button {
                            HapticManager.shared.lightTap()
                            editingExpense = expense
                        } label: {
                            // PERF: `.equatable()` lets SwiftUI skip
                            // rebuilding the card subtree when only an
                            // unrelated piece of state changes — matches
                            // the pattern already used in `HomeView` and
                            // `AllExpensesView`.
                            ExpenseCard(
                                expense: expense,
                                viewModel: viewModel,
                                categoryViewModel: categoryViewModel
                            )
                            .equatable()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var emptyDayState: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
            Text("No expenses logged")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            Spacer(minLength: 0)
            Text("No-spend day")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.green)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.15)))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .cardSurface()
    }

    // MARK: - Aggregation

    /// Per-day aggregation that backs the calendar cells. Captures only what
    /// the view needs: the resolved dot colors (already category-mapped),
    /// the net total, and the transaction count.
    private struct DayAggregate {
        let netTotal: Double
        let transactionCount: Int
        let dotColors: [Color]
    }

    private struct MonthAggregate {
        let monthStart: Date
        let byDay: [Date: DayAggregate]
        let netTotal: Double
        let transactionCount: Int
        let activeDays: Int

        static let empty = MonthAggregate(
            monthStart: .distantPast,
            byDay: [:],
            netTotal: 0,
            transactionCount: 0,
            activeDays: 0
        )
    }

    private func recompute() {
        aggregationTask?.cancel()
        let monthStart = visibleMonth
        let calendar = self.calendar
        let expenses = viewModel.expenses
        // Snapshot the custom-category map so the detached task doesn't touch
        // an `@MainActor` property mid-flight.
        let customColors: [UUID: String] = Dictionary(
            uniqueKeysWithValues: categoryViewModel.customCategories.map { ($0.id, $0.colorName) }
        )

        aggregationTask = Task.detached(priority: .userInitiated) { [calendar] in
            guard !Task.isCancelled else { return }
            guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }

            // Bucket expenses by start-of-day; only consider this month.
            var amountsByDay: [Date: Double] = [:]
            var countsByDay: [Date: Int] = [:]
            // Per-day per-category amount → used to pick the "top 3"
            // categories for the dot row.
            var perDayCatTotals: [Date: [String: Double]] = [:]

            for expense in expenses {
                guard expense.date >= monthStart, expense.date < monthEnd else { continue }
                guard expense.amount.isFinite else { continue }
                let day = calendar.startOfDay(for: expense.date)
                let signed = expense.signedAmount
                amountsByDay[day, default: 0] += signed
                countsByDay[day, default: 0] += 1

                let key: String = {
                    if expense.category == .custom, let id = expense.customCategoryId {
                        return "custom:\(id.uuidString)"
                    }
                    return "default:\(expense.category.rawValue)"
                }()
                perDayCatTotals[day, default: [:]][key, default: 0] += Swift.abs(signed)
            }

            var byDay: [Date: DayAggregate] = [:]
            for (day, total) in amountsByDay {
                let count = countsByDay[day] ?? 0
                let topKeys = (perDayCatTotals[day] ?? [:])
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                let dotColors: [Color] = topKeys.map { key in
                    Self.colorForKey(key, customColors: customColors)
                }
                byDay[day] = DayAggregate(
                    netTotal: total,
                    transactionCount: count,
                    dotColors: dotColors
                )
            }

            let net = amountsByDay.values.reduce(0, +)
            let count = countsByDay.values.reduce(0, +)
            let active = amountsByDay.keys.count

            let aggregate = MonthAggregate(
                monthStart: monthStart,
                byDay: byDay,
                netTotal: net,
                transactionCount: count,
                activeDays: active
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.monthAggregate = aggregate
            }
        }
    }

    /// Resolves a per-expense category key (default-or-custom) into the
    /// concrete dot color. Static so the detached task can call it without
    /// touching MainActor state.
    private static func colorForKey(_ key: String, customColors: [UUID: String]) -> Color {
        if key.hasPrefix("custom:") {
            let suffix = String(key.dropFirst("custom:".count))
            if let id = UUID(uuidString: suffix), let name = customColors[id] {
                return Color.forCategory(name)
            }
            return .appPrimary
        }
        if key.hasPrefix("default:") {
            let suffix = String(key.dropFirst("default:".count))
            if let cat = Expense.Category(rawValue: suffix) {
                return Color.forCategory(cat.color)
            }
        }
        return .appPrimary
    }
}

// MARK: - Calendar helpers

private extension Calendar {
    /// Returns the first instant of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
