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
    
    // MARK: - Cached Totals (Performance Optimization)
    // These are updated asynchronously when filteredExpenses changes
    @Published private(set) var cachedTotalAmount: Double = 0
    @Published private(set) var cachedTotalsByCategory: [Expense.Category: Double] = [:]
    @Published private(set) var cachedTotalsByCustomId: [UUID: Double] = [:]
    @Published private(set) var cachedCountsByCategory: [Expense.Category: Int] = [:]
    @Published private(set) var cachedCountsByCustomId: [UUID: Int] = [:]
    @Published private(set) var isFilteringInProgress: Bool = false
    
    // Background task management for filtering
    private var filterTask: Task<Void, Never>?
    private var totalsTask: Task<Void, Never>?
    
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
    
    // MARK: - Filtering Setup (Performance Optimized)
    
    /// Set up filtering with debouncing and background processing for smooth UI
    private func setupFiltering() {
        Publishers.CombineLatest4($expenses, $selectedCategory, $selectedCustomCategoryId, $selectedTimeFrame)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main) // Batch rapid changes
            .sink { [weak self] expenses, category, customCategoryId, timeFrame in
                self?.scheduleFilterRecompute(
                    expenses: expenses,
                    category: category,
                    customCategoryId: customCategoryId,
                    timeFrame: timeFrame
                )
            }
            .store(in: &cancellables)
    }
    
    /// Schedule filter recomputation on background thread to keep UI responsive
    private func scheduleFilterRecompute(
        expenses: [Expense],
        category: Expense.Category?,
        customCategoryId: UUID?,
        timeFrame: TimeFrame
    ) {
        // Cancel any pending filter task
        filterTask?.cancel()
        isFilteringInProgress = true
        
        filterTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Small delay to batch very rapid changes (e.g., quick category taps)
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Perform filtering on background thread
            let result = await Task.detached(priority: .userInitiated) {
                ExpenseFilter.apply(
                    expenses: expenses,
                    category: category,
                    customCategoryId: customCategoryId,
                    timeFrame: timeFrame,
                    referenceDate: Date()
                )
            }.value
            
            // Check again if task was cancelled before updating
            guard !Task.isCancelled else { return }
            
            // Update on main thread
            self.filteredExpenses = result
            self.isFilteringInProgress = false
            
            // Update cached totals in background
            self.updateCachedTotals(for: result)
        }
    }
    
    /// Update cached totals asynchronously for O(1) access
    private func updateCachedTotals(for expenses: [Expense]) {
        totalsTask?.cancel()
        
        totalsTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Compute totals on background thread
            let (total, byCategory, byCustomId, countsByCategory, countsByCustomId) = await Task.detached(priority: .utility) {
                var total: Double = 0
                var byCategory: [Expense.Category: Double] = [:]
                var byCustomId: [UUID: Double] = [:]
                var countsByCategory: [Expense.Category: Int] = [:]
                var countsByCustomId: [UUID: Int] = [:]
                
                for expense in expenses {
                    guard expense.amount.isFinite else { continue }
                    
                    total += expense.amount
                    byCategory[expense.category, default: 0] += expense.amount
                    countsByCategory[expense.category, default: 0] += 1
                    
                    if expense.category == .custom, let customId = expense.customCategoryId {
                        byCustomId[customId, default: 0] += expense.amount
                        countsByCustomId[customId, default: 0] += 1
                    }
                }
                
                return (total, byCategory, byCustomId, countsByCategory, countsByCustomId)
            }.value
            
            guard !Task.isCancelled else { return }
            
            // Update cached values
            self.cachedTotalAmount = total.isFinite ? total : 0
            self.cachedTotalsByCategory = byCategory
            self.cachedTotalsByCustomId = byCustomId
            self.cachedCountsByCategory = countsByCategory
            self.cachedCountsByCustomId = countsByCustomId
        }
    }
    
    /// Get total expenses - uses cached value for O(1) performance
    /// - Parameter category: Optional category to filter by. If nil, returns total of all filtered expenses.
    /// - Returns: The total amount for the specified category or all expenses
    func totalExpenses(for category: Expense.Category? = nil) -> Double {
        // Use cached values for O(1) access
        if let category = category {
            return cachedTotalsByCategory[category, default: 0]
        }
        return cachedTotalAmount
    }
    
    /// Get total expenses for a custom category - uses cached value for O(1) performance
    /// - Parameter customCategoryId: The UUID of the custom category
    /// - Returns: The total amount for the specified custom category
    func totalExpenses(forCustomCategoryId customCategoryId: UUID) -> Double {
        return cachedTotalsByCustomId[customCategoryId, default: 0]
    }
    
    /// Get expense count for a category - uses cached value for O(1) performance
    func expenseCount(for category: Expense.Category) -> Int {
        return cachedCountsByCategory[category, default: 0]
    }
    
    /// Get expense count for a custom category - uses cached value for O(1) performance
    func expenseCount(forCustomCategoryId customCategoryId: UUID) -> Int {
        return cachedCountsByCustomId[customCategoryId, default: 0]
    }
    
    /// Force recalculate totals if needed (legacy compatibility)
    /// This is useful when you need immediate accurate totals without waiting for cache
    func calculateTotalExpenses(for category: Expense.Category? = nil) -> Double {
        let expensesToSum = category == nil ?
            filteredExpenses :
            filteredExpenses.filter { $0.category == category }
        
        let total = expensesToSum.reduce(0) { result, expense in
            guard expense.amount.isFinite else { return result }
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
        
        // Use cached total for O(1) access
        let totalAmount = cachedTotalAmount
        
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
                
                // Use cached value for O(1) access
                let amount = cachedTotalsByCustomId[customId, default: 0]
                
                cardsData.append((
                    category: .custom,
                    customCategoryId: customId,
                    title: custom.name,
                    amount: amount,
                    icon: custom.icon,
                    color: Color.forCategory(custom.colorName)
                ))
            } else if let category = Expense.Category(rawValue: token), category != .custom {
                // Use cached value for O(1) access
                let amount = cachedTotalsByCategory[category, default: 0]
                
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
