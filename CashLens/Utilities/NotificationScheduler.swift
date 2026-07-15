import Foundation
import UserNotifications
import SwiftUI
import CoreData

enum AppNotificationIdentifiers {
    // Legacy id (kept for cleanup)
    static let weeklySummary = "weekly_summary"
    
    static let weeklyDigest = "weekly_digest_next"
    static let monthlyDigest = "monthly_digest_next"
    static let backupReminder = "backup_reminder_next"
    /// Pro-only proactive Smart Insights weekly push. Re-scheduled on every
    /// app foreground so the body always reflects the freshest computed
    /// insight; when no insight clears the firing bar, no request is added.
    static let smartInsightWeekly = "smart_insight_weekly_next"
    /// One-shot reminder scheduled at trial-start purchase, fired 2 days
    /// before the trial converts. Backs the paywall timeline's "we send
    /// you a reminder" promise with a real notification.
    static let trialEndingReminder = "trial_ending_reminder"
}

struct NotificationScheduler {
    static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Public entrypoint used by the app on foregrounding
    
    /// Re-schedules next-occurrence notifications based on current user preferences.
    /// We intentionally schedule a single upcoming notification (not repeating) so the body can be refreshed with real data.
    ///
    /// `isPro` lets the scheduler gate Pro-only notifications (currently just
    /// the proactive Smart Insights push) without having to import StoreKit /
    /// reach into `ProManager` from a non-actor context.
    @MainActor
    static func refreshScheduledNotificationsIfNeeded(viewModel: ExpenseViewModel, isPro: Bool = false) async {
        let weeklyEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.weeklySummaryEnabled)
        let monthlyEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.monthlyDigestEnabled)
        let backupEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.backupReminderEnabled)
        let smartInsightsEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.smartInsightsEnabled)

        let weeklyWeekday = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklySummaryWeekday)
        let weeklyHour = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklySummaryHour)
        let weeklyMinute = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklySummaryMinute)
        let monthlyDay = UserDefaults.standard.integer(forKey: UserDefaultsKeys.monthlyDigestDayOfMonth)
        let monthlyHour = UserDefaults.standard.integer(forKey: UserDefaultsKeys.monthlyDigestHour)
        let monthlyMinute = UserDefaults.standard.integer(forKey: UserDefaultsKeys.monthlyDigestMinute)
        let backupDay = UserDefaults.standard.integer(forKey: UserDefaultsKeys.backupReminderDayOfMonth)
        let backupHour = UserDefaults.standard.integer(forKey: UserDefaultsKeys.backupReminderHour)
        let backupMinute = UserDefaults.standard.integer(forKey: UserDefaultsKeys.backupReminderMinute)

        // PERF: gate the whole pass on a fingerprint of everything the
        // scheduled content depends on. The "IfNeeded" previously only
        // checked the on/off toggles — when enabled, every foreground
        // recomputed digests over the **entire** expense array (weekly +
        // monthly + the smart-insight scan). The fingerprint covers the
        // data shape (count + newest date + currency), every schedule
        // setting, Pro state, and the concrete next fire dates — so once
        // a scheduled notification's slot passes, the fingerprint changes
        // and the pass runs again.
        let normalizedWeeklyWeekday = max(1, min(7, weeklyWeekday == 0 ? 2 : weeklyWeekday))
        var fingerprint = "v1"
        fingerprint += "|data:\(viewModel.expenses.count):\(viewModel.expenses.first?.date.timeIntervalSince1970 ?? 0):\(viewModel.selectedCurrency.rawValue)"
        fingerprint += "|pro:\(isPro)"
        if weeklyEnabled {
            let fire = nextWeeklyFireDate(weekday: normalizedWeeklyWeekday, hour: weeklyHour, minute: weeklyMinute)
            fingerprint += "|w:\(normalizedWeeklyWeekday):\(weeklyHour):\(weeklyMinute):\(fire.timeIntervalSince1970)"
        } else {
            fingerprint += "|w:off"
        }
        if monthlyEnabled {
            let fire = nextMonthlyFireDate(dayOfMonth: normalizeDayOfMonth(monthlyDay), hour: monthlyHour, minute: monthlyMinute)
            fingerprint += "|m:\(normalizeDayOfMonth(monthlyDay)):\(monthlyHour):\(monthlyMinute):\(fire.timeIntervalSince1970)"
        } else {
            fingerprint += "|m:off"
        }
        if backupEnabled {
            let fire = nextMonthlyFireDate(dayOfMonth: normalizeDayOfMonth(backupDay), hour: backupHour, minute: backupMinute)
            fingerprint += "|b:\(normalizeDayOfMonth(backupDay)):\(backupHour):\(backupMinute):\(fire.timeIntervalSince1970)"
        } else {
            fingerprint += "|b:off"
        }
        if smartInsightsEnabled && isPro {
            let fire = nextWeeklyFireDate(
                weekday: smartInsightDefaultWeekday,
                hour: smartInsightDefaultHour,
                minute: smartInsightDefaultMinute
            )
            fingerprint += "|s:\(fire.timeIntervalSince1970)"
        } else {
            fingerprint += "|s:off"
        }

        if fingerprint == UserDefaults.standard.string(forKey: UserDefaultsKeys.scheduledNotificationsFingerprint) {
            return
        }

        // Clean up legacy repeating id if any exists
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.weeklySummary])
        
        // Track success across the pass: the fingerprint may only be
        // recorded when every *enabled* schedule actually landed —
        // otherwise a failed pass (authorization revoked mid-session,
        // `add` error) would be remembered as done and never retried.
        var allSucceeded = true

        if weeklyEnabled {
            let ok = await scheduleNextWeeklyDigest(weekday: normalizedWeeklyWeekday, hour: weeklyHour, minute: weeklyMinute, viewModel: viewModel)
            allSucceeded = allSucceeded && ok
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.weeklyDigest])
        }
        
        if monthlyEnabled {
            let ok = await scheduleNextMonthlyDigest(dayOfMonth: normalizeDayOfMonth(monthlyDay), hour: monthlyHour, minute: monthlyMinute, viewModel: viewModel)
            allSucceeded = allSucceeded && ok
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.monthlyDigest])
        }
        
        if backupEnabled {
            let ok = await scheduleNextBackupReminder(dayOfMonth: normalizeDayOfMonth(backupDay), hour: backupHour, minute: backupMinute)
            allSucceeded = allSucceeded && ok
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.backupReminder])
        }

        // Smart Insights — only refresh when the user has opted in **and**
        // is currently Pro. We always cancel any pending request first so a
        // user who toggled the setting off (or downgraded) doesn't receive
        // a stale insight scheduled days earlier.
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [AppNotificationIdentifiers.smartInsightWeekly]
        )
        if smartInsightsEnabled && isPro {
            let ok = await scheduleNextSmartInsight(viewModel: viewModel)
            allSucceeded = allSucceeded && ok
        }

        // Record only after the pass ran to completion so a mid-pass
        // failure (e.g. authorization revoked) retries next foreground.
        guard allSucceeded else { return }
        UserDefaults.standard.set(fingerprint, forKey: UserDefaultsKeys.scheduledNotificationsFingerprint)
    }
    
    // NOTE: removed two dead legacy entry points here
    // (`cancelWeeklySummary` / `scheduleWeeklySummary`) — nothing
    // called them; the digest lifecycle runs entirely through
    // `refreshScheduledNotificationsIfNeeded`, which still cleans up
    // the legacy `weeklySummary` identifier on every pass.
    
    // MARK: - Category name lookup
    //
    // PERF: `viewModel.categoryDisplayName(for:)` does a **full Core
    // Data fetch on every call** (see `ExpenseViewModel+Categories`'s
    // `getCustomCategories()`). Passing the bound method straight into
    // `DigestStatsCalculator.compute` or `SmartInsightsEngine.Inputs`
    // meant we re-ran that fetch **once per expense** inside the digest
    // / insight loops — for 1,500 expenses on Pro that was 1,500+
    // synchronous Core Data fetches on the MainActor every foreground.
    //
    // This helper hits Core Data **once** to materialize a `[UUID :
    // String]` map and returns a fast lookup closure that does an
    // O(1) dictionary read per expense. The closure is Sendable
    // because the captured dictionary is a value type.
    @MainActor
    private static func makeCategoryNameLookup(viewModel: ExpenseViewModel) -> (Expense) -> String {
        let customCategoriesById: [UUID: String] = Dictionary(
            uniqueKeysWithValues: viewModel.getCustomCategories().map { ($0.id, $0.name) }
        )
        return { expense in
            if expense.category == .custom, let id = expense.customCategoryId {
                return customCategoriesById[id] ?? "Custom"
            }
            // displayName, not rawValue — the digest should say
            // "Food & Drinks", matching the label users see in-app.
            return expense.category.displayName
        }
    }

    // MARK: - Digest scheduling with computed stats
    
    static func scheduleNextWeeklyDigest(weekday: Int, hour: Int, minute: Int, viewModel: ExpenseViewModel) async -> Bool {
        let ok = await ensureAuthorized()
        guard ok else { return false }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.weeklyDigest])
        
        let nextFire = nextWeeklyFireDate(weekday: weekday, hour: hour, minute: minute)
        let interval = (start: nextFire.addingTimeInterval(-7 * 24 * 60 * 60), end: nextFire)
        let categoryNameLookup = await MainActor.run { Self.makeCategoryNameLookup(viewModel: viewModel) }
        let stats = DigestStatsCalculator.compute(expenses: viewModel.expenses, start: interval.start, end: interval.end, formattedAmount: viewModel.formattedAmount, categoryDisplayName: categoryNameLookup)
        
        let content = UNMutableNotificationContent()
        content.title = "Weekly Digest"
        content.body = stats.bodyText(prefix: "this week")
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKeys.route: NotificationRouteTypes.allExpenses,
            NotificationUserInfoKeys.rangeStart: interval.start.timeIntervalSince1970,
            NotificationUserInfoKeys.rangeEnd: interval.end.timeIntervalSince1970
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, nextFire.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: AppNotificationIdentifiers.weeklyDigest, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
    
    static func scheduleNextMonthlyDigest(dayOfMonth: Int, hour: Int, minute: Int, viewModel: ExpenseViewModel) async -> Bool {
        let ok = await ensureAuthorized()
        guard ok else { return false }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.monthlyDigest])
        
        let nextFire = nextMonthlyFireDate(dayOfMonth: dayOfMonth, hour: hour, minute: minute)
        // Use the previous calendar month ending at nextFire.
        let calendar = Calendar.current
        let anchor = calendar.date(byAdding: .day, value: -1, to: nextFire) ?? nextFire
        let monthInterval = calendar.dateInterval(of: .month, for: anchor)
        let start = monthInterval?.start ?? nextFire.addingTimeInterval(-30 * 24 * 60 * 60)
        let end = monthInterval?.end ?? nextFire
        
        let categoryNameLookup = await MainActor.run { Self.makeCategoryNameLookup(viewModel: viewModel) }
        let stats = DigestStatsCalculator.compute(expenses: viewModel.expenses, start: start, end: end, formattedAmount: viewModel.formattedAmount, categoryDisplayName: categoryNameLookup)
        
        let content = UNMutableNotificationContent()
        content.title = "Monthly Digest"
        content.body = stats.bodyText(prefix: "this month")
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKeys.route: NotificationRouteTypes.allExpenses,
            NotificationUserInfoKeys.rangeStart: start.timeIntervalSince1970,
            NotificationUserInfoKeys.rangeEnd: end.timeIntervalSince1970
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, nextFire.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: AppNotificationIdentifiers.monthlyDigest, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
    
    static func scheduleNextBackupReminder(dayOfMonth: Int, hour: Int, minute: Int) async -> Bool {
        let ok = await ensureAuthorized()
        guard ok else { return false }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.backupReminder])
        
        let nextFire = nextMonthlyFireDate(dayOfMonth: dayOfMonth, hour: hour, minute: minute)
        let content = UNMutableNotificationContent()
        content.title = "Backup Reminder"
        content.body = "Export your CashLens data to Files in one tap."
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKeys.route: NotificationRouteTypes.export
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, nextFire.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: AppNotificationIdentifiers.backupReminder, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Trial ending reminder

    /// Schedules the one-shot "your trial ends soon" reminder promised
    /// by the paywall's trial timeline. Called immediately after a
    /// trial-starting purchase succeeds; fires 2 days before the trial
    /// converts (for a 7-day trial: day 5). If notification permission
    /// is denied we simply can't deliver — nothing else to do.
    ///
    /// The body restates the exact upcoming charge so the reminder is
    /// useful on its own, and stays truthful for users who already
    /// cancelled (Apple keeps the trial active until its end date).
    static func scheduleTrialEndingReminder(trialDays: Int, renewalPriceText: String) async {
        let ok = await ensureAuthorized()
        guard ok else { return }

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [AppNotificationIdentifiers.trialEndingReminder]
        )

        let reminderDay = max(trialDays - 2, 1)
        // Derive the headline from the actual fire day — for short
        // trials `reminderDay` clamps and "in 2 days" would be wrong.
        let daysLeftAtFire = trialDays - reminderDay
        let content = UNMutableNotificationContent()
        switch daysLeftAtFire {
        case ..<1: content.title = "Your Pro trial is ending"
        case 1:    content.title = "Your Pro trial ends tomorrow"
        default:   content.title = "Your Pro trial ends in \(daysLeftAtFire) days"
        }
        content.body = renewalPriceText.isEmpty
            ? "Your free trial converts soon. Cancel anytime in Settings if Pro isn't for you."
            : "After the trial you'll be charged \(renewalPriceText). Cancel anytime in Settings if Pro isn't for you."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(5, TimeInterval(reminderDay) * 24 * 60 * 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: AppNotificationIdentifiers.trialEndingReminder,
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Date helpers
    
    private static func normalizeDayOfMonth(_ day: Int) -> Int {
        let d = day == 0 ? 1 : day
        return max(1, min(28, d))
    }
    
    private static func nextWeeklyFireDate(weekday: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        
        // Start from this week; if already passed, add 1 week.
        let thisWeek = calendar.date(from: comps) ?? now
        if thisWeek > now {
            return thisWeek
        }
        return calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
    }
    
    private static func nextMonthlyFireDate(dayOfMonth: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.year, .month], from: now)
        comps.day = dayOfMonth
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        
        let thisMonth = calendar.date(from: comps) ?? now
        if thisMonth > now {
            return thisMonth
        }
        return calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
    }

    // MARK: - Smart Insights (Pro)
    //
    // Fires once a week — but **only** when the engine finds a genuinely
    // interesting headline. The brief is explicit that a boring week should
    // produce no push, so this function will simply cancel any pending
    // request and return when no insight clears the firing bar.

    /// Default fire slot if the user hasn't customized it. Sunday 10 AM
    /// works as a low-friction "start of the week recap" moment without
    /// competing with most digest-style pushes which fire mid-week.
    private static let smartInsightDefaultWeekday = 1 // Sunday
    private static let smartInsightDefaultHour = 10
    private static let smartInsightDefaultMinute = 0

    @MainActor
    static func scheduleNextSmartInsight(viewModel: ExpenseViewModel) async -> Bool {
        let ok = await ensureAuthorized()
        guard ok else { return false }

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [AppNotificationIdentifiers.smartInsightWeekly]
        )

        // Compose engine inputs on the main actor so we can read the live
        // expense set + active subscriptions through normal APIs without
        // having to bridge a nonisolated snapshot. The engine itself is
        // pure, so the heavy work (loops over expenses) runs to completion
        // synchronously; for typical datasets this is microseconds.
        let activeSubs = await fetchActiveSubscriptionsForInsights()
        let history = loadSmartInsightHistory()
        // PERF: see `makeCategoryNameLookup` — one Core Data fetch
        // amortized over the engine's full O(N) pass instead of one
        // fetch per expense.
        let categoryNameLookup = Self.makeCategoryNameLookup(viewModel: viewModel)
        let inputs = SmartInsightsEngine.Inputs(
            now: Date(),
            calendar: .current,
            allExpenses: viewModel.expenses,
            activeSubscriptions: activeSubs,
            formattedAmount: viewModel.formattedAmount,
            categoryDisplayName: categoryNameLookup,
            history: history
        )

        guard let insight = SmartInsightsEngine.selectInsight(inputs: inputs) else {
            // No headline today — nothing to schedule, and we leave the
            // pending queue empty. The next foreground will re-evaluate.
            return false
        }

        let nextFire = nextWeeklyFireDate(
            weekday: smartInsightDefaultWeekday,
            hour: smartInsightDefaultHour,
            minute: smartInsightDefaultMinute
        )

        let content = UNMutableNotificationContent()
        content.title = insight.headline
        content.body = insight.detail
        content.sound = .default
        // Route taps into All Expenses for the past week — gives the user
        // immediate context for the headline without inventing a new screen.
        let weekStart = nextFire.addingTimeInterval(-7 * 24 * 60 * 60)
        content.userInfo = [
            NotificationUserInfoKeys.route: NotificationRouteTypes.allExpenses,
            NotificationUserInfoKeys.rangeStart: weekStart.timeIntervalSince1970,
            NotificationUserInfoKeys.rangeEnd: nextFire.timeIntervalSince1970
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(5, nextFire.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: AppNotificationIdentifiers.smartInsightWeekly,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            // Persist the firing record so the engine doesn't re-suggest the
            // same headline next week. We record at *schedule* time rather
            // than fire time because UNUserNotificationCenter doesn't give
            // us a delivery hook on iOS — a near-miss is fine since the
            // request stays pending until it actually delivers or we cancel.
            let updatedHistory = SmartInsightsEngine.record(insight: insight, in: history)
            saveSmartInsightHistory(updatedHistory)
            UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.smartInsightsLastFireDate)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Smart insight persistence helpers

    private static func loadSmartInsightHistory() -> SmartInsightsEngine.HistoryRecord {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.smartInsightsHistory),
              let decoded = try? JSONDecoder().decode(SmartInsightsEngine.HistoryRecord.self, from: data) else {
            return .empty
        }
        return decoded
    }

    private static func saveSmartInsightHistory(_ history: SmartInsightsEngine.HistoryRecord) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.smartInsightsHistory)
    }

    /// Pulls active subscriptions on a background Core Data context so the
    /// engine has a complete picture without us needing to inject the
    /// SubscriptionViewModel into every entry point that schedules.
    @MainActor
    private static func fetchActiveSubscriptionsForInsights() async -> [Subscription] {
        await withCheckedContinuation { continuation in
            let context = PersistenceController.shared.container.newBackgroundContext()
            context.perform {
                let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                request.predicate = NSPredicate(format: "isActive == YES")
                let subs: [Subscription] = (try? context.fetch(request))?.toSubscriptions() ?? []
                continuation.resume(returning: subs)
            }
        }
    }
}

