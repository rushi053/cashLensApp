import Foundation
import SwiftUI
import Combine
import CoreData

class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var filteredExpenses: [Expense] = []
    @Published var selectedCategory: Expense.Category?
    @Published var selectedCustomCategoryId: UUID?
    @Published var selectedTimeFrame: TimeFrame = .all
    @Published var selectedCurrency: Expense.Currency = .usd {
        didSet {
            if oldValue != selectedCurrency {
                updateAllExpensesToCurrentCurrency()
                updateAllSubscriptionsToCurrentCurrency()
            }
            UserDefaults.standard.set(selectedCurrency.rawValue, forKey: "selectedCurrency")
        }
    }
    @Published var userName: String = "CashLens User" {
        didSet {
            UserDefaults.standard.set(userName, forKey: "userName")
        }
    }
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            
            // Post notification immediately for UI update
            NotificationCenter.default.post(name: .appearanceDidChange, object: nil)
        }
    }
    
    enum TimeFrame: String, CaseIterable {
        case day = "Today"
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        case all = "All Time"
        
        var dateRange: (Date, Date) {
            let calendar = Calendar.current
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            
            switch self {
            case .day:
                return (startOfDay, now)
            case .week:
                let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                return (startOfWeek, now)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: now)
                let startOfMonth = calendar.date(from: components)!
                return (startOfMonth, now)
            case .year:
                let components = calendar.dateComponents([.year], from: now)
                let startOfYear = calendar.date(from: components)!
                return (startOfYear, now)
            case .all:
                return (Date.distantPast, now)
            }
        }
    }
    
    enum AppearanceMode: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"
        
        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    let viewContext: NSManagedObjectContext
    
    // Show currency picker on first launch
    @AppStorage("hasShownCurrencyPicker") var hasShownCurrencyPicker: Bool = false
    
    // Number formatter for consistent formatting across the app
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    // MARK: - Summary Cards Customization
    
    @Published var preferredSummaryCategories: [Expense.Category] = []
    
    private let summaryPreferencesKey = "preferred_summary_categories"
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        
        // Load saved preferences
        loadSelectedCurrency()
        loadSelectedTimeFrame()
        loadAppearanceMode()
        loadSummaryPreferences()
        
        // Load initial data
        loadExpenses()
        
        // Auto-select currency based on locale if not set
        autoSelectCurrencyIfNeeded()
        
        // Check if this is the first launch
        checkFirstLaunch()
        
        // Set up filtering
        setupFiltering()
    }
    
    // Load individual preferences from UserDefaults
    private func loadSelectedCurrency() {
        if let savedCurrency = UserDefaults.standard.string(forKey: "selectedCurrency"),
           let currency = Expense.Currency(rawValue: savedCurrency) {
            selectedCurrency = currency
        }
    }
    
    private func loadSelectedTimeFrame() {
        if let savedTimeFrame = UserDefaults.standard.string(forKey: "selectedTimeFrame"),
           let timeFrame = TimeFrame(rawValue: savedTimeFrame) {
            selectedTimeFrame = timeFrame
        }
    }
    
    private func loadAppearanceMode() {
        if let savedAppearance = UserDefaults.standard.string(forKey: "appearanceMode"),
           let appearance = AppearanceMode(rawValue: savedAppearance) {
            appearanceMode = appearance
        }
    }
    
    // Legacy method kept for compatibility - now delegates to individual methods
    private func loadUserPreferences() {
        if let savedName = UserDefaults.standard.string(forKey: "userName") {
            userName = savedName
        }
        
        loadSelectedCurrency()
        loadAppearanceMode()
        
        hasShownCurrencyPicker = UserDefaults.standard.bool(forKey: "hasShownCurrencyPicker")
    }
    
    // Auto-select currency based on user's locale if not already set
    private func autoSelectCurrencyIfNeeded() {
        if UserDefaults.standard.string(forKey: "selectedCurrency") == nil {
            let locale = Locale.current
            if let currencyCode = locale.currencyCode,
               let currency = Expense.Currency(rawValue: currencyCode.uppercased()) {
                selectedCurrency = currency
            }
        }
    }
    
    // Check if this is the first launch
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            hasShownCurrencyPicker = false
            UserDefaults.standard.set(false, forKey: "hasShownCurrencyPicker")
        }
    }
    
    // Set up filtering
    private func setupFiltering() {
        $expenses
            .combineLatest($selectedCategory, $selectedTimeFrame)
            .map { [weak self] expenses, category, timeFrame in
                self?.filterExpenses(expenses, category: category, timeFrame: timeFrame) ?? []
            }
            .assign(to: \.filteredExpenses, on: self)
            .store(in: &cancellables)
    }
    
    func addExpense(_ expense: Expense) {
        // Ensure the expense uses the current selected currency
        var newExpense = expense
        newExpense.currency = selectedCurrency
        
        // Save to Core Data
        _ = ExpenseEntity.fromExpense(newExpense, context: viewContext)
        saveContext()
        
        // Update the expenses array
        loadExpenses()
        
        // Track successful action for feedback request
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
                
                do {
                    let result = try viewContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    if let objectIDs = result?.result as? [NSManagedObjectID] {
                        let changes = [NSDeletedObjectsKey: objectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                    }
                } catch {
                    print("Error deleting expenses: \(error.localizedDescription)")
                }
            } else {
                // Use regular delete for single expense
                for expense in expensesToDelete {
                    // Delete directly from Core Data using ID
                    let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
                    
                    do {
                        let results = try viewContext.fetch(fetchRequest)
                        for entity in results {
                            viewContext.delete(entity)
                        }
                        saveContext()
                    } catch {
                        print("Error deleting single expense: \(error.localizedDescription)")
                    }
                }
            }
            
            // Always reload data to update the UI
            loadExpenses()
        } catch {
            print("Error in deleteExpense: \(error.localizedDescription)")
            // Still try to reload in case of error
            loadExpenses()
        }
    }
    
    // A safer way to delete expenses directly by ID without relying on array indices
    func deleteExpenseById(_ id: UUID) {
        // Create a fetch request to find the expense entity by ID
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            // Get the expense entities with the matching ID
            let results = try viewContext.fetch(fetchRequest)
            
            // Delete each matching entity (should be at most one)
            for entity in results {
                viewContext.delete(entity)
            }
            
            // Save context and reload expenses
            saveContext()
            loadExpenses()
            
            print("Successfully deleted expense with ID: \(id)")
        } catch {
            print("Error deleting expense by ID: \(error.localizedDescription)")
        }
    }
    
    func totalExpenses(for category: Expense.Category? = nil) -> Double {
        let expensesToSum = category == nil ? 
            filteredExpenses : 
            filteredExpenses.filter { $0.category == category }
        
        let total = expensesToSum.reduce(0) { result, expense in
            // Safety check for each expense amount
            guard expense.amount.isFinite else {
                print("Warning: Invalid expense amount detected: \(expense.amount) for expense: \(expense.title)")
                return result
            }
            return result + expense.amount
        }
        
        // Final safety check for the total
        return total.isFinite ? total : 0.0
    }
    
    private func filterExpenses(_ expenses: [Expense], category: Expense.Category?, timeFrame: TimeFrame) -> [Expense] {
        // Use safe copy of expenses to avoid any concurrent modification issues
        let safeExpenses = expenses
        var filtered = safeExpenses
        
        do {
            // Apply category filter if selected
            if let category = category {
                if category == .custom {
                    // For custom category, also check the customCategoryId
                    if let customCategoryId = selectedCustomCategoryId {
                        print("Filtering for custom category with ID: \(customCategoryId)")
                        
                        // Make sure we're only looking at expenses with the exact matching customCategoryId
                        filtered = filtered.filter { expense in
                            if expense.category == .custom, let expenseCategoryId = expense.customCategoryId {
                                return expenseCategoryId == customCategoryId
                            }
                            return false
                        }
                    } else {
                        // If no specific custom category is selected, show all custom categories
                        filtered = filtered.filter { $0.category == .custom }
                    }
                } else {
                    // For standard categories
                    filtered = filtered.filter { $0.category == category }
                }
            }
            
            // Apply time frame filter
            let (startDate, _) = timeFrame.dateRange
            if timeFrame != .all {
                filtered = filtered.filter { $0.date >= startDate }
            }
            
            // Sort by date (newest first)
            return filtered.sorted { $0.date > $1.date }
        } catch {
            print("Error during expenses filtering: \(error.localizedDescription)")
            // In case of any error, return the original expenses sorted by date
            return safeExpenses.sorted { $0.date > $1.date }
        }
    }
    
    // Format amount with currency symbol and locale-specific formatting
    func formattedAmount(_ amount: Double) -> String {
        // Safety check for NaN or infinite values
        guard amount.isFinite else {
            print("Warning: Invalid amount detected: \(amount). Using 0.00 as fallback.")
            return "\(selectedCurrency.symbol)0.00"
        }
        
        // Ensure amount is non-negative
        let safeAmount = max(amount, 0.0)
        
        numberFormatter.numberStyle = .decimal
        let formatted = numberFormatter.string(from: NSNumber(value: safeAmount)) ?? "0.00"
        return "\(selectedCurrency.symbol)\(formatted)"
    }
    
    // Parse amount string to Double, handling locale-specific decimal separators
    func parseAmount(_ amountString: String) -> Double? {
        // Remove all currency symbols and whitespace
        let cleanedAmount = amountString.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If nothing left after cleaning, return nil
        if cleanedAmount.isEmpty {
            return nil
        }
        
        // First try parsing with current locale
        if let number = numberFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        // If that fails, try parsing with standard decimal point
        let standardFormatter = NumberFormatter()
        standardFormatter.decimalSeparator = "."
        if let number = standardFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        // If that fails, try parsing with comma
        let commaFormatter = NumberFormatter()
        commaFormatter.decimalSeparator = ","
        if let number = commaFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        return nil
    }
    
    // Currency symbol for formatting
    var currencySymbol: String {
        return selectedCurrency.symbol
    }
    
    // Update all expenses to use the current selected currency
    private func updateAllExpensesToCurrentCurrency() {
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
    
    // Update all subscriptions to use the current selected currency
    private func updateAllSubscriptionsToCurrentCurrency() {
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
                
                // Notify other parts of the app that subscription currencies have been updated
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
    
    // MARK: - Core Data Operations
    
    // Load expenses from Core Data
    private func loadExpenses() {
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
    
    // Public method to refresh data when app becomes active
    func refreshData() {
        loadExpenses()
        // Re-apply filters to ensure UI is up to date
        updateFilteredExpenses()
    }
    
    // Helper method to manually trigger filter updates
    private func updateFilteredExpenses() {
        filteredExpenses = filterExpenses(expenses, category: selectedCategory, timeFrame: selectedTimeFrame)
    }
    
    // Save context
    private func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                print("Error saving context: \(error.localizedDescription)")
            }
        }
    }
    
    // Helper function to check what data exists (for debugging/testing)
    func checkDataExists() -> String {
        var dataStatus: [String] = []
        
        // Check expenses
        let expenseCount = expenses.count
        dataStatus.append("Expenses: \(expenseCount)")
        
        // Check subscriptions
        let subscriptionCount = loadSubscriptionsForExport().count
        dataStatus.append("Subscriptions: \(subscriptionCount)")
        
        // Check custom categories
        let customCategoryCount = getCustomCategories().count
        dataStatus.append("Custom Categories: \(customCategoryCount)")
        
        // Check deleted default categories
        let deletedCategoryCount = getDeletedDefaultCategories().count
        dataStatus.append("Deleted Default Categories: \(deletedCategoryCount)")
        
        return dataStatus.joined(separator: ", ")
    }
    
    // Helper function to check currency consistency across the app
    func checkCurrencyConsistency() -> (isConsistent: Bool, report: String) {
        var report: [String] = []
        var allCurrenciesConsistent = true
        
        // Check expenses
        let expenseCurrencies = Set(expenses.map { $0.currency.rawValue })
        if expenseCurrencies.count > 1 {
            allCurrenciesConsistent = false
            report.append("⚠️ Expenses have mixed currencies: \(expenseCurrencies.joined(separator: ", "))")
        } else if expenseCurrencies.count == 1 {
            let expenseCurrency = expenseCurrencies.first!
            if expenseCurrency != selectedCurrency.rawValue {
                allCurrenciesConsistent = false
                report.append("⚠️ Expenses currency (\(expenseCurrency)) doesn't match selected currency (\(selectedCurrency.rawValue))")
            } else {
                report.append("✅ All \(expenses.count) expenses use \(expenseCurrency)")
            }
        }
        
        // Check subscriptions
        let subscriptions = loadSubscriptionsForExport()
        let subscriptionCurrencies = Set(subscriptions.map { $0.currency.rawValue })
        if subscriptionCurrencies.count > 1 {
            allCurrenciesConsistent = false
            report.append("⚠️ Subscriptions have mixed currencies: \(subscriptionCurrencies.joined(separator: ", "))")
        } else if subscriptionCurrencies.count == 1 {
            let subscriptionCurrency = subscriptionCurrencies.first!
            if subscriptionCurrency != selectedCurrency.rawValue {
                allCurrenciesConsistent = false
                report.append("⚠️ Subscriptions currency (\(subscriptionCurrency)) doesn't match selected currency (\(selectedCurrency.rawValue))")
            } else {
                report.append("✅ All \(subscriptions.count) subscriptions use \(subscriptionCurrency)")
            }
        }
        
        // Overall status
        if allCurrenciesConsistent {
            report.insert("✅ All currencies are consistent with selected currency: \(selectedCurrency.rawValue)", at: 0)
        } else {
            report.insert("❌ Currency inconsistency detected!", at: 0)
        }
        
        return (allCurrenciesConsistent, report.joined(separator: "\n"))
    }
    
    // Clear all data from the app
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
        UserDefaults.standard.removeObject(forKey: "deletedDefaultCategories")
        print("✅ Cleared deleted default categories list")
        
        // 5. Clear any other app settings that might contain user data
        // Note: We keep user preferences like currency, appearance mode, and user name
        // as these are settings, not data
        
        // 6. Save changes to Core Data
        if clearSuccessful {
            saveContext()
            
            // Notify other parts of the app that all data has been cleared
            NotificationCenter.default.post(name: .dataDidClear, object: nil)
            
            print("✅ All data cleared successfully!")
            print("📊 After clearing: \(checkDataExists())")
        } else {
            print("⚠️ Some data may not have been cleared completely")
            print("📊 After partial clear: \(checkDataExists())")
        }
    }
    
    // MARK: - Data Export
    
    // Export all app data to CSV
    func exportToCSV() -> URL? {
        let fileName = "CashLens_Data_\(formattedCurrentDate()).csv"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        var csvText = ""
        
        // 1. Export Expenses
        csvText += "=== EXPENSES ===\n"
        csvText += "\"ID\",\"Date\",\"Title\",\"Amount\",\"Currency\",\"Category\",\"CustomCategoryId\",\"Notes\"\n"
        
        for expense in expenses {
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
        let subscriptions = loadSubscriptionsForExport()
        csvText += "\n=== SUBSCRIPTIONS ===\n"
        csvText += "\"ID\",\"Name\",\"Amount\",\"Currency\",\"StartDate\",\"Frequency\",\"NextDueDate\",\"Category\",\"CustomCategoryId\",\"Notes\",\"IsActive\",\"ReminderEnabled\",\"ReminderDaysBefore\"\n"
        
        for subscription in subscriptions {
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
        let customCategories = getCustomCategories()
        csvText += "\n=== CUSTOM_CATEGORIES ===\n"
        csvText += "\"ID\",\"Name\",\"Icon\",\"ColorName\"\n"
        
        for category in customCategories {
            let id = category.id.uuidString
            let name = category.name.replacingOccurrences(of: "\"", with: "\"\"")
            let icon = category.icon
            let colorName = category.colorName
            
            let newLine = "\"\(id)\",\"\(name)\",\"\(icon)\",\"\(colorName)\"\n"
            csvText.append(newLine)
        }
        
        // 4. Export Deleted Default Categories
        let deletedCategories = getDeletedDefaultCategories()
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
    
    // Export all app data to JSON
    func exportToJSON() -> URL? {
        let fileName = "CashLens_Data_\(formattedCurrentDate()).json"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        // Collect all data
        let subscriptions = loadSubscriptionsForExport()
        let customCategories = getCustomCategories()
        let deletedCategories = Array(getDeletedDefaultCategories())
        
        // Create comprehensive data structure
        let exportData: [String: Any] = [
            "exportVersion": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "expenses": expenses.map { expense in
                [
                    "id": expense.id.uuidString,
                    "title": expense.title,
                    "amount": expense.amount,
                    "currency": expense.currency.rawValue,
                    "date": ISO8601DateFormatter().string(from: expense.date),
                    "category": expense.category.rawValue,
                    "customCategoryId": expense.customCategoryId?.uuidString as Any,
                    "notes": expense.notes as Any
                ]
            },
            "subscriptions": subscriptions.map { subscription in
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
            "customCategories": customCategories.map { category in
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
    
    // Helper function to load subscriptions for export without main actor issues
    func loadSubscriptionsForExport() -> [Subscription] {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
            NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
        ]
        
        do {
            let entities = try viewContext.fetch(fetchRequest)
            return entities.toSubscriptions()
        } catch {
            print("Error loading subscriptions for export: \(error.localizedDescription)")
            return []
        }
    }
    
    // Helper function to format current date for filenames
    private func formattedCurrentDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    
    // MARK: - Data Import
    
    func importData(_ importResult: ImportResult, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Early validation of import data
                print("Starting import: \(importResult.expenses.count) expenses, \(importResult.subscriptions.count) subscriptions, \(importResult.customCategories.count) custom categories")
                
                // Basic sanity check
                if importResult.expenses.isEmpty && importResult.subscriptions.isEmpty && importResult.customCategories.isEmpty {
                    DispatchQueue.main.async {
                        completion(false, "No valid data found in import file")
                    }
                    return
                }
                
                var importStats = ImportStats()
                
                print("Import phase 1: Importing custom categories...")
                // Import Custom Categories first (so they exist when importing expenses/subscriptions)
                for customCategory in importResult.customCategories {
                    // Check if category already exists
                    let categoryViewModel = CategoryViewModel(context: self.viewContext)
                    let existingCategories = categoryViewModel.customCategories
                    
                    if !existingCategories.contains(where: { $0.id == customCategory.id }) {
                        categoryViewModel.addCustomCategory(customCategory)
                        importStats.customCategoriesImported += 1
                    } else {
                        importStats.customCategoriesSkipped += 1
                    }
                }
                
                print("Import phase 2: Importing \(importResult.expenses.count) expenses...")
                // Import Expenses
                var processedExpenses = 0
                for expense in importResult.expenses {
                    processedExpenses += 1
                    if processedExpenses % 50 == 0 {
                        print("Processed \(processedExpenses)/\(importResult.expenses.count) expenses...")
                    }
                    
                    // Validate expense data before processing
                    guard self.validateExpenseData(expense) else {
                        print("Warning: Skipping invalid expense: \(expense.title) with amount: \(expense.amount)")
                        importStats.expensesSkipped += 1
                        continue
                    }
                    
                    // First check if expense already exists by ID
                    let fetchByIdRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    
                    do {
                        fetchByIdRequest.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
                        let existingById = try self.viewContext.fetch(fetchByIdRequest)
                        
                        if !existingById.isEmpty {
                            importStats.expensesSkipped += 1
                            importStats.expensesSkippedById += 1
                            continue
                        }
                    } catch {
                        print("Error checking expense by ID \(expense.id): \(error.localizedDescription)")
                        // Skip this expense if ID check fails
                        importStats.expensesSkipped += 1
                        continue
                    }
                    
                    // If not found by ID, check for content-based duplicates
                    // (same title, amount, date, and category)
                    let fetchByContentRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    
                    // Additional safety checks before creating NSPredicate
                    guard !expense.title.isEmpty,
                          expense.amount.isFinite,
                          !expense.category.rawValue.isEmpty else {
                        print("Warning: Skipping expense with invalid data for predicate: \(expense.title)")
                        importStats.expensesSkipped += 1
                        continue
                    }
                    
                    // Create predicate safely with validated data
                    do {
                        fetchByContentRequest.predicate = NSPredicate(
                            format: "title == %@ AND amount == %@ AND date == %@ AND category == %@",
                            expense.title as NSString,
                            NSNumber(value: expense.amount),
                            expense.date as NSDate,
                            expense.category.rawValue as NSString
                        )
                        
                        let existingByContent = try self.viewContext.fetch(fetchByContentRequest)
                        
                        if existingByContent.isEmpty {
                            _ = ExpenseEntity.fromExpense(expense, context: self.viewContext)
                            importStats.expensesImported += 1
                        } else {
                            importStats.expensesSkipped += 1
                            importStats.expensesSkippedByContent += 1
                        }
                    } catch {
                        print("Error checking for duplicate expense: \(error.localizedDescription)")
                        // Skip this expense on predicate/fetch error
                        importStats.expensesSkipped += 1
                        continue
                    }
                }
                
                print("Import phase 3: Importing \(importResult.subscriptions.count) subscriptions...")
                // Import Subscriptions
                for subscription in importResult.subscriptions {
                    // Check if subscription already exists
                    let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                    
                    do {
                        fetchRequest.predicate = NSPredicate(format: "id == %@", subscription.id as CVarArg)
                        let existingSubscriptions = try self.viewContext.fetch(fetchRequest)
                        
                        if existingSubscriptions.isEmpty {
                            _ = SubscriptionEntity.fromSubscription(subscription, context: self.viewContext)
                            importStats.subscriptionsImported += 1
                        } else {
                            importStats.subscriptionsSkipped += 1
                        }
                    } catch {
                        print("Error checking subscription by ID \(subscription.id): \(error.localizedDescription)")
                        // Skip this subscription if ID check fails
                        importStats.subscriptionsSkipped += 1
                        continue
                    }
                }
                
                print("Import phase 4: Importing deleted categories...")
                // Import Deleted Default Categories
                if !importResult.deletedDefaultCategories.isEmpty {
                    let currentDeleted = self.getDeletedDefaultCategories()
                    let newDeleted = Set(importResult.deletedDefaultCategories)
                    let combinedDeleted = currentDeleted.union(newDeleted)
                    
                    UserDefaults.standard.set(Array(combinedDeleted), forKey: "deletedDefaultCategories")
                    importStats.deletedCategoriesImported = newDeleted.subtracting(currentDeleted).count
                }
                
                print("Import phase 5: Saving to Core Data...")
                // Save all changes with error handling
                do {
                    if self.viewContext.hasChanges {
                        try self.viewContext.save()
                        print("Successfully saved import changes to Core Data")
                    } else {
                        print("No changes to save to Core Data")
                    }
                } catch {
                    print("Error saving import changes: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false, "Failed to save imported data: \(error.localizedDescription)")
                    }
                    return
                }
                
                print("Import complete! Reloading data...")
                // Reload data on main thread
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
    
    // Helper struct to track import statistics
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
    
    // MARK: - Category Helpers
    
    // Get custom categories
    func getCustomCategories() -> [CustomCategory] {
        let categoryViewModel = CategoryViewModel(context: viewContext)
        // Always load fresh data to ensure we have the latest categories
        categoryViewModel.loadCustomCategories()
        return categoryViewModel.customCategories
    }
    
    // Get available default categories (excluding deleted ones)
    func getAvailableDefaultCategories() -> [Expense.Category] {
        let deletedCategories = getDeletedDefaultCategories()
        return Expense.Category.allCases.filter { category in
            category != .custom && !deletedCategories.contains(category.rawValue)
        }
    }
    
    // Get deleted default categories from UserDefaults
    func getDeletedDefaultCategories() -> Set<String> {
        if let deleted = UserDefaults.standard.array(forKey: "deletedDefaultCategories") as? [String] {
            return Set(deleted)
        }
        return []
    }
    
    // Move expenses from a deleted category to "Other"
    func moveExpensesFromDeletedCategory(_ categoryName: String) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "category == %@", categoryName)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                entity.category = Expense.Category.other.rawValue
            }
            
            if !results.isEmpty {
                saveContext()
                loadExpenses()
                print("Moved \(results.count) expenses from \(categoryName) to Other")
            }
        } catch {
            print("Error moving expenses from deleted category: \(error.localizedDescription)")
        }
    }
    
    // Get display name for a category (handles custom categories)
    func categoryDisplayName(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            // Get ALL custom categories and then find by ID to ensure consistency
            let customCategories = getCustomCategories()
            if let category = customCategories.first(where: { $0.id == customCategoryId }) {
                return category.name
            }
            return "Custom"
        }
        return expense.category.rawValue
    }
    
    // Get icon for a category (handles custom categories)
    func categoryIcon(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            // Get ALL custom categories and then find by ID to ensure consistency
            let customCategories = getCustomCategories()
            if let category = customCategories.first(where: { $0.id == customCategoryId }) {
                return category.icon
            }
            return "tag.fill"
        }
        return expense.category.icon
    }
    
    // Get color for a category (handles custom categories)
    func categoryColor(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            // Get ALL custom categories and then find by ID to ensure consistency
            let customCategories = getCustomCategories()
            if let category = customCategories.first(where: { $0.id == customCategoryId }) {
                return category.colorName
            }
            return "appPrimary"
        }
        return expense.category.color
    }
    
    // Validate expense data before processing
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
    
    func loadSummaryPreferences() {
        if let data = UserDefaults.standard.data(forKey: summaryPreferencesKey),
           let categories = try? JSONDecoder().decode([String].self, from: data) {
            preferredSummaryCategories = categories.compactMap { Expense.Category(rawValue: $0) }
        } else {
            // Set default categories if none are saved
            preferredSummaryCategories = getDefaultSummaryCategories()
            saveSummaryPreferences()
        }
    }
    
    func saveSummaryPreferences() {
        let categoryStrings = preferredSummaryCategories.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(categoryStrings) {
            UserDefaults.standard.set(data, forKey: summaryPreferencesKey)
        }
    }
    
    func updateSummaryCategories(_ categories: [Expense.Category]) {
        preferredSummaryCategories = categories
        saveSummaryPreferences()
    }
    
    func getDefaultSummaryCategories() -> [Expense.Category] {
        return [.food, .shopping, .transportation, .entertainment]
    }
    
    func getSummaryCardsData() -> [(category: Expense.Category?, title: String, amount: Double, icon: String, color: Color)] {
        var cardsData: [(category: Expense.Category?, title: String, amount: Double, icon: String, color: Color)] = []
        
        // Always include total expenses as first card
        cardsData.append((
            category: nil,
            title: "Total Expenses",
            amount: totalExpenses(),
            icon: "creditcard.fill",
            color: .appPrimary
        ))
        
        // Add user-selected categories (limit to 3 more to keep 4 total)
        for category in preferredSummaryCategories.prefix(3) {
            cardsData.append((
                category: category,
                title: category.displayName,
                amount: totalExpenses(for: category),
                icon: category.icon,
                color: Color.forCategory(category.color)
            ))
        }
        
        return cardsData
    }
} 