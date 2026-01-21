import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Currency Sync
    
    func syncCurrencyAcrossStoredData() {
        updateAllExpensesToCurrentCurrency()
        updateAllSubscriptionsToCurrentCurrency()
    }
    
    func updateAllExpensesToCurrentCurrency() {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                entity.currency = selectedCurrency.rawValue
            }
            saveContext()
            loadExpenses()
        } catch {
            print("Error updating expenses currency: \(error.localizedDescription)")
        }
    }
    
    func updateAllSubscriptionsToCurrentCurrency() {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            var updateCount = 0
            var previousCurrencies: Set<String> = []
            
            for entity in results {
                if let currentCurrency = entity.currency, currentCurrency != selectedCurrency.rawValue {
                    previousCurrencies.insert(currentCurrency)
                }
                entity.currency = selectedCurrency.rawValue
                updateCount += 1
            }
            
            if updateCount > 0 {
                saveContext()
                let currencyList = previousCurrencies.joined(separator: ", ")
                print("✅ Updated \(updateCount) subscription(s) from [\(currencyList)] to \(selectedCurrency.rawValue)")
                
                NotificationCenter.default.post(
                    name: .subscriptionCurrencyUpdated,
                    object: nil,
                    userInfo: [
                        "updateCount": updateCount,
                        "newCurrency": selectedCurrency.rawValue,
                        "previousCurrencies": Array(previousCurrencies)
                    ]
                )
            } else {
                print("ℹ️ No subscriptions to update (0 subscriptions found)")
            }
        } catch {
            print("❌ Error updating subscriptions currency: \(error.localizedDescription)")
        }
    }
}


