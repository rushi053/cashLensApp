import SwiftUI

struct CategoryItem: View {
    let category: Expense.Category
    let isSelected: Bool
    let action: () -> Void
    
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
                .overlay(
                    Circle()
                        .stroke(isSelected ? 
                               Color.forCategory(category.color).opacity(0.9) : 
                               Color.clear, 
                               lineWidth: 3)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                .shadow(color: isSelected ?
                       Color.forCategory(category.color).opacity(0.25) :
                       Color.clear,
                       radius: 6, x: 0, y: 0)
                
                Text(category.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(isSelected ? Color.forCategory(category.color) : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
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