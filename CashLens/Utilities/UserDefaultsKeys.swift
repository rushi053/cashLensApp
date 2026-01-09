import Foundation

enum UserDefaultsKeys {
    // MARK: - Onboarding / First Launch
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let hasLaunchedBefore = "hasLaunchedBefore"
    static let hasShownCurrencyPicker = "hasShownCurrencyPicker"
    
    // MARK: - User Preferences
    static let selectedCurrency = "selectedCurrency"
    static let selectedTimeFrame = "selectedTimeFrame"
    static let defaultHomeTimeFrame = "defaultHomeTimeFrame"
    static let appearanceMode = "appearanceMode"
    static let userName = "userName"
    
    // MARK: - Summary Customization
    static let preferredSummaryCategories = "preferred_summary_categories"
    
    // MARK: - Categories
    static let deletedDefaultCategories = "deletedDefaultCategories"
    
    // MARK: - Drafts
    static let expenseDraft = "expense_draft"
    
    // MARK: - Feedback
    static let hasRequestedFeedback = "hasRequestedFeedback"
    static let successfulActionsCount = "successfulActionsCount"
    static let lastFeedbackAttempt = "lastFeedbackAttempt"
    
    // MARK: - Notifications
    static let weeklySummaryEnabled = "weeklySummaryEnabled"
    static let weeklySummaryWeekday = "weeklySummaryWeekday" // 1=Sunday...7=Saturday
    static let weeklySummaryHour = "weeklySummaryHour"
    static let weeklySummaryMinute = "weeklySummaryMinute"
    
    static let monthlyDigestEnabled = "monthlyDigestEnabled"
    static let monthlyDigestDayOfMonth = "monthlyDigestDayOfMonth" // 1...28
    static let monthlyDigestHour = "monthlyDigestHour"
    static let monthlyDigestMinute = "monthlyDigestMinute"
    
    static let backupReminderEnabled = "backupReminderEnabled"
    static let backupReminderDayOfMonth = "backupReminderDayOfMonth" // 1...28
    static let backupReminderHour = "backupReminderHour"
    static let backupReminderMinute = "backupReminderMinute"
}


