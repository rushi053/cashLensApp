import Foundation

enum UserDefaultsKeys {
    // MARK: - Onboarding / First Launch
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let hasLaunchedBefore = "hasLaunchedBefore"
    static let hasShownCurrencyPicker = "hasShownCurrencyPicker"
    
    // MARK: - User Preferences
    static let selectedCurrency = "selectedCurrency"
    /// JSON-encoded `[String]` of the last few currency codes the user
    /// actively picked (most-recent-first, deduped, capped). Drives the
    /// "Recently Used" section in `CurrencyPickerView`.
    static let recentCurrencies = "recent_currencies_v1"
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

    // MARK: - Quick Search
    /// Persisted JSON-encoded `[String]` of the user's most recent search queries
    /// in `QuickSearchView`. Capped to 5; deduped; most-recent-first.
    static let quickSearchRecents = "quick_search_recents"
    
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

    // MARK: - Smart Insights (Pro)
    /// User opt-in for the weekly Smart Insights notification. Pro-gated.
    static let smartInsightsEnabled = "smartInsightsEnabled"
    /// `[String: Date]` JSON dictionary of insight fingerprint -> last fired
    /// date. Used by `SmartInsightsEngine` to suppress repeats within a
    /// rolling cooldown window so the user never gets the same headline
    /// twice in a row.
    static let smartInsightsHistory = "smartInsightsHistory"
    /// Last successful weekly fire date (any insight). Used as a "no insight
    /// found this week → don't pester the user" backoff anchor so we don't
    /// spam the scheduler when the inbox would otherwise be empty.
    static let smartInsightsLastFireDate = "smartInsightsLastFireDate"
    
    // MARK: - Backup Tracking
    static let lastBackupDate = "lastBackupDate"
    static let lastBackupFormat = "lastBackupFormat"
    static let totalBackupCount = "totalBackupCount"
    
    // MARK: - Pro
    static let hasSeenPaywall = "hasSeenPaywall"
    static let paywallImpressionCount = "paywallImpressionCount"

    // MARK: - Personalization (Pro)
    /// Active accent theme id (`AppTheme.id`). Defaults to `mauve` (current
    /// CashLens brand color) when missing so existing users see no change.
    static let activeThemeId = "activeThemeId"
    /// Active alternate app icon id. `nil` means the primary `AppIcon` is
    /// in use. Tracked separately from the system's `alternateIconName` so
    /// the picker can highlight the user's choice without a UIKit round-trip.
    static let activeAppIconId = "activeAppIconId"
}


