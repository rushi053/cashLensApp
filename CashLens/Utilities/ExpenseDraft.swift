import Foundation

struct ExpenseDraft: Codable {
    let title: String
    let amount: String
    let date: Date
    let selectedCategory: Expense.Category
    let selectedCustomCategoryId: UUID?
    let notes: String
    let timestamp: Date
    
    init(title: String, amount: String, date: Date, selectedCategory: Expense.Category, selectedCustomCategoryId: UUID?, notes: String) {
        self.title = title
        self.amount = amount
        self.date = date
        self.selectedCategory = selectedCategory
        self.selectedCustomCategoryId = selectedCustomCategoryId
        self.notes = notes
        self.timestamp = Date()
    }
}


