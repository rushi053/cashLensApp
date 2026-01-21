import SwiftUI

/// High-performance expense card that only re-renders when its specific data changes
struct ExpenseCard: View, Equatable {
    let expense: Expense
    let currencySymbol: String
    let categoryName: String
    let categoryIcon: String
    let categoryColorName: String
    let formattedAmount: String
    
    // Equatable conformance for efficient SwiftUI diffing
    static func == (lhs: ExpenseCard, rhs: ExpenseCard) -> Bool {
        lhs.expense.id == rhs.expense.id &&
        lhs.expense.amount == rhs.expense.amount &&
        lhs.expense.title == rhs.expense.title &&
        lhs.expense.date == rhs.expense.date &&
        lhs.categoryName == rhs.categoryName
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Category Icon - simplified for performance
            categoryIconView
            
            // Expense Details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
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
            
            Spacer(minLength: 8)
            
            // Amount and Date
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedAmount)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(expense.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        // Single lightweight shadow instead of multiple
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var categoryIconView: some View {
        ZStack {
            Circle()
                .fill(Color.forCategory(categoryColorName).opacity(0.25))
                .frame(width: 50, height: 50)
            
            Image(systemName: categoryIcon)
                .font(.system(size: 20))
                .foregroundColor(Color.forCategory(categoryColorName))
        }
        .drawingGroup() // Rasterize for better scroll performance
    }
}

// MARK: - Convenience Initializer with EnvironmentObjects
extension ExpenseCard {
    /// Convenience initializer that extracts data from view models
    /// This creates a self-contained card that won't re-render on unrelated viewModel changes
    init(expense: Expense, viewModel: ExpenseViewModel, categoryViewModel: CategoryViewModel) {
        self.expense = expense
        self.currencySymbol = viewModel.currencySymbol
        self.formattedAmount = viewModel.formattedAmount(expense.amount)
        
        // Pre-compute category info to avoid lookups during render
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            self.categoryName = custom.name
            self.categoryIcon = custom.icon
            self.categoryColorName = custom.colorName
        } else {
            self.categoryName = expense.category.rawValue
            self.categoryIcon = expense.category.icon
            self.categoryColorName = expense.category.color
        }
    }
}

// MARK: - Legacy Initializer (for backward compatibility)
extension ExpenseCard {
    @ViewBuilder
    static func withEnvironment(expense: Expense) -> some View {
        ExpenseCardWrapper(expense: expense)
    }
}

/// Wrapper that uses environment objects for backward compatibility
private struct ExpenseCardWrapper: View {
    let expense: Expense
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    var body: some View {
        ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
    }
}

struct ExpenseCard_Previews: PreviewProvider {
    static var previews: some View {
        let sample = Expense.sampleData[0]
        ExpenseCard(
            expense: sample,
            currencySymbol: "$",
            categoryName: sample.category.rawValue,
            categoryIcon: sample.category.icon,
            categoryColorName: sample.category.color,
            formattedAmount: "$49.99"
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
} 