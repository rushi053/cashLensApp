import Foundation
import UserNotifications
import SwiftUI

enum AppNotificationIdentifiers {
    // Legacy id (kept for cleanup)
    static let weeklySummary = "weekly_summary"
    
    static let weeklyDigest = "weekly_digest_next"
    static let monthlyDigest = "monthly_digest_next"
    static let backupReminder = "backup_reminder_next"
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
    
    static func cancelWeeklySummary() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            AppNotificationIdentifiers.weeklySummary,
            AppNotificationIdentifiers.weeklyDigest
        ])
    }
    
    // MARK: - Public entrypoint used by the app on foregrounding
    
    /// Re-schedules next-occurrence notifications based on current user preferences.
    /// We intentionally schedule a single upcoming notification (not repeating) so the body can be refreshed with real data.
    static func refreshScheduledNotificationsIfNeeded(viewModel: ExpenseViewModel) async {
        let weeklyEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.weeklySummaryEnabled)
        let monthlyEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.monthlyDigestEnabled)
        let backupEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.backupReminderEnabled)
        
        // Clean up legacy repeating id if any exists
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.weeklySummary])
        
        if weeklyEnabled {
            let weekday = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklySummaryWeekday)
            let hour = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklySummaryHour)
            let minute = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklySummaryMinute)
            _ = await scheduleNextWeeklyDigest(weekday: max(1, min(7, weekday == 0 ? 2 : weekday)), hour: hour, minute: minute, viewModel: viewModel)
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.weeklyDigest])
        }
        
        if monthlyEnabled {
            let day = UserDefaults.standard.integer(forKey: UserDefaultsKeys.monthlyDigestDayOfMonth)
            let hour = UserDefaults.standard.integer(forKey: UserDefaultsKeys.monthlyDigestHour)
            let minute = UserDefaults.standard.integer(forKey: UserDefaultsKeys.monthlyDigestMinute)
            _ = await scheduleNextMonthlyDigest(dayOfMonth: normalizeDayOfMonth(day), hour: hour, minute: minute, viewModel: viewModel)
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.monthlyDigest])
        }
        
        if backupEnabled {
            let day = UserDefaults.standard.integer(forKey: UserDefaultsKeys.backupReminderDayOfMonth)
            let hour = UserDefaults.standard.integer(forKey: UserDefaultsKeys.backupReminderHour)
            let minute = UserDefaults.standard.integer(forKey: UserDefaultsKeys.backupReminderMinute)
            _ = await scheduleNextBackupReminder(dayOfMonth: normalizeDayOfMonth(day), hour: hour, minute: minute)
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.backupReminder])
        }
    }
    
    // MARK: - Legacy API used by ProfileView (kept signature; now schedules next digest)
    
    static func scheduleWeeklySummary(weekday: Int, hour: Int, minute: Int) async -> Bool {
        // ProfileView uses this entrypoint; treat "Weekly Summary" as "Weekly Digest".
        // We need access to real data for dynamic body, so if the app hasn't created the view model yet,
        // we still schedule a generic notification without stats.
        let ok = await ensureAuthorized()
        guard ok else { return false }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            AppNotificationIdentifiers.weeklySummary,
            AppNotificationIdentifiers.weeklyDigest
        ])
        
        let nextFire = nextWeeklyFireDate(weekday: weekday, hour: hour, minute: minute)
        let content = UNMutableNotificationContent()
        content.title = "Weekly Digest"
        content.body = "Open CashLens to review your spending for the week."
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKeys.route: NotificationRouteTypes.allExpenses,
            NotificationUserInfoKeys.rangeStart: nextFire.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970,
            NotificationUserInfoKeys.rangeEnd: nextFire.timeIntervalSince1970
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
    
    // MARK: - Digest scheduling with computed stats
    
    static func scheduleNextWeeklyDigest(weekday: Int, hour: Int, minute: Int, viewModel: ExpenseViewModel) async -> Bool {
        let ok = await ensureAuthorized()
        guard ok else { return false }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AppNotificationIdentifiers.weeklyDigest])
        
        let nextFire = nextWeeklyFireDate(weekday: weekday, hour: hour, minute: minute)
        let interval = (start: nextFire.addingTimeInterval(-7 * 24 * 60 * 60), end: nextFire)
        let stats = DigestStatsCalculator.compute(expenses: viewModel.expenses, start: interval.start, end: interval.end, formattedAmount: viewModel.formattedAmount, categoryDisplayName: viewModel.categoryDisplayName)
        
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
        
        let stats = DigestStatsCalculator.compute(expenses: viewModel.expenses, start: start, end: end, formattedAmount: viewModel.formattedAmount, categoryDisplayName: viewModel.categoryDisplayName)
        
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
        let total = filtered.reduce(0) { $0 + $1.amount }
        
        // Top category
        var byCategory: [String: Double] = [:]
        for e in filtered {
            let name = categoryDisplayName(e)
            byCategory[name, default: 0] += e.amount
        }
        let topCategoryName = byCategory.max(by: { $0.value < $1.value })?.key
        
        // Biggest day of week
        var byDay: [Date: Double] = [:]
        for e in filtered {
            let d = calendar.startOfDay(for: e.date)
            byDay[d, default: 0] += e.amount
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


