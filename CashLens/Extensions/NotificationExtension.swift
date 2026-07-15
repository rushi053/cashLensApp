import Foundation

extension Notification.Name {
    static let appearanceDidChange = Notification.Name("appearanceDidChange")
    static let dataDidClear = Notification.Name("dataDidClear")
    static let subscriptionCurrencyUpdated = Notification.Name("subscriptionCurrencyUpdated")
    /// Posted on the main actor whenever the user picks a new currency in
    /// Settings or `CurrencyPickerView`. Subscribers (e.g. `StatisticsView`)
    /// listen to this to flush any baked-in formatted-string caches —
    /// like `cachedInsights`, which embeds the formatter output at compute
    /// time and otherwise lingers on the previous symbol.
    static let currencyDidChange = Notification.Name("currencyDidChange")
    /// Posted whenever a backup operation writes one of the
    /// "last backup at / size / format" UserDefaults keys (or wipes
    /// them on a clear-all). `ProfileView` listens to this to
    /// refresh the "Last backup" footer in Settings without having
    /// to react to **every** UserDefaults write app-wide (which used
    /// to fire on currency / theme / draft autosave / smart-insight
    /// history / digest scheduling — none of which affect backup
    /// metadata).
    static let backupMetadataDidChange = Notification.Name("backupMetadataDidChange")

    /// Posted (on the main queue) after a headless write path —
    /// Siri/Shortcuts App Intents via `QuickLogService`, or the widget
    /// pending-queue drain — inserts expenses directly into the store
    /// on a background context. A live `ExpenseViewModel` observes this
    /// and re-runs its diff-gated `loadExpensesAsync()` so the
    /// in-memory array reconciles without a full-table thrash. Harmless
    /// when the scene isn't alive (nobody is subscribed).
    static let expensesChangedExternally = Notification.Name("expensesChangedExternally")

    /// Posted (on the main actor) by `AppLockManager` right after a
    /// successful unlock. Subscribers use it to release work that was
    /// deliberately deferred while the lock screen was up — e.g.
    /// `DeepLinkRouter` flushing a notification/widget route so its
    /// sheet can't present *above* the lock overlay.
    static let appDidUnlock = Notification.Name("appDidUnlock")

    /// Posted by Today when the user taps a header arrow that should
    /// jump to Insights with a specific window preselected (e.g. the
    /// "This week" header). The `object` carries the desired
    /// `ExpenseViewModel.TimeFrame`. `StatisticsView` listens and
    /// applies the new timeframe **before** the tab switch animates
    /// in, so the user lands on the right view without a flash of
    /// the previous selection.
    static let insightsRequestTimeFrame = Notification.Name("insightsRequestTimeFrame")
} 