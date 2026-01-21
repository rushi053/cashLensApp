import SwiftUI

struct CategoryDonutChart: View {
    struct Slice: Identifiable {
        let id: String
        let title: String
        let amount: Double
        let color: Color
        let icon: String
        let category: Expense.Category?
        let customCategoryId: UUID?
    }
    
    let slices: [Slice]
    let total: Double
    let selectedId: String?
    let onSelect: (Slice?) -> Void
    
    private var normalizedSlices: [(slice: Slice, start: Double, end: Double)] {
        guard total > 0 else { return [] }
        var cursor: Double = 0
        return slices
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
            .map { slice in
                let fraction = slice.amount / total
                let start = cursor
                cursor += fraction
                return (slice, start, cursor)
            }
    }
    
    private var selectedSlice: Slice? {
        guard let selectedId else { return nil }
        return slices.first(where: { $0.id == selectedId })
    }
    
    private var centerTitle: String {
        selectedSlice?.title ?? "Total"
    }
    
    private var centerPercentText: String {
        guard total > 0 else { return "0%" }
        if let s = selectedSlice {
            return "\(Int(round((s.amount / total) * 100)))%"
        }
        return "100%"
    }
    
    private let strokeWidth: CGFloat = 18
    private let chartSize: CGFloat = 150
    
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Donut
                ZStack {
                    ForEach(normalizedSlices, id: \.slice.id) { item in
                        Circle()
                            .trim(from: item.start, to: item.end)
                            .stroke(
                                item.slice.color,
                                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .opacity(selectedId == nil || selectedId == item.slice.id ? 1.0 : 0.25)
                    }
                }
                .frame(width: chartSize, height: chartSize)
                .padding(strokeWidth / 2 + 2) // Account for stroke extending beyond frame + small buffer
                .clipShape(Circle()) // Ensure perfectly circular edges
                .drawingGroup()
                .contentShape(Circle())
                .onTapGesture {
                    // Tap center donut area toggles off selection
                    HapticManager.shared.selectionChanged()
                    onSelect(nil)
                }
                
                // Center label
                VStack(spacing: 4) {
                    Text(centerTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(centerPercentText)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.85), value: selectedId)
            }
            
            // Legend (top 6 to keep it tidy)
            let top = slices
                .filter { $0.amount > 0 }
                .sorted { $0.amount > $1.amount }
                .prefix(6)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(top), id: \.id) { slice in
                    Button {
                        HapticManager.shared.selectionChanged()
                        onSelect(selectedId == slice.id ? nil : slice)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(slice.color)
                                .frame(width: 10, height: 10)
                            
                            Text(slice.title)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer(minLength: 0)
                            
                            if total > 0 {
                                Text("\(Int(round((slice.amount / total) * 100)))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.systemBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedId == slice.id ? slice.color.opacity(0.6) : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}