// MARK: - Digest stats

private struct DigestStats {
    let totalText: String
    let topCategoryName: String?
    let biggestDayName: String?
    let hasAnySpend: Bool
    
    func bodyText(prefix: String) -> String {
        guard hasAnySpend else {
            return "No spending \(prefix). Open CashLens to review details."
        }
        var parts: [String] = []
        parts.append("You spent \(totalText) \(prefix)")
        if let topCategoryName { parts.append("Top: \(topCategoryName)") }
        if let biggestDayName { parts.append("Biggest day: \(biggestDayName)") }
        return parts.joined(separator: " • ")
    }
}

private enum DigestStatsCalculator {
    static func compute(
        expenses: [Expense],
        start: Date,
        end: Date,
        formattedAmount: (Double) -> String,
        categoryDisplayName: (Expense) -> String
    ) -> DigestStats {
        let calendar = Calendar.current
        let filtered = expenses.filter { $0.date >= start && $0.date < end }
        // Refund-aware totals so the digest reflects net spend.
        let total = filtered.netTotal()
        
        // Top category
        var byCategory: [String: Double] = [:]
        for e in filtered {
            let name = categoryDisplayName(e)
            byCategory[name, default: 0] += e.signedAmount
        }
        let topCategoryName = byCategory.max(by: { $0.value < $1.value })?.key
        
        // Biggest day of week
        var byDay: [Date: Double] = [:]
        for e in filtered {
            let d = calendar.startOfDay(for: e.date)
            byDay[d, default: 0] += e.signedAmount
        }
        let biggestDayDate = byDay.max(by: { $0.value < $1.value })?.key
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "EEE"
        let biggestDayName = biggestDayDate.map(df.string)
        
        return DigestStats(
            totalText: formattedAmount(total),
            topCategoryName: topCategoryName,
            biggestDayName: biggestDayName,
            hasAnySpend: total > 0.0001
        )
    }
}


