import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Maintenance / Health
    
    /// Reload data on foreground / `scenePhase == .active`.
    ///
    /// PERF (round 1): Previously this called both `loadExpenses()`
    /// **and** `updateFilteredExpenses()`. The second call did the
    /// filter **synchronously on the main thread** — and the off-main
    /// pipeline fired a moment later off the back of `loadExpenses()`'s
    /// `$expenses` publish, doing the same filter again. We removed
    /// the synchronous half.
    ///
    /// PERF (round 2): The remaining `loadExpenses()` still hit Core
    /// Data + mapped every entity on the main thread on every
    /// foreground — a 50–100 ms stall at scale for data that almost
    /// never actually changes (the app is the sole writer of its
    /// own SQLite store, so a foreground transition can't have made
    /// the in-memory state stale). We now use `loadExpensesAsync()`
    /// so the fetch + mapping happen on a background context; the
    /// main-actor reassignment of `expenses` still fires the
    /// downstream pipeline exactly once but doesn't block the
    /// scene-phase transition.
    func refreshData() {
        loadExpensesAsync()
    }
    
    func checkDataExists() -> String {
        var dataStatus: [String] = []
        dataStatus.append("Expenses: \(expenses.count)")
        dataStatus.append("Subscriptions: \(loadSubscriptionsForExport().count)")
        dataStatus.append("Custom Categories: \(getCustomCategories().count)")
        dataStatus.append("Deleted Default Categories: \(getDeletedDefaultCategories().count)")
        return dataStatus.joined(separator: ", ")
    }
    
    func checkCurrencyConsistency() -> (isConsistent: Bool, report: String) {
        var report: [String] = []
        var allCurrenciesConsistent = true
        
        // Expenses
        let expenseCurrencies = Set(expenses.map { $0.currency.rawValue })
        if expenseCurrencies.count > 1 {
            allCurrenciesConsistent = false
            report.append("⚠️ Expenses have mixed currencies: \(expenseCurrencies.joined(separator: ", "))")
        } else if let expenseCurrency = expenseCurrencies.first {
            if expenseCurrency != selectedCurrency.rawValue {
                allCurrenciesConsistent = false
                report.append("⚠️ Expenses currency (\(expenseCurrency)) doesn't match selected currency (\(selectedCurrency.rawValue))")
            } else {
                report.append("✅ All \(expenses.count) expenses use \(expenseCurrency)")
            }
        }
        
        // Subscriptions
        let subscriptions = loadSubscriptionsForExport()
        let subscriptionCurrencies = Set(subscriptions.map { $0.currency.rawValue })
        if subscriptionCurrencies.count > 1 {
            allCurrenciesConsistent = false
            report.append("⚠️ Subscriptions have mixed currencies: \(subscriptionCurrencies.joined(separator: ", "))")
        } else if let subscriptionCurrency = subscriptionCurrencies.first {
            if subscriptionCurrency != selectedCurrency.rawValue {
                allCurrenciesConsistent = false
                report.append("⚠️ Subscriptions currency (\(subscriptionCurrency)) doesn't match selected currency (\(selectedCurrency.rawValue))")
            } else {
                report.append("✅ All \(subscriptions.count) subscriptions use \(subscriptionCurrency)")
            }
        }
        
        report.insert(
            allCurrenciesConsistent
                ? "✅ All currencies are consistent with selected currency: \(selectedCurrency.rawValue)"
                : "❌ Currency inconsistency detected!",
            at: 0
        )
        
        return (allCurrenciesConsistent, report.joined(separator: "\n"))
    }
    
    func clearAllData() {
        print("Starting to clear all app data...")
        print("📊 Before clearing: \(checkDataExists())")
        
        var clearSuccessful = true
        
        // 1. Clear all Expenses
        do {
            let expenseFetchRequest: NSFetchRequest<NSFetchRequestResult> = ExpenseEntity.fetchRequest()
            let expenseBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: expenseFetchRequest)
            expenseBatchDeleteRequest.resultType = .resultTypeObjectIDs
            
            let expenseResult = try viewContext.execute(expenseBatchDeleteRequest) as? NSBatchDeleteResult
            if let objectIDs = expenseResult?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
            
            expenses = []
            print("✅ Cleared all expenses")
        } catch {
            print("❌ Error clearing expenses: \(error.localizedDescription)")
            clearSuccessful = false
        }
        
        // 2. Clear all Subscriptions
        do {
            let subscriptionFetchRequest: NSFetchRequest<NSFetchRequestResult> = SubscriptionEntity.fetchRequest()
            let subscriptionBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: subscriptionFetchRequest)
            subscriptionBatchDeleteRequest.resultType = .resultTypeObjectIDs
            
            let subscriptionResult = try viewContext.execute(subscriptionBatchDeleteRequest) as? NSBatchDeleteResult
            if let objectIDs = subscriptionResult?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
            
            print("✅ Cleared all subscriptions")
        } catch {
            print("❌ Error clearing subscriptions: \(error.localizedDescription)")
            clearSuccessful = false
        }
        
        // 3. Clear all Custom Categories
        do {
            let categoryFetchRequest: NSFetchRequest<NSFetchRequestResult> = CustomCategoryEntity.fetchRequest()
            let categoryBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: categoryFetchRequest)
            categoryBatchDeleteRequest.resultType = .resultTypeObjectIDs
            
            let categoryResult = try viewContext.execute(categoryBatchDeleteRequest) as? NSBatchDeleteResult
            if let objectIDs = categoryResult?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
            
            print("✅ Cleared all custom categories")
        } catch {
            print("❌ Error clearing custom categories: \(error.localizedDescription)")
            clearSuccessful = false
        }
        
        // 4. Clear Deleted Default Categories from UserDefaults
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.deletedDefaultCategories)
        print("✅ Cleared deleted default categories list")
        
        // 5. Save changes to Core Data
        if clearSuccessful {
            saveContext()
            NotificationCenter.default.post(name: .dataDidClear, object: nil)
            print("✅ All data cleared successfully!")
            print("📊 After clearing: \(checkDataExists())")
        } else {
            print("⚠️ Some data may not have been cleared completely")
            print("📊 After partial clear: \(checkDataExists())")
        }
    }
}


