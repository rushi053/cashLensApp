import SwiftUI

struct CategoryItem: View, Equatable {
    let category: Expense.Category
    let isSelected: Bool
    let action: () -> Void
    
    // Equatable conformance - ignore action closure
    static func == (lhs: CategoryItem, rhs: CategoryItem) -> Bool {
        lhs.category == rhs.category && lhs.isSelected == rhs.isSelected
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.forCategory(category.color).opacity(0.3))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 24))
                        .foregroundColor(Color.forCategory(category.color))
                }
                .drawingGroup() // Rasterize icon for better scroll performance
                // Selection ring as overlay (outside drawingGroup to prevent clipping)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.forCategory(category.color).opacity(0.9) : Color.clear,
                                lineWidth: 3)
                )
                // Single lightweight shadow
                .shadow(color: isSelected ? Color.forCategory(category.color).opacity(0.2) : Color.black.opacity(0.04),
                        radius: isSelected ? 4 : 2, x: 0, y: 1)
                
                Text(category.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(isSelected ? Color.forCategory(category.color) : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

struct CategoryItem_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            CategoryItem(category: .food, isSelected: true, action: {})
            CategoryItem(category: .transportation, isSelected: false, action: {})
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
} 