import SwiftUI
import Charts

/// Grouped bar chart comparing this-year's monthly totals with the same months last year.
///
/// Designed to live inside the Statistics "Pro Insights" section. Accepts pre-computed
/// `AdvancedStatsCalculator.YearOverYearPoint`s so rendering stays cheap.
struct YearOverYearChart: View {
    let points: [AdvancedStatsCalculator.YearOverYearPoint]
    let accent: Color
    let formattedAmount: (Double) -> String

    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }

    private var yearFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }

    private var currentYearLabel: String {
        guard let first = points.first?.monthAnchor else { return "This Year" }
        return yearFormatter.string(from: first)
    }

    private var previousYearLabel: String {
        guard let first = points.first?.monthAnchor,
              let prev = Calendar.current.date(byAdding: .year, value: -1, to: first) else { return "Last Year" }
        return yearFormatter.string(from: prev)
    }

    private struct Bar: Identifiable {
        let id = UUID()
        let monthLabel: String
        let series: String
        let amount: Double
    }

    private var bars: [Bar] {
        points.flatMap { point -> [Bar] in
            let label = monthFormatter.string(from: point.monthAnchor)
            return [
                Bar(monthLabel: label, series: previousYearLabel, amount: point.previousAmount),
                Bar(monthLabel: label, series: currentYearLabel, amount: point.currentAmount),
            ]
        }
    }

    private var yearTotals: (current: Double, previous: Double) {
        let current = points.reduce(0) { $0 + $1.currentAmount }
        let previous = points.reduce(0) { $0 + $1.previousAmount }
        return (current, previous)
    }

    private var deltaText: String? {
        let totals = yearTotals
        guard totals.previous > 0 else { return nil }
        let change = ((totals.current - totals.previous) / totals.previous) * 100
        let arrow = change >= 0 ? "↑" : "↓"
        return "\(arrow) \(String(format: "%.1f", abs(change)))% vs \(previousYearLabel)"
    }

    private var deltaIsIncrease: Bool {
        yearTotals.current >= yearTotals.previous
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            headerRow

            Chart(bars) { bar in
                BarMark(
                    x: .value("Month", bar.monthLabel),
                    y: .value("Amount", bar.amount)
                )
                .foregroundStyle(by: .value("Series", bar.series))
                .position(by: .value("Series", bar.series))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale([
                previousYearLabel: Color.secondary.opacity(0.35),
                currentYearLabel: accent
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: Theme.Spacing.md)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactAmount(amount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 200)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentYearLabel + " · " + formattedAmount(yearTotals.current))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(previousYearLabel + " · " + formattedAmount(yearTotals.previous))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let delta = deltaText {
                Text(delta)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(deltaIsIncrease ? .red : .green)
                    .padding(.horizontal, Theme.Spacing.sm + 2)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .background(
                        Capsule()
                            .fill((deltaIsIncrease ? Color.red : Color.green).opacity(0.12))
                    )
            }
        }
    }

    private func compactAmount(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if abs >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}
