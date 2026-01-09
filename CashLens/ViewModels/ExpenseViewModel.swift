import Foundation
import SwiftUI
import Combine
import CoreData

class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var filteredExpenses: [Expense] = []
    @Published var selectedCategory: Expense.Category?
    @Published var selectedCustomCategoryId: UUID?
    @Published var selectedTimeFrame: TimeFrame = .all {
        didSet {
            UserDefaults.standard.set(selectedTimeFrame.rawValue, forKey: UserDefaultsKeys.selectedTimeFrame)
        }
    }
    
    /// Controls what Home should default to on launch (when no explicit last selection is stored).
    @Published var defaultHomeTimeFrame: TimeFrame = .month {
        didSet {
            UserDefaults.standard.set(defaultHomeTimeFrame.rawValue, forKey: UserDefaultsKeys.defaultHomeTimeFrame)
        }
    }
    @Published var selectedCurrency: Expense.Currency = .usd {
        didSet {
            if oldValue != selectedCurrency {
                updateAllExpensesToCurrentCurrency()
                updateAllSubscriptionsToCurrentCurrency()
            }
            UserDefaults.standard.set(selectedCurrency.rawValue, forKey: UserDefaultsKeys.selectedCurrency)
        }
    }
    @Published var userName: String = "CashLens User" {
        didSet {
            UserDefaults.standard.set(userName, forKey: UserDefaultsKeys.userName)
        }
    }
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: UserDefaultsKeys.appearanceMode)
            
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
        
        /// Returns a half-open date interval: \([start, end)\).
        /// `referenceDate` controls "which" day/week/month/year we mean (enables browsing history).
        func dateRange(referenceDate: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
            switch self {
            case .day:
                let start = calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? referenceDate
                return (start, end)
            case .week:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)) ?? calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? referenceDate
                return (start, end)
            case .month:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? referenceDate
                return (start, end)
            case .year:
                let start = calendar.date(from: calendar.dateComponents([.year], from: referenceDate)) ?? calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .year, value: 1, to: start) ?? referenceDate
                return (start, end)
            case .all:
                return (Date.distantPast, referenceDate)
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
    @AppStorage(UserDefaultsKeys.hasShownCurrencyPicker) var hasShownCurrencyPicker: Bool = false
    
    // Number formatter for consistent formatting across the app
    // Note: needs to be accessible from split extension files.
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    // MARK: - Summary Cards Customization
    
    /// Stored as tokens for backwards compatibility:
    /// - Default categories are stored as their `Expense.Category.rawValue` (e.g. "Food")
    /// - Custom categories are stored as `"custom:<uuid>"`
    @Published var preferredSummaryCategoryTokens: [String] = []
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        
        // Load saved preferences
        loadUserName()
        loadSelectedCurrency()
        loadDefaultHomeTimeFrame()
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
        if let savedCurrency = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedCurrency),
           let currency = Expense.Currency(rawValue: savedCurrency) {
            selectedCurrency = currency
        }
    }
    
    private func loadUserName() {
        if let savedName = UserDefaults.standard.string(forKey: UserDefaultsKeys.userName) {
            let trimmed = savedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                userName = trimmed
            }
        }
    }
    
    private func loadSelectedTimeFrame() {
        if let savedTimeFrame = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedTimeFrame),
           let timeFrame = TimeFrame(rawValue: savedTimeFrame) {
            selectedTimeFrame = timeFrame
        } else {
            // First launch (or after reset): respect the configured default instead of showing All Time.
            selectedTimeFrame = defaultHomeTimeFrame
        }
    }
    
    private func loadDefaultHomeTimeFrame() {
        if let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.defaultHomeTimeFrame),
           let timeFrame = TimeFrame(rawValue: saved) {
            defaultHomeTimeFrame = timeFrame
        } else {
            // Sensible default for most users
            defaultHomeTimeFrame = .month
        }
    }
    
    private func loadAppearanceMode() {
        if let savedAppearance = UserDefaults.standard.string(forKey: UserDefaultsKeys.appearanceMode),
           let appearance = AppearanceMode(rawValue: savedAppearance) {
            appearanceMode = appearance
        }
    }
    
    // Legacy method kept for compatibility - now delegates to individual methods
    private func loadUserPreferences() {
        if let savedName = UserDefaults.standard.string(forKey: UserDefaultsKeys.userName) {
            userName = savedName
        }
        
        loadSelectedCurrency()
        loadAppearanceMode()
        
        hasShownCurrencyPicker = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasShownCurrencyPicker)
    }
    
    // Auto-select currency based on user's locale if not already set
    private func autoSelectCurrencyIfNeeded() {
        if UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedCurrency) == nil {
            let locale = Locale.current
            if let currencyCode = locale.currencyCode,
               let currency = Expense.Currency(rawValue: currencyCode.uppercased()) {
                selectedCurrency = currency
            }
        }
    }
    
    // Check if this is the first launch
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasLaunchedBefore)
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasLaunchedBefore)
            hasShownCurrencyPicker = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
        }
    }
    
    // Set up filtering
    private func setupFiltering() {
        Publishers.CombineLatest4($expenses, $selectedCategory, $selectedCustomCategoryId, $selectedTimeFrame)
            .map { [weak self] expenses, category, customCategoryId, timeFrame in
                self?.filterExpenses(expenses, category: category, customCategoryId: customCategoryId, timeFrame: timeFrame) ?? []
            }
            .assign(to: \.filteredExpenses, on: self)
            .store(in: &cancellables)
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
    
    func totalExpenses(forCustomCategoryId customCategoryId: UUID) -> Double {
        let expensesToSum = filteredExpenses.filter {
            $0.category == .custom && $0.customCategoryId == customCategoryId
        }
        
        let total = expensesToSum.reduce(0) { result, expense in
            guard expense.amount.isFinite else {
                print("Warning: Invalid expense amount detected: \(expense.amount) for expense: \(expense.title)")
                return result
            }
            return result + expense.amount
        }
        
        return total.isFinite ? total : 0.0
    }
    
    
    func filterExpenses(_ expenses: [Expense], category: Expense.Category?, customCategoryId: UUID?, timeFrame: TimeFrame) -> [Expense] {
        ExpenseFilter.apply(
            expenses: expenses,
            category: category,
            customCategoryId: customCategoryId,
            timeFrame: timeFrame,
            referenceDate: Date()
        )
    }
    
    // Currency symbol for formatting
    var currencySymbol: String {
        return selectedCurrency.symbol
    }
    
    
    func getSummaryCardsData(customCategories: [CustomCategory]? = nil) -> [(category: Expense.Category?, customCategoryId: UUID?, title: String, amount: Double, icon: String, color: Color)] {
        var cardsData: [(category: Expense.Category?, customCategoryId: UUID?, title: String, amount: Double, icon: String, color: Color)] = []
        
        let totalAmount = totalExpenses()
        
        // Always include total expenses as first card
        cardsData.append((
            category: nil,
            customCategoryId: nil,
            title: "Total Expenses",
            amount: totalAmount,
            icon: "creditcard.fill",
            color: .appPrimary
        ))
        
        // Add user-selected categories (limit to 3 more to keep 4 total)
        let customCategories = customCategories ?? getCustomCategories()
        for token in preferredSummaryCategoryTokens.prefix(3) {
            if token.lowercased().hasPrefix("custom:") {
                let idString = String(token.dropFirst("custom:".count))
                guard let customId = UUID(uuidString: idString),
                      let custom = customCategories.first(where: { $0.id == customId }) else {
                    continue
                }
                
                let amount = totalExpenses(forCustomCategoryId: customId)
                
                cardsData.append((
                    category: .custom,
                    customCategoryId: customId,
                    title: custom.name,
                    amount: amount,
                    icon: custom.icon,
                    color: Color.forCategory(custom.colorName)
                ))
            } else if let category = Expense.Category(rawValue: token), category != .custom {
                let amount = totalExpenses(for: category)
                
                cardsData.append((
                    category: category,
                    customCategoryId: nil,
                    title: category.displayName,
                    amount: amount,
                    icon: category.icon,
                    color: Color.forCategory(category.color)
                ))
            }
        }
        
        return cardsData
    }
} 
