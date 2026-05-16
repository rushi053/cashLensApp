import SwiftUI
import Charts

/// Compact line chart that visualises a `ForecastEngine.Forecast`:
///
///   • Solid line   — actual daily totals (history).
///   • Dashed line  — projected daily totals (horizon).
///   • Soft band    — ±1σ confidence band on the projection.
///   • Vertical "today" marker  — separates history from projection.
///   • Yellow dots  — days where a known subscription cashflow lands.
///
/// The chart is render-only; it expects pre-computed points so we never block
/// the main thread.
struct ForecastChart: View {
    let forecast: ForecastEngine.Forecast
    let accent: Color
    let formattedAmount: (Double) -> String

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var historicalPoints: [ForecastEngine.DayPoint] {
        forecast.points.filter { $0.actual != nil }
    }

    private var projectedPoints: [ForecastEngine.DayPoint] {
        forecast.points.filter { $0.actual == nil }
    }

    /// Subscription cashflow markers — only future days that have a sub charge.
    private var subscriptionMarkers: [ForecastEngine.DayPoint] {
        projectedPoints.filter { $0.subscriptionAmount > 0 }
    }

    /// Bridge point so the dashed projection line connects visually to the
    /// last actual point with no gap at "today".
    private var bridgePoint: ForecastEngine.DayPoint? {
        guard let last = historicalPoints.last else { return nil }
        return ForecastEngine.DayPoint(
            date: last.date,
            actual: nil,
            projected: last.actual ?? 0,
            confidenceLow: last.actual ?? 0,
            confidenceHigh: last.actual ?? 0,
            subscriptionAmount: 0
        )
    }

    private var projectedSeries: [ForecastEngine.DayPoint] {
        if let bridge = bridgePoint {
            return [bridge] + projectedPoints
        }
        return projectedPoints
    }

    var body: some View {
        Chart {
            // Confidence band — drawn first so the lines sit on top.
            ForEach(projectedPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Low", point.confidenceLow),
                    yEnd: .value("High", point.confidenceHigh)
                )
                .foregroundStyle(accent.opacity(0.12))
                .interpolationMethod(.monotone)
            }

            // Historical actual line (solid).
            ForEach(historicalPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", point.actual ?? 0),
                    series: .value("Series", "Actual")
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            // Projected line (dashed).
            ForEach(projectedSeries) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", point.projected),
                    series: .value("Series", "Projected")
                )
                .foregroundStyle(accent.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                .interpolationMethod(.monotone)
            }

            // "Today" vertical marker.
            RuleMark(x: .value("Today", today))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    Text("Today")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondarySystemBackground)
                        )
                }

            // Subscription cashflow dots.
            ForEach(subscriptionMarkers) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", point.projected)
                )
                .foregroundStyle(.yellow)
                .symbolSize(40)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.12))
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
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortDateLabel(date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 200)
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

    private func shortDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
