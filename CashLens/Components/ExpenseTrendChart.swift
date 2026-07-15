import SwiftUI
import Charts

/// The Insights "Over time" trend line.
///
/// v2 Swift Charts migration: this used to be ~350 lines of
/// GeometryReader + Path with hand-placed dots and density-managed
/// static tooltips. The `Chart` version preserves the visual style
/// (category-tinted 3pt line, 15%-opacity area fill, hairline grid,
/// per-timeframe x labels) and gains what the hand-rolled version
/// couldn't do:
///   • scrubbing — drag anywhere for a lollipop cursor with the exact
///     bucket amount (replaces the static tooltip clutter)
///   • a dashed average `RuleMark`
///   • animated interpolation when the timeframe/filter changes
///   • audio-graph / VoiceOver chart descriptions for free
///
/// The data pipeline is unchanged: `chartDates`/`chartValues` are
/// pre-bucketed off-main in `recomputeStatsNow` (Swift Charts renders
/// on the main thread, so keeping aggregation out of it still
/// matters).
struct ExpenseTrendChart: View {
    /// Pre-bucketed dates (one per chart x-tick).
    let chartDates: [Date]
    /// Pre-bucketed values aligned to `chartDates`.
    let chartValues: [Double]
    let timeFrame: ExpenseViewModel.TimeFrame
    let categoryColor: Color
    @EnvironmentObject var viewModel: ExpenseViewModel

    /// Raw scrub position from `chartXSelection`; snapped to the
    /// nearest bucket in `selectedPoint`.
    @State private var rawSelectedDate: Date? = nil

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var hasData: Bool {
        chartValues.contains { $0 > 0 }
    }

    private var average: Double {
        let nonZero = chartValues.filter { $0 > 0 }
        return nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
    }

