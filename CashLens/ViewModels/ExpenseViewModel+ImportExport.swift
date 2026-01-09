import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Data Export
    
    /// Export all app data to CSV.
    /// Thread-safe: uses a background Core Data context for fetching.
    func exportToCSV() -> URL? {
        let fileName = "CashLens_Data_\(formattedCurrentDate()).csv"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        let deletedCategories = getDeletedDefaultCategories()
        
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        var exportedExpenses: [Expense] = []
        var exportedSubscriptions: [Subscription] = []
        var exportedCustomCategories: [CustomCategory] = []
        
        backgroundContext.performAndWait {
            do {
                // Expenses
                let expenseFetch: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                expenseFetch.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
                exportedExpenses = try backgroundContext.fetch(expenseFetch).toExpenses()
                
                // Subscriptions
                let subFetch: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                subFetch.sortDescriptors = [
                    NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
                    NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
                ]
                exportedSubscriptions = try backgroundContext.fetch(subFetch).toSubscriptions()
                
                // Custom Categories
                let catFetch: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
                catFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
                exportedCustomCategories = try backgroundContext.fetch(catFetch).toCustomCategories()
            } catch {
                print("Failed to fetch export data: \(error.localizedDescription)")
            }
        }
        
        var csvText = ""
        
        // 1. Export Expenses
        csvText += "=== EXPENSES ===\n"
        csvText += "\"ID\",\"Date\",\"Title\",\"Amount\",\"Currency\",\"Category\",\"CustomCategoryId\",\"Notes\"\n"
        
        for expense in exportedExpenses {
            let id = expense.id.uuidString
            let date = dateFormatter.string(from: expense.date)
            let title = expense.title.replacingOccurrences(of: "\"", with: "\"\"")
            let amount = String(format: "%.2f", expense.amount)
            let currency = expense.currency.rawValue
            let category = expense.category.rawValue
            let customCategoryId = expense.customCategoryId?.uuidString ?? ""
            let notes = expense.notes?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            
            let newLine = "\"\(id)\",\"\(date)\",\"\(title)\",\"\(amount)\",\"\(currency)\",\"\(category)\",\"\(customCategoryId)\",\"\(notes)\"\n"
            csvText.append(newLine)
        }
        
        // 2. Export Subscriptions
        csvText += "\n=== SUBSCRIPTIONS ===\n"
        csvText += "\"ID\",\"Name\",\"Amount\",\"Currency\",\"StartDate\",\"Frequency\",\"NextDueDate\",\"Category\",\"CustomCategoryId\",\"Notes\",\"IsActive\",\"ReminderEnabled\",\"ReminderDaysBefore\"\n"
        
        for subscription in exportedSubscriptions {
            let id = subscription.id.uuidString
            let name = subscription.name.replacingOccurrences(of: "\"", with: "\"\"")
            let amount = String(format: "%.2f", subscription.amount)
            let currency = subscription.currency.rawValue
            let startDate = dateFormatter.string(from: subscription.startDate)
            let frequency = subscription.frequency.rawValue
            let nextDueDate = dateFormatter.string(from: subscription.nextDueDate)
            let category = subscription.category.rawValue
            let customCategoryId = subscription.customCategoryId?.uuidString ?? ""
            let notes = subscription.notes?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            let isActive = subscription.isActive ? "true" : "false"
            let reminderEnabled = subscription.reminderEnabled ? "true" : "false"
            let reminderDaysBefore = String(subscription.reminderDaysBefore)
            
            let newLine = "\"\(id)\",\"\(name)\",\"\(amount)\",\"\(currency)\",\"\(startDate)\",\"\(frequency)\",\"\(nextDueDate)\",\"\(category)\",\"\(customCategoryId)\",\"\(notes)\",\"\(isActive)\",\"\(reminderEnabled)\",\"\(reminderDaysBefore)\"\n"
            csvText.append(newLine)
        }
        
        // 3. Export Custom Categories
        csvText += "\n=== CUSTOM_CATEGORIES ===\n"
        csvText += "\"ID\",\"Name\",\"Icon\",\"ColorName\"\n"
        
        for category in exportedCustomCategories {
            let id = category.id.uuidString
            let name = category.name.replacingOccurrences(of: "\"", with: "\"\"")
            let icon = category.icon
            let colorName = category.colorName
            
            let newLine = "\"\(id)\",\"\(name)\",\"\(icon)\",\"\(colorName)\"\n"
            csvText.append(newLine)
        }
        
        // 4. Export Deleted Default Categories
        csvText += "\n=== DELETED_DEFAULT_CATEGORIES ===\n"
        csvText += "\"CategoryName\"\n"
        
        for categoryName in deletedCategories {
            let newLine = "\"\(categoryName)\"\n"
            csvText.append(newLine)
        }
        
        do {
            try csvText.write(to: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            print("Failed to create CSV file: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Export all app data to JSON.
    /// Thread-safe: uses a background Core Data context for fetching.
    func exportToJSON() -> URL? {
        let fileName = "CashLens_Data_\(formattedCurrentDate()).json"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        let deletedCategories = Array(getDeletedDefaultCategories())
        
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        var exportedExpenses: [Expense] = []
        var exportedSubscriptions: [Subscription] = []
        var exportedCustomCategories: [CustomCategory] = []
        
        backgroundContext.performAndWait {
            do {
                // Expenses
                let expenseFetch: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                expenseFetch.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
                exportedExpenses = try backgroundContext.fetch(expenseFetch).toExpenses()
                
                // Subscriptions
                let subFetch: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                subFetch.sortDescriptors = [
                    NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
                    NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
                ]
                exportedSubscriptions = try backgroundContext.fetch(subFetch).toSubscriptions()
                
                // Custom Categories
                let catFetch: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
                catFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
                exportedCustomCategories = try backgroundContext.fetch(catFetch).toCustomCategories()
            } catch {
                print("Failed to fetch export data: \(error.localizedDescription)")
            }
        }
        
        let exportData: [String: Any] = [
            "exportVersion": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "expenses": exportedExpenses.map { expense in
                [
                    "id": expense.id.uuidString,
                    "title": expense.title,
                    "amount": expense.amount,
                    "currency": expense.currency.rawValue,
                    "date": ISO8601DateFormatter().string(from: expense.date),
                    "category": expense.category.rawValue,
                    "customCategoryId": expense.customCategoryId?.uuidString as Any,
                    "notes": expense.notes as Any,
                    "isFromSubscription": expense.isFromSubscription,
                    "subscriptionId": expense.subscriptionId?.uuidString as Any
                ]
            },
            "subscriptions": exportedSubscriptions.map { subscription in
                [
                    "id": subscription.id.uuidString,
                    "name": subscription.name,
                    "amount": subscription.amount,
                    "currency": subscription.currency.rawValue,
                    "startDate": ISO8601DateFormatter().string(from: subscription.startDate),
                    "frequency": subscription.frequency.rawValue,
                    "nextDueDate": ISO8601DateFormatter().string(from: subscription.nextDueDate),
                    "category": subscription.category.rawValue,
                    "customCategoryId": subscription.customCategoryId?.uuidString as Any,
                    "notes": subscription.notes as Any,
                    "isActive": subscription.isActive,
                    "reminderEnabled": subscription.reminderEnabled,
                    "reminderDaysBefore": subscription.reminderDaysBefore
                ]
            },
            "customCategories": exportedCustomCategories.map { category in
                [
                    "id": category.id.uuidString,
                    "name": category.name,
                    "icon": category.icon,
                    "colorName": category.colorName
                ]
            },
            "deletedDefaultCategories": deletedCategories
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            try jsonData.write(to: path)
            return path
        } catch {
            print("Failed to create JSON file: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Thread-safe helper: fetch subscriptions from the current viewContext's queue.
    func loadSubscriptionsForExport() -> [Subscription] {
        var result: [Subscription] = []
        viewContext.performAndWait {
            let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
                NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
            ]
            
            do {
                let entities = try viewContext.fetch(fetchRequest)
                result = entities.toSubscriptions()
            } catch {
                print("Error loading subscriptions for export: \(error.localizedDescription)")
                result = []
            }
        }
        return result
    }
    
    private func formattedCurrentDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    
    // MARK: - Data Import
    
    func importData(_ importResult: ImportResult, completion: @escaping (Bool, String) -> Void) {
        // Early validation of import data
        if importResult.expenses.isEmpty && importResult.subscriptions.isEmpty && importResult.customCategories.isEmpty {
            completion(false, "No valid data found in import file")
            return
        }
        
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        backgroundContext.perform {
            do {
                var importStats = ImportStats()
                
                // Phase 1: Import custom categories (so IDs exist for expenses/subscriptions)
                for customCategory in importResult.customCategories {
                    let fetch: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
                    fetch.fetchLimit = 1
                    fetch.predicate = NSPredicate(format: "id == %@", customCategory.id as CVarArg)
                    
                    let existingCount = try backgroundContext.count(for: fetch)
                    if existingCount == 0 {
                        _ = CustomCategoryEntity.fromCustomCategory(customCategory, context: backgroundContext)
                        importStats.customCategoriesImported += 1
                    } else {
                        importStats.customCategoriesSkipped += 1
                    }
                }
                
                // Phase 2: Import expenses with dedupe
                for expense in importResult.expenses {
                    guard self.validateExpenseData(expense) else {
                        importStats.expensesSkipped += 1
                        continue
                    }
                    
                    // Check by ID
                    let fetchById: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchById.fetchLimit = 1
                    fetchById.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
                    let existingById = try backgroundContext.count(for: fetchById)
                    if existingById > 0 {
                        importStats.expensesSkipped += 1
                        importStats.expensesSkippedById += 1
                        continue
                    }
                    
                    // Check content duplicates
                    guard !expense.title.isEmpty,
                          expense.amount.isFinite,
                          !expense.category.rawValue.isEmpty else {
                        importStats.expensesSkipped += 1
                        continue
                    }
                    
                    let fetchByContent: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchByContent.fetchLimit = 1
                    fetchByContent.predicate = NSPredicate(
                        format: "title == %@ AND amount == %@ AND date == %@ AND category == %@",
                        expense.title as NSString,
                        NSNumber(value: expense.amount),
                        expense.date as NSDate,
                        expense.category.rawValue as NSString
                    )
                    let existingByContent = try backgroundContext.count(for: fetchByContent)
                    if existingByContent == 0 {
                        _ = ExpenseEntity.fromExpense(expense, context: backgroundContext)
                        importStats.expensesImported += 1
                    } else {
                        importStats.expensesSkipped += 1
                        importStats.expensesSkippedByContent += 1
                    }
                }
                
                // Phase 3: Import subscriptions
                for subscription in importResult.subscriptions {
                    let fetch: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                    fetch.fetchLimit = 1
                    fetch.predicate = NSPredicate(format: "id == %@", subscription.id as CVarArg)
                    
                    let existingCount = try backgroundContext.count(for: fetch)
                    if existingCount == 0 {
                        _ = SubscriptionEntity.fromSubscription(subscription, context: backgroundContext)
                        importStats.subscriptionsImported += 1
                    } else {
                        importStats.subscriptionsSkipped += 1
                    }
                }
                
                // Phase 4: Deleted default categories (UserDefaults)
                if !importResult.deletedDefaultCategories.isEmpty {
                    let currentDeleted = self.getDeletedDefaultCategories()
                    let newDeleted = Set(importResult.deletedDefaultCategories)
                    let combinedDeleted = currentDeleted.union(newDeleted)
                    UserDefaults.standard.set(Array(combinedDeleted), forKey: UserDefaultsKeys.deletedDefaultCategories)
                    importStats.deletedCategoriesImported = newDeleted.subtracting(currentDeleted).count
                }
                
                // Save
                if backgroundContext.hasChanges {
                    try backgroundContext.save()
                }
                
                DispatchQueue.main.async {
                    self.loadExpenses()
                    let message = self.formatImportSuccessMessage(importStats)
                    completion(true, message)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Failed to import data: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatImportSuccessMessage(_ stats: ImportStats) -> String {
        var messages: [String] = []
        
        if stats.expensesImported > 0 {
            messages.append("\(stats.expensesImported) expense(s)")
        }
        if stats.subscriptionsImported > 0 {
            messages.append("\(stats.subscriptionsImported) subscription(s)")
        }
        if stats.customCategoriesImported > 0 {
            messages.append("\(stats.customCategoriesImported) custom categor(y/ies)")
        }
        if stats.deletedCategoriesImported > 0 {
            messages.append("\(stats.deletedCategoriesImported) deleted categor(y/ies)")
        }
        
        let importedMessage = messages.isEmpty ? "No new data" : "Successfully imported: " + messages.joined(separator: ", ")
        
        var skippedMessages: [String] = []
        if stats.expensesSkipped > 0 {
            let detailMessage = stats.expensesSkippedById > 0 && stats.expensesSkippedByContent > 0 ?
                "\(stats.expensesSkipped) expense(s) (duplicates)" :
                "\(stats.expensesSkipped) expense(s)"
            skippedMessages.append(detailMessage)
        }
        if stats.subscriptionsSkipped > 0 {
            skippedMessages.append("\(stats.subscriptionsSkipped) subscription(s)")
        }
        if stats.customCategoriesSkipped > 0 {
            skippedMessages.append("\(stats.customCategoriesSkipped) custom categor(y/ies)")
        }
        
        let skippedMessage = skippedMessages.isEmpty ? "" : "\n\nSkipped (already exists): " + skippedMessages.joined(separator: ", ")
        
        return importedMessage + skippedMessage
    }
    
    struct ImportStats {
        var expensesImported = 0
        var expensesSkipped = 0
        var expensesSkippedById = 0
        var expensesSkippedByContent = 0
        var subscriptionsImported = 0
        var subscriptionsSkipped = 0
        var customCategoriesImported = 0
        var customCategoriesSkipped = 0
        var deletedCategoriesImported = 0
    }
    
    private func validateExpenseData(_ expense: Expense) -> Bool {
        // Check for valid amount (no NaN, infinity, or negative values)
        guard expense.amount.isFinite && expense.amount >= 0 else {
            print("Invalid expense amount: \(expense.amount)")
            return false
        }
        
        // Check for valid title (not empty)
        guard !expense.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Invalid expense title: empty or whitespace only")
            return false
        }
        
        // Check for valid date (not too far in past or future)
        let now = Date()
        let tenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: now) ?? now
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        
        guard expense.date >= tenYearsAgo && expense.date <= oneYearFromNow else {
            print("Invalid expense date: \(expense.date) is outside reasonable range")
            return false
        }
        
        // Check for valid UUID format (should be valid UUID string representation)
        let uuidString = expense.id.uuidString
        guard UUID(uuidString: uuidString) != nil else {
            print("Invalid expense UUID: \(expense.id)")
            return false
        }
        
        // Check category validity
        guard !expense.category.rawValue.isEmpty else {
            print("Invalid expense category: empty rawValue")
            return false
        }
        
        // Check custom category ID if present
        if let customCategoryId = expense.customCategoryId {
            let customIdString = customCategoryId.uuidString
            guard UUID(uuidString: customIdString) != nil else {
                print("Invalid custom category UUID: \(customCategoryId)")
                return false
            }
        }
        
        return true
    }
}


