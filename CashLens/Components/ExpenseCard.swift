import SwiftUI

struct ExpenseCard: View {
    let expense: Expense
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    private var customCategory: CustomCategory? {
        guard expense.category == .custom, let id = expense.customCategoryId else { return nil }
        return categoryViewModel.customCategories.first(where: { $0.id == id })
    }
    
    private var categoryName: String {
        customCategory?.name ?? expense.category.rawValue
    }
    
    private var categoryIcon: String {
        customCategory?.icon ?? expense.category.icon
    }
    
    private var categoryColorName: String {
        customCategory?.colorName ?? expense.category.color
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(Color.forCategory(categoryColorName).opacity(0.3))
                    .frame(width: 50, height: 50)
                
                Image(systemName: categoryIcon)
                    .font(.system(size: 20))
                    .foregroundColor(Color.forCategory(categoryColorName))
            }
            
            // Expense Details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(categoryName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let notes = expense.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Amount and Date
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.formattedAmount(expense.amount))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(expense.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
    }
}

struct ExpenseCard_Previews: PreviewProvider {
    static var previews: some View {
        ExpenseCard(expense: Expense.sampleData[0])
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
            .previewLayout(.sizeThatFits)
            .padding()
    }
} 