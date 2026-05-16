import SwiftUI

struct ExpenseRow: View {
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
            // Category icon with proper handling for custom categories
            ZStack {
                Circle()
                    .fill(Color.forCategory(categoryColorName).opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Image(systemName: categoryIcon)
                    .font(.system(size: 16))
                    .foregroundColor(Color.forCategory(categoryColorName))
            }
            
            // Expense details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Use proper category display name
                Text(categoryName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount and date
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.formattedAmount(expense.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(formattedDate(expense.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        // Clean white row to match the new card system across the app.
        // Hairline border keeps the row edge visible against white parents.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct ExpenseRow_Previews: PreviewProvider {
    static var previews: some View {
        ExpenseRow(expense: Expense.sampleData[0])
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
            .padding()
            .previewLayout(.sizeThatFits)
    }
} 