    /// The bucket nearest to the scrub position, or `nil` when idle.
    private var selectedPoint: (date: Date, value: Double)? {
        guard let raw = rawSelectedDate, !chartDates.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        for (i, d) in chartDates.enumerated() {
            let distance = abs(d.timeIntervalSince(raw))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }
        return (chartDates[bestIndex], chartValues[bestIndex])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasData {
                chart
                    .frame(height: isIPad ? 300 : 200)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(Array(zip(chartDates, chartValues).enumerated()), id: \.offset) { _, point in
                // Area fill first so the line renders on top of it.
                AreaMark(
                    x: .value("Date", point.0),
                    y: .value("Spent", point.1)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(categoryColor.opacity(0.15))

                LineMark(
                    x: .value("Date", point.0),
                    y: .value("Spent", point.1)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(categoryColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // Dashed average line — quieter than the data line so it
            // reads as context, not another series.
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(formatCurrency(average))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
            }

            // Scrub lollipop: hairline cursor + highlighted dot +
            // amount/date callout pinned to the top of the plot.
            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        VStack(spacing: 1) {
                            Text(formatCurrency(selected.value))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            Text(formatDate(selected.date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.systemBackground)
                                .shadow(color: Theme.Shadow.elevatedColor, radius: 4, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(categoryColor.opacity(0.35), lineWidth: Theme.Stroke.thin)
                        )
                    }

                PointMark(
                    x: .value("Selected", selected.date),
                    y: .value("Spent", selected.value)
                )
                .symbolSize(90)
                .foregroundStyle(categoryColor)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: isIPad ? 10 : 6)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(formatDate(date))
                            .font(isIPad ? .caption : .caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            // Hairline grid only — mirrors the old hand-drawn dividers;
            // exact values live in the scrub lollipop, so y labels
            // would just add noise at this card size.
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.2))
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .onChange(of: selectedPoint?.date) { old, new in
            if old != nil, new != nil, old != new {
                HapticManager.shared.selectionChanged()
            }
        }
        .animation(Theme.Motion.emphasized, value: chartValues)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: isIPad ? 20 : 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: isIPad ? 44 : 32, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            VStack(spacing: isIPad ? 8 : 4) {
                Text("No trend data yet")
                    .font(isIPad ? .title3.weight(.semibold) : Theme.Typography.rowTitle)
                    .foregroundColor(.primary)

                Text("Add more expenses to see your spending trends.")
                    .font(isIPad ? .subheadline : .footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isIPad ? 24 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isIPad ? 300 : 200)
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(16)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        switch timeFrame {
        case .day:          return Self.hourFormatter.string(from: date)
        case .week, .month: return Self.dayMonthFormatter.string(from: date)
        case .year, .all:   return Self.monthFormatter.string(from: date)
        }
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f
    }()
    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    /// Shared cached formatter — allocating a NumberFormatter per call
    /// was measurable on the axis-label hot path. The currency symbol
    /// is user-changeable, so it's (re)applied per call; that's a cheap
    /// property write, unlike the allocation.
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0 // No decimals — better readability in small space
        return formatter
    }()

    private func formatCurrency(_ value: Double) -> String {
        let formatter = Self.currencyFormatter
        formatter.currencySymbol = viewModel.currencySymbol
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Pre-aggregation helper
//
// Static helper that does the bucket math the view body used to do per
// redraw. `nonisolated` so the StatisticsView recompute can call it from
// `Task.detached` and hand the result into the new pre-built initializer.

extension ExpenseTrendChart {
    /// Convenience initializer that pre-builds the chart series eagerly.
    /// Use this in previews and any path where the caller doesn't have
    /// pre-aggregated data — production paths in StatisticsView should
    /// compute the series off-main and use the primary initializer.
    init(
        expenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        categoryColor: Color
    ) {
        let series = ExpenseTrendChart.buildChartData(
            expenses: expenses,
            timeFrame: timeFrame,
            referenceDate: Date()
        )
        self.init(
            chartDates: series.dates,
            chartValues: series.values,
            timeFrame: timeFrame,
            categoryColor: categoryColor
        )
    }

    /// Pure value-type bucket-builder. Safe to call from any context — the
    /// audit flagged the old body-side computation as P1 because it ran
    /// every time the parent invalidated. Now `recomputeStatsNow` calls
    /// this once per recompute on the background task.
    nonisolated static func buildChartData(
        expenses: [Expense],
        timeFrame: ExpenseViewModel.TimeFrame,
        referenceDate: Date
    ) -> (dates: [Date], values: [Double]) {
        let calendar = Calendar.current
        let now = referenceDate

        // Single-pass bucket aggregation.
        var groupedAmounts: [String: Double] = [:]
        for expense in expenses {
            let key = bucketKey(for: expense.date, timeFrame: timeFrame, calendar: calendar)
            groupedAmounts[key, default: 0] += expense.signedAmount
        }

        var dates: [Date] = []
        switch timeFrame {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            for hour in 0..<24 {
                if let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
                    dates.append(date)
                }
            }
        case .week:
            for day in (0..<7).reversed() {
                if let date = calendar.date(byAdding: .day, value: -day, to: now) {
                    dates.append(calendar.startOfDay(for: date))
                }
            }
        case .month:
            if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
               let range = calendar.range(of: .day, in: .month, for: now) {
                for day in 1...range.count {
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                        dates.append(date)
                    }
                }
            }
        case .year:
            if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                for month in 0..<12 {
                    if let date = calendar.date(byAdding: .month, value: month, to: startOfYear) {
                        dates.append(date)
                    }
                }
            }
        case .all:
            if let oldestExpense = expenses.min(by: { $0.date < $1.date })?.date {
                var current = calendar.date(from: calendar.dateComponents([.year, .month], from: oldestExpense)) ?? calendar.startOfDay(for: oldestExpense)
                let endDate = calendar.startOfDay(for: now)

                while current <= endDate {
                    dates.append(current)
                    if let nextMonth = calendar.date(byAdding: .month, value: 1, to: current) {
                        current = nextMonth
                    } else {
                        break
                    }
                }
            }
        }

        let values = dates.map { date -> Double in
            let key = bucketKey(for: date, timeFrame: timeFrame, calendar: calendar)
            return groupedAmounts[key, default: 0]
        }
        return (dates, values)
    }

    /// Generate a unique bucket key for grouping expenses.
    nonisolated private static func bucketKey(
        for date: Date,
        timeFrame: ExpenseViewModel.TimeFrame,
        calendar: Calendar
    ) -> String {
        switch timeFrame {
        case .day:
            let day = calendar.component(.day, from: date)
            let hour = calendar.component(.hour, from: date)
            return "\(day)-\(hour)"
        case .week, .month:
            let year = calendar.component(.year, from: date)
            let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
            return "\(year)-\(day)"
        case .year, .all:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return "\(year)-\(month)"
        }
    }
}

struct ExpenseTrendChart_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ExpenseTrendChart(
                expenses: Expense.sampleData,
                timeFrame: .month,
                categoryColor: .appPrimary
            )
            .padding()
            .background(Color.systemBackground)
            .cornerRadius(16)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .previewLayout(.sizeThatFits)
    }
} 