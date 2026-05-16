import Foundation
@preconcurrency import CoreData

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
    
    // PERF: Removed `updateFilteredExpenses()` — it was only called
    // by `refreshData()` on foreground and ran the filter
    // **synchronously on the main thread**. It also fought the
    // off-main pipeline in `setupFiltering` which would publish a
    // newer result a frame later, causing one wasted O(N) main-thread
    // pass per foreground transition. Filtering is now exclusively
    // driven by the debounced Combine sink → `scheduleFilterRecompute`.

    // MARK: - Incremental in-memory updates
    //
    // PERF: Every CRUD method used to call `loadExpenses()` at the
    // end, which re-fetched the **entire** ExpenseEntity table from
    // SQLite, mapped every row to a Swift `Expense` value, and then
    // reassigned `expenses` — an O(N) main-thread pass for every
    // single-row save. The audit identified this as the single
    // biggest source of "slow with data, fast without" perception.
    //
    // The three helpers below mutate the in-memory `expenses` array
    // in place to mirror what just happened on disk. Because
    // `expenses` is `@Published`, assignment still triggers the
    // downstream filter / budget / widget / digest pipelines exactly
    // once — but we skip the full Core Data fetch and the row-by-row
    // `toExpense()` allocations. Saves go from O(N) to O(log N) or
    // O(1) work on the main thread for typical edits.
    //
    // Contract:
    //   • Each helper must be called **only after `saveContext()`
    //     succeeds**, so the in-memory array can never get ahead of
    //     Core Data.
    //   • If the targeted row is not present in `expenses` (which
    //     would mean the in-memory state has drifted from Core Data —
    //     e.g. after a backup restore), we fall back to a full
    //     `loadExpenses()` to re-establish ground truth.
    //   • The array must remain sorted by date descending to match
    //     `loadExpenses()`'s `NSSortDescriptor`, since every consumer
    //     downstream (filter, hero average, recent titles, recent
    //     expenses list) assumes that order.

    /// Insert one new expense into the in-memory array at the
    /// correct date-desc position. O(N) worst case (single linear
    /// scan + shift) but with no Core Data round-trip and no
    /// allocation per existing row.
    func applyIncrementalInsert(_ expense: Expense) {
        let insertIndex = expenses.firstIndex(where: { $0.date < expense.date }) ?? expenses.count
        expenses.insert(expense, at: insertIndex)
    }

    /// Replace one expense in-place. If the date changed we also
    /// move it to the correct position so the array stays sorted.
    /// Falls back to a full reload if the row isn't present
    /// in-memory (drift case).
    func applyIncrementalUpdate(_ expense: Expense) {
        guard let idx = expenses.firstIndex(where: { $0.id == expense.id }) else {
            loadExpenses()
            return
        }
        let oldDate = expenses[idx].date
        if oldDate == expense.date {
            expenses[idx] = expense
        } else {
            expenses.remove(at: idx)
            let insertIndex = expenses.firstIndex(where: { $0.date < expense.date }) ?? expenses.count
            expenses.insert(expense, at: insertIndex)
        }
    }

    /// Remove zero or more expenses by id in one publish. Cheap
    /// even for large bulk-delete selections because the Swift
    /// `removeAll(where:)` does a single pass over the array.
    func applyIncrementalDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        expenses.removeAll(where: { ids.contains($0.id) })
    }

    func saveContext() {
        viewContext.performAndWait {
            guard viewContext.hasChanges else { return }
            do {
                try viewContext.save()
            } catch {
                // Surface to the user via the global save-error
                // banner so silent failures don't leave the UI in
                // a "looks saved" state. See `SaveErrorReporter`.
                SaveErrorReporter.report(operation: "saving your changes", error: error)
            }
        }
    }
    
    /// Save context asynchronously to avoid blocking UI
    func saveContextAsync() {
        let context = viewContext
        Task {
            await context.perform {
                guard context.hasChanges else { return }
                do {
                    try context.save()
                } catch {
                    SaveErrorReporter.report(operation: "saving your changes", error: error)
                }
            }
        }
    }
}


