import SwiftUI

struct CustomCategoryItem: View {
    let category: CustomCategory
    let isSelected: Bool
    let action: () -> Void
    
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
                .overlay(
                    Circle()
                        .stroke(isSelected ? 
                               Color.forCategory(category.colorName).opacity(0.9) : 
                               Color.clear, 
                               lineWidth: 3)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                .shadow(color: isSelected ?
                       Color.forCategory(category.colorName).opacity(0.25) :
                       Color.clear,
                       radius: 6, x: 0, y: 0)
                
                Text(category.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? Color.forCategory(category.colorName) : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
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