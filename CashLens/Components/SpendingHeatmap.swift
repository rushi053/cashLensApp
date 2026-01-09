import SwiftUI

struct SpendingHeatmap: View {
    struct DayCell: Identifiable {
        let id: String
        let date: Date
        let amount: Double
        let intensity: Double
    }
    
    let expenses: [Expense]
    let startDate: Date
    let endDate: Date
    let accentColor: Color
    let formattedAmount: (Double) -> String
    
    /// Safety cap so extremely large ranges (e.g. "All Time" = distantPast) don't freeze the UI.
    /// Shows the *most recent* `maxDaysToRender` days of the selected range.
    let maxDaysToRender: Int = 365
    
    @State private var selectedCell: DayCell?
    
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

        var totalsByDay: [Date: Double] = [:]
        for expense in expenses {
            let key = calendar.startOfDay(for: expense.date)
            totalsByDay[key, default: 0] += expense.amount
        }
        
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
        }
        
        let values = dates.map { totalsByDay[$0, default: 0] }
        let maxValue = values.max() ?? 0
        
        return dates.map { date in
            let amount = totalsByDay[date, default: 0]
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
    
    private var gridCellsRowMajor: [DayCell?] {
        // Render as week columns (horizontal) with weekday rows (vertical),
        // so longer ranges stay readable and can scroll horizontally.
        let items = days
        guard !items.isEmpty else { return [] }
        
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
        
        return out
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Scrollable grid (weeks horizontally)
            HStack(alignment: .top, spacing: 10) {
                // Weekday labels (Mon..Sun)
                VStack(spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(height: 18)
                    }
                }
                .padding(.top, 2)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    let rows = Array(repeating: GridItem(.fixed(18), spacing: 8), count: 7)
                    LazyHGrid(rows: rows, spacing: 8) {
                        ForEach(Array(gridCellsRowMajor.enumerated()), id: \.offset) { _, cell in
                            if let cell {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(accentColor.opacity(0.12 + (0.78 * cell.intensity)))
                                    .frame(width: 18, height: 18)
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
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onChange(of: startDate) { _ in
                selectedCell = nil
            }
            .onChange(of: endDate) { _ in
                selectedCell = nil
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
    }
}


