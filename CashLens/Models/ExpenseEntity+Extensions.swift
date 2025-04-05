import Foundation
import CoreData

extension ExpenseEntity {
    // Convert from Expense struct to ExpenseEntity
    static func fromExpense(_ expense: Expense, context: NSManagedObjectContext) -> ExpenseEntity {
        let entity = ExpenseEntity(context: context)
        entity.id = expense.id
        entity.title = expense.title
        entity.amount = expense.amount
        entity.currency = expense.currency.rawValue
        entity.date = expense.date
        entity.category = expense.category.rawValue
        entity.notes = expense.notes
        entity.customCategoryId = expense.customCategoryId
        return entity
    }
    
    // Convert to Expense struct
    func toExpense() -> Expense {
        return Expense(
            id: self.id ?? UUID(),
            title: self.title ?? "",
            amount: self.amount,
            currency: Expense.Currency(rawValue: self.currency ?? "USD") ?? .usd,
            date: self.date ?? Date(),
            category: Expense.Category(rawValue: self.category ?? "Other") ?? .other,
            notes: self.notes,
            customCategoryId: self.customCategoryId
        )
    }
}

// Extension for fetching and sorting expenses
extension Collection where Element == ExpenseEntity {
    func toExpenses() -> [Expense] {
        return self.map { $0.toExpense() }
    }
} 