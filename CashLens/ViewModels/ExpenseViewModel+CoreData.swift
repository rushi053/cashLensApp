import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Core Data (shared helpers)
    
    /// Load expenses from Core Data with optional background loading for large datasets
    func loadExpenses() {
        // For initial load, use synchronous fetch to ensure data is ready
        // This is acceptable since it only happens once at app startup
        viewContext.performAndWait {
            let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
            fetchRequest.fetchBatchSize = 100 // Load in batches for memory efficiency
            
            do {
                let results = try viewContext.fetch(fetchRequest)
                self.expenses = results.toExpenses()
            } catch {
                print("Error loading expenses: \(error.localizedDescription)")
                self.expenses = []
            }
        }
    }
    
    /// Load expenses asynchronously on background thread (for refreshes)
    func loadExpensesAsync() {
        Task { @MainActor in
            let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
            backgroundContext.automaticallyMergesChangesFromParent = true
            
            let loadedExpenses = await Task.detached(priority: .userInitiated) {
                await backgroundContext.perform {
                    let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
                    fetchRequest.fetchBatchSize = 100
                    
                    do {
                        let results = try backgroundContext.fetch(fetchRequest)
                        return results.toExpenses()
                    } catch {
                        print("Error loading expenses async: \(error.localizedDescription)")
                        return [] as [Expense]
                    }
                }
            }.value
            
            self.expenses = loadedExpenses
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
    
    /// Save context asynchronously to avoid blocking UI
    func saveContextAsync() {
        Task {
            await viewContext.perform {
                guard self.viewContext.hasChanges else { return }
                do {
                    try self.viewContext.save()
                } catch {
                    print("Error saving context async: \(error.localizedDescription)")
                }
            }
        }
    }
}


