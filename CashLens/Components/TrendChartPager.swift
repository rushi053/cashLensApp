import SwiftUI
import Charts

// MARK: - Data structures

/// Average spend on a given weekday, plus a flag marking whether it is the highest
/// weekday in the current view so the bar chart can emphasise it.
struct WeekdayAveragePoint: Identifiable, Hashable {
    /// Calendar weekday number (1 = Sunday … 7 = Saturday).
    let weekday: Int
    /// Mean spend across every occurrence of this weekday inside the current range.
    let average: Double
    /// Total spend for this weekday in the range (shown as the caption).
    let total: Double
    /// Number of expenses falling on this weekday.
    let count: Int
    /// Whether this weekday has the highest `average` among all non-zero weekdays.
    var isHighest: Bool

    var id: Int { weekday }

    /// Short 3-letter label ("Mon", "Tue", …) using the current locale.
    var shortName: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        // `weekday` is 1-indexed (1 = Sunday), `shortWeekdaySymbols` is 0-indexed.
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }
}

/// A single "top spending day" — one calendar day's aggregate total.
struct TopDayPoint: Identifiable, Hashable {
    let date: Date
    let amount: Double
    let count: Int

    var id: Date { date }
}

// MARK: - Pager

/// Three-page swipeable Trend card. Each page answers a different question about the
/// same filtered set:
///
///   1. **Over time** — how is spending moving day to day?
///   2. **By weekday** — which weekday costs the most on average?
///   3. **Top days** — which specific days blew the budget?
///
/// The pager owns its own `selection` state so the Statistics view stays clean.
struct TrendChartPager: View {
    /// Pre-bucketed dates for the "Over time" line chart. Built off-main on
    /// the StatisticsView background recompute task so the pager body stays
    /// declarative — no ExpenseFilter / O(N) work touches the main thread.
    let trendDates: [Date]
    /// Pre-bucketed values aligned to `trendDates`.
    let trendValues: [Double]
    let timeFrame: ExpenseViewModel.TimeFrame
    let accent: Color
    let weekdayPoints: [WeekdayAveragePoint]
    let topDays: [TopDayPoint]
    let formattedAmount: (Double) -> String

    @State private var selection: Int = 0
    @EnvironmentObject var viewModel: ExpenseViewModel

    private let pageTitles = ["Over time", "By weekday", "Top days"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            pageTabBar

            TabView(selection: $selection) {
                overTimePage.tag(0)
                weekdayPage.tag(1)
                topDaysPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 280)
            .animation(Theme.Motion.snappy, value: selection)

            pageIndicator
        }
    }

    // MARK: Page tab bar

    /// Segmented pill row above the swipe area. Tapping a tab animates to that page
    /// and the underline pill slides via `matchedGeometryEffect` for a premium feel.
    private var pageTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<pageTitles.count, id: \.self) { index in
                pageTab(index: index)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.tertiarySystemBackground)
        )
    }

    @Namespace private var tabNamespace

    private func pageTab(index: Int) -> some View {
        let isSelected = selection == index
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = index
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.systemBackground)
                        .matchedGeometryEffect(id: "tabSelection", in: tabNamespace)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                }

                Text(pageTitles[index])
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: Page indicator (dots)

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageTitles.count, id: \.self) { index in
                Capsule()
                    .fill(selection == index ? accent : Color.secondary.opacity(0.25))
                    .frame(width: selection == index ? 16 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
            }
            Spacer()
            Text(swipeHint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(0.7)
        }
    }

    private var swipeHint: String {
        "Swipe to compare"
    }

    // MARK: Page 1 — Over time

    private var overTimePage: some View {
        ExpenseTrendChart(
            chartDates: trendDates,
            chartValues: trendValues,
            timeFrame: timeFrame,
            categoryColor: accent
        )
        .environmentObject(viewModel)
    }

    // MARK: Page 2 — By weekday

    private var weekdayPage: some View {
        let hasData = weekdayPoints.contains(where: { $0.average > 0 })
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Average spend per weekday")
                .font(.caption)
                .foregroundColor(.secondary)

            if hasData {
                Chart(weekdayPoints) { point in
                    BarMark(
                        x: .value("Weekday", point.shortName),
                        y: .value("Average", point.average)
                    )
                    .foregroundStyle(point.isHighest ? accent : accent.opacity(0.45))
                    .cornerRadius(6)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        if point.isHighest, point.average > 0 {
                            Text(formattedAmount(point.average))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(accent)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let double = value.as(Double.self), double > 0 {
                                Text(formattedAmount(double))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                if let busiest = weekdayPoints.first(where: { $0.isHighest && $0.average > 0 }) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(accent)
                        Text("Busiest on \(fullWeekdayName(busiest.weekday))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(busiest.count) \(busiest.count == 1 ? "expense" : "expenses")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                emptyPage(icon: "calendar", label: "Not enough data to break down by weekday.")
            }
        }
        .padding(.horizontal, 2)
    }

    private func fullWeekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }

    // MARK: Page 3 — Top days

    private var topDaysPage: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Biggest spending days")
                .font(.caption)
                .foregroundColor(.secondary)

            if topDays.isEmpty {
                emptyPage(icon: "flame", label: "No expenses in this period yet.")
            } else {
                let maxAmount = topDays.first?.amount ?? 1
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(topDays.prefix(5).enumerated()), id: \.element.id) { index, day in
                        topDayRow(day, rank: index + 1, maxAmount: maxAmount)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func topDayRow(_ day: TopDayPoint, rank: Int, maxAmount: Double) -> some View {
        let fraction = maxAmount > 0 ? CGFloat(day.amount / maxAmount) : 0
        return HStack(spacing: Theme.Spacing.md) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedDate(day.date))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(formattedAmount(day.amount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.tertiarySystemBackground)
                            .frame(height: 5)

                        Capsule()
                            .fill(accent)
                            .frame(width: max(6, proxy.size.width * fraction), height: 5)
                            .animation(.easeOut(duration: 0.35), value: fraction)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    /// Hoisted formatters — the per-row Top Days list called this on every
    /// render, allocating a fresh `DateFormatter` each call. Both formats
    /// are static and locale-stable, so reusing one instance per format is
    /// safe (we only touch them from the main actor in `body`).
    private static let formatterCurrentYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
    private static let formatterOtherYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let currentYear = calendar.component(.year, from: Date())
        let dateYear = calendar.component(.year, from: date)
        let formatter = currentYear == dateYear
            ? Self.formatterCurrentYear
            : Self.formatterOtherYear
        return formatter.string(from: date)
    }

    // MARK: Empty state (reused by pages 2 and 3)

    private func emptyPage(icon: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(.secondary.opacity(0.5))
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }
}
