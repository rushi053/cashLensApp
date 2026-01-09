import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Core Data (shared helpers)
    
    func loadExpenses() {
        viewContext.performAndWait {
            let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
            
            do {
                let results = try viewContext.fetch(fetchRequest)
                self.expenses = results.toExpenses()
            } catch {
                print("Error loading expenses: \(error.localizedDescription)")
                self.expenses = []
            }
        }
    }
    
    func updateFilteredExpenses() {
        filteredExpenses = filterExpenses(
            expenses,
            category: selectedCategory,
            customCategoryId: selectedCustomCategoryId,
            timeFrame: selectedTimeFrame
        )
    }
    
    func saveContext() {
        viewContext.performAndWait {
            guard viewContext.hasChanges else { return }
            do {
                try viewContext.save()
            } catch {
                print("Error saving context: \(error.localizedDescription)")
            }
        }
    }
}


