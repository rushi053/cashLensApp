import SwiftUI

struct SpendingHeatmap: View {
    struct DayCell: Identifiable {
        let id: String
        let date: Date
        let amount: Double
        let intensity: Double
    }

    /// Pre-aggregated day → net total map (refund-aware, floored at 0). The
    /// caller is expected to do this aggregation **once** (typically on the
    /// background recompute task in StatisticsView) so the heatmap doesn't
    /// re-walk the full expense array on every body redraw — the audit
    /// flagged the prior `expenses: [Expense]` shape as a P0 hot path.
    let dailyTotals: [Date: Double]
    let startDate: Date
    let endDate: Date
    let accentColor: Color
    let formattedAmount: (Double) -> String

    /// Safety cap so extremely large ranges (e.g. "All Time" = distantPast) don't freeze the UI.
    /// Shows the *most recent* `maxDaysToRender` days of the selected range.
    let maxDaysToRender: Int = 365
    
    @State private var selectedCell: DayCell?

    /// Day cell edge. Scales with Dynamic Type (against `.caption2`,
    /// the weekday label style) so the grid and its labels stay aligned
    /// and the 18pt tap target isn't frozen at Large text on an AX size.
    @ScaledMetric(relativeTo: .caption2) private var cellSize: CGFloat = 18
    
    private var calendar: Calendar { .current }
    
    private static let isoDayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
    
    private var renderRange: (start: Date, end: Date) {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return (start, end) }
        guard maxDaysToRender > 0 else { return (start, end) }
        
        let diffDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let totalInclusiveDays = diffDays + 1
        if totalInclusiveDays <= maxDaysToRender {
            return (start, end)
        }
        
