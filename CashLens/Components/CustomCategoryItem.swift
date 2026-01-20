import SwiftUI

struct CustomCategoryItem: View, Equatable {
    let category: CustomCategory
    let isSelected: Bool
    let action: () -> Void
    
    // Equatable conformance - ignore action closure
    static func == (lhs: CustomCategoryItem, rhs: CustomCategoryItem) -> Bool {
        lhs.category.id == rhs.category.id && lhs.isSelected == rhs.isSelected
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.forCategory(category.colorName).opacity(0.3))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 24))
                        .foregroundColor(Color.forCategory(category.colorName))
                }
                .drawingGroup() // Rasterize icon for better scroll performance
                // Selection ring as overlay (outside drawingGroup to prevent clipping)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.forCategory(category.colorName).opacity(0.9) : Color.clear,
                                lineWidth: 3)
                )
                // Single lightweight shadow
                .shadow(color: isSelected ? Color.forCategory(category.colorName).opacity(0.2) : Color.black.opacity(0.04),
                        radius: isSelected ? 4 : 2, x: 0, y: 1)
                
                Text(category.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? Color.forCategory(category.colorName) : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

struct CustomCategoryItem_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            CustomCategoryItem(
                category: CustomCategory(name: "Pets", icon: "pawprint.fill", colorName: "celadon"),
                isSelected: true,
                action: {}
            )
            CustomCategoryItem(
                category: CustomCategory(name: "Gifts", icon: "gift.fill", colorName: "teaRose"),
                isSelected: false,
                action: {}
            )
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
} 