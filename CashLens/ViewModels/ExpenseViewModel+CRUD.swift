import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Core Data Operations (Expenses)
    
    func addExpense(_ expense: Expense) {
        // Ensure the expense uses the current selected currency
        var newExpense = expense
        newExpense.currency = selectedCurrency
        
        _ = ExpenseEntity.fromExpense(newExpense, context: viewContext)
        saveContext()
        loadExpenses()
        
        FeedbackManager.shared.incrementSuccessfulAction()
    }
    
    func updateExpense(_ expense: Expense) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let entity = results.first {
                entity.title = expense.title
                entity.amount = expense.amount
                entity.currency = expense.currency.rawValue
                entity.date = expense.date
                entity.category = expense.category.rawValue
                entity.notes = expense.notes
                entity.customCategoryId = expense.customCategoryId
                
                saveContext()
                loadExpenses()
            }
        } catch {
            print("Error updating expense: \(error.localizedDescription)")
        }
    }
    
    func deleteExpense(at indexSet: IndexSet) {
        // Ensure indices are valid to prevent crashes
        let validIndices = indexSet.filter { $0 < filteredExpenses.count }
        
        if validIndices.isEmpty {
            print("Warning: Attempted to delete expenses with invalid indices")
            return
        }
        
        // Map indices to expenses
        let expensesToDelete = validIndices.map { filteredExpenses[$0] }
        
        do {
            // Use a batch request for better performance when deleting multiple expenses
            if expensesToDelete.count > 1 {
                let ids = expensesToDelete.map { $0.id }
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = ExpenseEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id IN %@", ids as CVarArg)
                
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                
                let result = try viewContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                }
            } else {
                // Use regular delete for single expense
                for expense in expensesToDelete {
                    let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
                    
                    let results = try viewContext.fetch(fetchRequest)
                    for entity in results {
                        viewContext.delete(entity)
                    }
                    saveContext()
                }
            }
            
            loadExpenses()
        } catch {
            print("Error deleting expenses: \(error.localizedDescription)")
            loadExpenses()
        }
    }
    
    func deleteExpenseById(_ id: UUID) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                viewContext.delete(entity)
            }
            saveContext()
            loadExpenses()
        } catch {
            print("Error deleting expense by ID: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Formatting
    
    func formattedAmount(_ amount: Double) -> String {
        guard amount.isFinite else {
            return "\(selectedCurrency.symbol)0.00"
        }
        
        let safeAmount = max(amount, 0.0)
        numberFormatter.numberStyle = .decimal
        let formatted = numberFormatter.string(from: NSNumber(value: safeAmount)) ?? "0.00"
        return "\(selectedCurrency.symbol)\(formatted)"
    }
    
    func parseAmount(_ amountString: String) -> Double? {
        let cleanedAmount = amountString
            .replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanedAmount.isEmpty { return nil }
        
        if let number = numberFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        let standardFormatter = NumberFormatter()
        standardFormatter.decimalSeparator = "."
        if let number = standardFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        let commaFormatter = NumberFormatter()
        commaFormatter.decimalSeparator = ","
        if let number = commaFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        return nil
    }
}


