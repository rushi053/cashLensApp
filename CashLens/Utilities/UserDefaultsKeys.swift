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
    /// Legacy (pre-2.0): permanent "never ask again" flag. Read once for
    /// migration in `FeedbackManager`, never written anymore.
    static let hasRequestedFeedback = "hasRequestedFeedback"
    static let successfulActionsCount = "successfulActionsCount"
    static let lastFeedbackAttempt = "lastFeedbackAttempt"
    static let feedbackPromptCount = "feedbackPromptCount"
    static let feedbackUsageDayCount = "feedbackUsageDayCount"
    static let feedbackLastUsageDay = "feedbackLastUsageDay"
    static let feedbackLegacyMigrated = "feedbackLegacyMigrated"
    
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

    /// Fingerprint (settings + next fire dates + data shape) of the last
    /// completed `refreshScheduledNotificationsIfNeeded` pass. When the
    /// fingerprint is unchanged the whole reschedule — including the
    /// full-array digest recomputes — is skipped on foreground.
    static let scheduledNotificationsFingerprint = "scheduledNotificationsFingerprint"

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
    
    // MARK: - Today verdict haptics
    /// Start-of-day timestamp of the last "budget turned Tight/Over"
    /// warning haptic. The design review's haptic map calls for one
    /// contextual `.warning` the moment Today first renders a worse
    /// verdict pill — once per day, never a repeat buzz on every
    /// recompute.
    static let verdictWarningLastDate = "verdictWarningLastDate"

    // MARK: - Today screen layout
    /// Ordered raw values of `TodaySectionID` — the user's preferred
    /// section order below the pinned verdict card. Written by
    /// `TodayCustomizeView`; absent → default order.
    static let todaySectionOrder = "today.sectionOrder"
    /// Raw values of `TodaySectionID` the user has hidden from Today.
    /// Absent → nothing hidden.
    static let todayHiddenSections = "today.hiddenSections"

    // MARK: - Monthly Recap
    /// "yyyy-MM" key of the last recap month the user actually opened
    /// (written by `MonthlyRecapSheet.onAppear`). Today's automatic
    /// "Your June recap is ready" card shows during the first few days
    /// of a new month only while this differs from the previous month's
    /// key — viewing the recap from either entry point dismisses it.
    static let monthlyRecapLastSeenMonth = "monthlyRecapLastSeenMonth"

    // MARK: - Backup Tracking
    static let lastBackupDate = "lastBackupDate"
    static let lastBackupFormat = "lastBackupFormat"
    static let totalBackupCount = "totalBackupCount"
    
    // MARK: - Pro
    static let hasSeenPaywall = "hasSeenPaywall"
    static let paywallImpressionCount = "paywallImpressionCount"
    /// True once the post-value paywall has been auto-presented (the
    /// "you just logged your 10th expense" trigger). Once-ever.
    static let hasAutoShownPaywall = "hasAutoShownPaywall"
    /// Date of the last automatic paywall presentation. Guarantees at
    /// most one auto-show per week even if the once-ever rule changes.
    static let lastAutoPaywallDate = "lastAutoPaywallDate"

    // MARK: - Donor grandfathering
    /// Grant type applied for past donors: `founder` ($4.99+ tier,
    /// permanent Pro) or `year` (smaller tier, 1 year of Pro from the
    /// grant date). Absent = no grant.
    static let donorGrantType = "donorGrantType"
    /// Date the donor grant was first applied. Anchor for the 1-year
    /// expiry; written once and never refreshed so an expired grant is
    /// never silently re-granted.
    static let donorGrantDate = "donorGrantDate"
    /// True once the one-time donor thank-you has been shown.
    static let donorGrantThanksShown = "donorGrantThanksShown"

    // MARK: - Pro lapse / win-back
    /// Last observed value of `ProManager.isPro`, persisted across
    /// launches so a Pro → free transition can be detected on launch.
    static let lastKnownIsPro = "lastKnownIsPro"
    /// Set when a Pro → free lapse is detected; cleared when the
    /// win-back sheet is shown (one show per lapse).
    static let winBackPending = "winBackPending"
    /// True once the user tapped "No thanks" on the win-back sheet —
    /// never show it again.
    static let winBackDeclined = "winBackDeclined"

    // MARK: - App Lock (free — privacy is not a paywall)
    /// User opt-in for the Face ID / Touch ID / passcode app lock.
    static let appLockEnabled = "appLockEnabled"
    /// Grace window in seconds (0 = immediately) before a backgrounded
    /// app requires re-authentication. Raw value of
    /// `AppLockManager.GracePeriod`.
    static let appLockGraceSeconds = "appLockGraceSeconds"
    /// Timestamp of the last real backgrounding. Persisted (not held in
    /// memory) so the grace window also applies across a terminate-and-
    /// relaunch inside the window.
    static let appLockLastBackgroundedAt = "appLockLastBackgroundedAt"

    // MARK: - Personalization (Pro)
    /// Active accent theme id (`AppTheme.id`). Defaults to `mauve` (current
    /// CashLens brand color) when missing so existing users see no change.
    static let activeThemeId = "activeThemeId"
    /// Active alternate app icon id. `nil` means the primary `AppIcon` is
    /// in use. Tracked separately from the system's `alternateIconName` so
    /// the picker can highlight the user's choice without a UIKit round-trip.
    static let activeAppIconId = "activeAppIconId"
}


