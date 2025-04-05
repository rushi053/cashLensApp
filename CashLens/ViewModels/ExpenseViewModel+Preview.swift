import Foundation
import SwiftUI

// Extension to provide a preview instance of ExpenseViewModel
extension ExpenseViewModel {
    static var preview: ExpenseViewModel {
        let viewModel = ExpenseViewModel()
        
        // Add sample expenses
        viewModel.expenses = Expense.sampleData
        viewModel.filteredExpenses = Expense.sampleData
        
        return viewModel
    }
}