        let renderStart = calendar.date(byAdding: .day, value: -(maxDaysToRender - 1), to: end) ?? end
        return (calendar.startOfDay(for: renderStart), end)
    }
    
    private var isCapped: Bool {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return false }
        let diffDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let totalInclusiveDays = diffDays + 1
        return maxDaysToRender > 0 && totalInclusiveDays > maxDaysToRender
    }
    
    private var days: [DayCell] {
        let start = renderRange.start
        let end = renderRange.end
        guard start <= end else { return [] }

        // No O(N) grouping pass here anymore — the caller hands us the
        // already-aggregated map. We only walk the calendar-day range,
        // which is bounded by `maxDaysToRender`.
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
        }

        let values = dates.map { dailyTotals[$0, default: 0] }
        let maxValue = values.max() ?? 0

        return dates.map { date in
            let amount = dailyTotals[date, default: 0]
            let intensity = maxValue > 0 ? (amount / maxValue) : 0
            return DayCell(
                id: isoDayId(for: date),
                date: date,
                amount: amount,
                intensity: intensity
            )
        }
    }
    
    private func isoDayId(for date: Date) -> String {
        Self.isoDayFormatter.string(from: date)
    }
    
    private var weekdayOffset: Int {
        let first = renderRange.start
        // Make Monday = 0 ... Sunday = 6 for a nicer week layout.
        let weekday = calendar.component(.weekday, from: first) // 1=Sunday...7=Saturday
        let mondayBased = (weekday + 5) % 7
        return mondayBased
    }
    
    private var weekdaySymbols: [String] {
        // Mon..Sun short
        let symbols = calendar.shortWeekdaySymbols // Sun..Sat
        return Array(symbols[1...6]) + [symbols[0]]
    }
    
    /// Everything the two layouts need, derived from **one** walk of the
    /// day range. PERF: `days` (up to 365 `date(byAdding:)` + ISO id
    /// formats) used to be re-entered by five separate computed
    /// properties per body — and the body re-runs on every cell tap and
    /// every parent Insights re-render.
    private struct GridModel {
        /// Weekday-major flat cells: 7 rows × `weekCount` columns.
        let cellsRowMajor: [DayCell?]
        /// Number of week columns the range spans (including the
        /// leading weekday offset).
        let weekCount: Int

        static let empty = GridModel(cellsRowMajor: [], weekCount: 0)

        /// Short ranges (Today / This Week / This Month / custom ≤ 6
        /// weeks) render as a calendar — weekdays across, weeks down —
        /// so the cells fill the card. The GitHub-style week-column
        /// strip is kept for long ranges, where it earns its horizontal
        /// scroll; for a month it was a 5 × 18pt block beside ~200pt of
        /// empty card.
        var usesCalendarLayout: Bool { weekCount > 0 && weekCount <= 6 }
    }

    private func makeGrid() -> GridModel {
        // Render as week columns (horizontal) with weekday rows (vertical),
        // so longer ranges stay readable and can scroll horizontally.
        let items = days
        guard !items.isEmpty else { return .empty }

        let offset = weekdayOffset
        let dateCount = items.count
        let totalSlots = offset + dateCount
        let weekCount = Int(ceil(Double(totalSlots) / 7.0))

        var byWeek: [[DayCell?]] = Array(repeating: Array(repeating: nil, count: 7), count: weekCount)

        for i in 0..<dateCount {
            let pos = offset + i
            let week = pos / 7
            let weekday = pos % 7 // 0=Mon ... 6=Sun
            if week < weekCount {
                byWeek[week][weekday] = items[i]
            }
        }

        var out: [DayCell?] = []
        out.reserveCapacity(weekCount * 7)

        // Flatten in row-major order for LazyHGrid (rows first, then columns).
        for weekday in 0..<7 {
            for week in 0..<weekCount {
                out.append(byWeek[week][weekday])
            }
        }

        return GridModel(cellsRowMajor: out, weekCount: weekCount)
    }

    /// Largest calendar cell; keeps wide (iPad / Duo) cards from
    /// blowing the squares up to 56pt.
    private let calendarCellMax: CGFloat = 44
    private let calendarSpacing: CGFloat = 8

    var body: some View {
        let grid = makeGrid()
        VStack(alignment: .leading, spacing: 14) {
            if grid.usesCalendarLayout {
                calendarGrid(grid)
            } else {
                weekColumnStrip(grid)
            }

            if let selectedCell {
                HStack {
                    Text(selectedCell.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formattedAmount(selectedCell.amount))
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.systemBackground)
                .cornerRadius(12)
            } else {
                Text("Tap a day to see the total.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if isCapped {
                Text("Heatmap shows the last \(maxDaysToRender) days of the selected range.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: startDate) {
            selectedCell = nil
        }
        .onChange(of: endDate) {
            selectedCell = nil
        }
    }

    // MARK: Calendar layout (≤ 6 weeks)

    private func calendarGrid(_ grid: GridModel) -> some View {
        // Clamp: at AX text sizes the scaled `cellSize` can exceed the
        // 44pt cap, which would hand GridItem a min > max.
        let columns = Array(
            repeating: GridItem(
                .flexible(minimum: min(cellSize, calendarCellMax), maximum: calendarCellMax),
                spacing: calendarSpacing
            ),
            count: 7
        )
        // Same week-major cells as the strip, re-read week by week.
        let byWeek: [[DayCell?]] = {
            let flat = grid.cellsRowMajor          // weekday-major: 7 rows × weekCount
            let weeks = grid.weekCount
            guard weeks > 0, flat.count == 7 * weeks else { return [] }
            return (0..<weeks).map { week in
                (0..<7).map { weekday in flat[weekday * weeks + week] }
            }
        }()

        return LazyVGrid(columns: columns, spacing: calendarSpacing) {
            ForEach(weekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ForEach(Array(byWeek.enumerated()), id: \.offset) { _, week in
                ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        dayCellView(cell)
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: 7 * calendarCellMax + 6 * calendarSpacing, alignment: .leading)
        // Let the surrounding card keep its column width even when the
        // grid caps out (iPad / Duo two-column Insights).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func dayCellView(_ cell: DayCell) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(accentColor.opacity(0.12 + (0.78 * cell.intensity)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selectedCell?.id == cell.id ? accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture {
                HapticManager.shared.selectionChanged()
                selectedCell = (selectedCell?.id == cell.id) ? nil : cell
            }
            .accessibilityLabel("\(cell.date.formatted(date: .abbreviated, time: .omitted)), \(formattedAmount(cell.amount))")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Week-column strip (long ranges)

    private func weekColumnStrip(_ grid: GridModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Scrollable grid (weeks horizontally)
            HStack(alignment: .top, spacing: 10) {
                // Weekday labels (Mon..Sun)
                VStack(spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .padding(.top, 2)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    let rows = Array(repeating: GridItem(.fixed(cellSize), spacing: 8), count: 7)
                    LazyHGrid(rows: rows, spacing: 8) {
                        ForEach(Array(grid.cellsRowMajor.enumerated()), id: \.offset) { _, cell in
                            if let cell {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(accentColor.opacity(0.12 + (0.78 * cell.intensity)))
                                    .frame(width: cellSize, height: cellSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(selectedCell?.id == cell.id ? accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 5))
                                    .onTapGesture {
                                        HapticManager.shared.selectionChanged()
                                        selectedCell = (selectedCell?.id == cell.id) ? nil : cell
                                    }
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}


