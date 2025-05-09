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
    private let viewContext: NSManagedObjectContext
    
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
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        
        // Load user preferences from UserDefaults
        loadUserPreferences()
        
        // Auto-select currency based on locale if not set
        autoSelectCurrencyIfNeeded()
        
        // Check if this is the first launch
        checkFirstLaunch()
        
        // Load saved expenses from Core Data
        loadExpenses()
        
        // Set up filtering
        setupFiltering()
    }
    
    // Load user preferences from UserDefaults
    private func loadUserPreferences() {
        if let savedName = UserDefaults.standard.string(forKey: "userName") {
            userName = savedName
        }
        
        if let savedCurrency = UserDefaults.standard.string(forKey: "selectedCurrency"),
           let currency = Expense.Currency(rawValue: savedCurrency) {
            selectedCurrency = currency
        }
        
        if let savedAppearance = UserDefaults.standard.string(forKey: "appearanceMode"),
           let appearance = AppearanceMode(rawValue: savedAppearance) {
            appearanceMode = appearance
        }
        
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
        return expensesToSum.reduce(0) { $0 + $1.amount }
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
        numberFormatter.numberStyle = .decimal
        let formatted = numberFormatter.string(from: NSNumber(value: amount)) ?? "0.00"
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
    
    // Clear all expenses data
    func clearAllData() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = ExpenseEntity.fetchRequest()
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        
        do {
            let result = try viewContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
            
            expenses = []
        } catch {
            print("Error clearing expenses: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Export
    
    // Export expenses to CSV
    func exportToCSV() -> URL? {
        let fileName = "CashLens_Expenses_\(formattedCurrentDate()).csv"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        // Create CSV header
        var csvText = "\"Date\",\"Title\",\"Amount\",\"Currency\",\"Category\",\"Notes\"\n"
        
        // Add expense data
        for expense in expenses {
            let date = dateFormatter.string(from: expense.date)
            let title = expense.title.replacingOccurrences(of: "\"", with: "\"\"")
            let amount = String(format: "%.2f", expense.amount)
            let currency = expense.currency.rawValue
            let category = expense.category.rawValue
            let notes = expense.notes?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            
            let newLine = "\"\(date)\",\"\(title)\",\"\(amount)\",\"\(currency)\",\"\(category)\",\"\(notes)\"\n"
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
    
    // Export expenses to JSON
    func exportToJSON() -> URL? {
        let fileName = "CashLens_Expenses_\(formattedCurrentDate()).json"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        do {
            let jsonData = try JSONEncoder().encode(expenses)
            try jsonData.write(to: path)
            return path
        } catch {
            print("Failed to create JSON file: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Helper function to format current date for filenames
    private func formattedCurrentDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    
    // MARK: - Category Helpers
    
    // Get custom categories
    func getCustomCategories() -> [CustomCategory] {
        let categoryViewModel = CategoryViewModel(context: viewContext)
        // Always load fresh data to ensure we have the latest categories
        categoryViewModel.loadCustomCategories()
        return categoryViewModel.customCategories
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
} 