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
} 