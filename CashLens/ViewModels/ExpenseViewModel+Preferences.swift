import Foundation

extension ExpenseViewModel {
    // MARK: - Preferences
    
    func loadSummaryPreferences() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.preferredSummaryCategories),
           let categories = try? JSONDecoder().decode([String].self, from: data) {
            // Backwards compatible:
            // - Default category tokens are their rawValue
            // - Custom category tokens are "custom:<uuid>"
            preferredSummaryCategoryTokens = categories
        } else {
            // Set default categories if none are saved
            preferredSummaryCategoryTokens = getDefaultSummaryCategories().map { $0.rawValue }
            saveSummaryPreferences()
        }
    }
    
    func saveSummaryPreferences() {
        if let data = try? JSONEncoder().encode(preferredSummaryCategoryTokens) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.preferredSummaryCategories)
        }
    }
    
    func updateSummaryCategoryTokens(_ tokens: [String]) {
        preferredSummaryCategoryTokens = tokens
        saveSummaryPreferences()
    }
    
    func getDefaultSummaryCategories() -> [Expense.Category] {
        return [.food, .shopping, .transportation, .entertainment]
    }
}


