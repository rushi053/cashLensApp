#if DEBUG
import CoreData
import Foundation
import UIKit

/// Debug-only launch mode for App Store preview and ad recordings.
/// The whole file is compiled out of Release.
///
///   -demoData         wipe local data and seed the fixed dataset
///   -slowAnimations   1.5× motion (springs, reveals, sheets)
///   -skipOnboarding   jump straight to Today
///   -showOnboarding   force the onboarding flow
///   -proUnlocked      force Pro on
///   -proLocked        force Pro off
///   -demoDate yyyy-MM-dd   freeze "today" to that date, 15:30 local
///
/// CashLens has no income ledger, so the brief's "Salary" row is not
/// seeded: logging it as an expense would count as spending and blow
/// the $2,500 budget. The one refund is "Returned purchase".
enum PromoDemo {

    /// Set by `-demoDate`. Read by `AppNow` on every "now" check.
    static var frozenNow: Date?

    /// `nil` leaves StoreKit in charge. Set by `-proUnlocked` / `-proLocked`.
    static var forcedIsPro: Bool?

    /// 1.5 while `-slowAnimations` is set, otherwise 1.
    static var animationScale: Double = 1

    private static var didConfigure = false
    private static var demoDataRequested = false

    // MARK: - Launch arguments

    /// Idempotent. Called before Pro, App Lock and the view models
    /// read preferences, because those singletons initialize before
    /// `CashLensApp.init` runs its body.
    static func configureFromLaunchArguments() {
        guard !didConfigure else { return }
        didConfigure = true
        apply(arguments: ProcessInfo.processInfo.arguments)
    }

    static func apply(arguments: [String], defaults: UserDefaults = .standard) {
        var onboarding: OnboardingOverride?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-demoData":
                demoDataRequested = true
            case "-slowAnimations":
                animationScale = 1.5
            case "-skipOnboarding":
                onboarding = .skip
            case "-showOnboarding":
                onboarding = .show
            case "-proUnlocked":
                forcedIsPro = true
            case "-proLocked":
                forcedIsPro = false
            case "-demoDate":
                let next = index + 1
                if next < arguments.count, let date = parseDemoDate(arguments[next]) {
                    frozenNow = date
                    index = next
                } else {
                    print("PromoDemo: -demoDate needs a yyyy-MM-dd value; clock left alone.")
                }
            default:
                break
            }
            index += 1
        }
        applyPreferences(onboarding: onboarding, defaults: defaults)
    }

    /// Puts the static flags back. Tests call this; launch does not.
    static func resetForTests() {
        frozenNow = nil
        forcedIsPro = nil
        animationScale = 1
        demoDataRequested = false
        didConfigure = false
    }

    enum OnboardingOverride {
        case skip, show
    }

    /// Noon-adjacent (15:30 local) so the greeting is "Good afternoon"
    /// and the whole date is unambiguously that calendar day.
    static func parseDemoDate(_ text: String) -> Date? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = 15
        parts.minute = 30
        return calendar.date(from: parts)
    }

    private static func applyPreferences(onboarding: OnboardingOverride?, defaults: UserDefaults) {
        let promo = demoDataRequested || frozenNow != nil || forcedIsPro != nil || animationScale > 1 || onboarding != nil
        guard promo else { return }

        // A lock screen in the middle of a take ruins it.
        defaults.set(false, forKey: UserDefaultsKeys.appLockEnabled)
        defaults.removeObject(forKey: UserDefaultsKeys.appLockLastBackgroundedAt)

        guard demoDataRequested else {
            writeOnboarding(onboarding, defaults: defaults)
            return
        }

        defaults.set(Expense.Currency.usd.rawValue, forKey: UserDefaultsKeys.selectedCurrency)
        defaults.set("Alex", forKey: UserDefaultsKeys.userName)
        defaults.set(true, forKey: UserDefaultsKeys.hasLaunchedBefore)
        defaults.set(true, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
        defaults.set("This Month", forKey: UserDefaultsKeys.selectedTimeFrame)
        defaults.set("This Month", forKey: UserDefaultsKeys.defaultHomeTimeFrame)
        // Back to the shipping default (This Week) so a previous
        // All Time choice doesn't leak into the take.
        defaults.removeObject(forKey: SummaryPeriod.userDefaultsKey)
        defaults.removeObject(forKey: UserDefaultsKeys.expenseDraft)
        // 46 seeded expenses would otherwise trip the rating sheet.
        // Same major.minor key ReviewPromptManager uses.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2"
        let asked = version.split(separator: ".").prefix(2).joined(separator: ".")
        defaults.set(asked, forKey: UserDefaultsKeys.reviewPromptAskedVersion)
        writeOnboarding(onboarding, defaults: defaults)
        print("PromoDemo: demo data requested. Today is \(frozenNow.map { "\($0)" } ?? "the real clock").")
    }

    private static func writeOnboarding(_ onboarding: OnboardingOverride?, defaults: UserDefaults) {
        switch onboarding {
        case .skip:
            defaults.set(true, forKey: UserDefaultsKeys.hasCompletedOnboarding)
            defaults.set(true, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
            defaults.set(true, forKey: UserDefaultsKeys.hasLaunchedBefore)
        case .show:
            defaults.set(false, forKey: UserDefaultsKeys.hasCompletedOnboarding)
        case nil:
            break
        }
    }

    // MARK: - Motion

    /// Slows UIKit-driven motion (sheet presentations included).
    /// SwiftUI springs go through `Theme.Motion`, which reads
    /// `animationScale`.
    static func applySlowAnimations() {
        guard animationScale > 1 else { return }
        let speed = Float(1 / animationScale)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.layer.speed = speed
            }
        }
    }

    // MARK: - Dataset

    struct Row {
        /// 0 = the frozen month, -1 = the month before.
        var monthOffset: Int
        var day: Int
        var hour: Int
        var title: String
        var category: Expense.Category
        var cents: Int
        var refund: Bool = false
    }

    /// Fixed merchants, exact cent amounts. October (month offset 0)
    /// nets to $1,750.00, which is 70% of the $2,500 budget, and
    /// Groceries nets to $428.40 against a $400 budget. September
    /// nets to $1,520.00. Every amount is a whole number of cents.
    static let rows: [Row] = [
        // Current month. Spending is light in the first days and
        // heavier after the 12th, so the trend climbs.
        Row(monthOffset: 0, day: 1, hour: 8, title: "Gym membership", category: .health, cents: 4500),
        Row(monthOffset: 0, day: 2, hour: 8, title: "Morning coffee", category: .food, cents: 450),
        Row(monthOffset: 0, day: 3, hour: 18, title: "Groceries", category: .groceries, cents: 6240),
        Row(monthOffset: 0, day: 4, hour: 8, title: "Morning coffee", category: .food, cents: 525),
        Row(monthOffset: 0, day: 5, hour: 9, title: "Train pass", category: .transportation, cents: 1860),
        Row(monthOffset: 0, day: 6, hour: 8, title: "Morning coffee", category: .food, cents: 480),
        Row(monthOffset: 0, day: 6, hour: 20, title: "Movie night", category: .entertainment, cents: 3200),
        Row(monthOffset: 0, day: 7, hour: 19, title: "Dinner with friends", category: .food, cents: 8640),
        Row(monthOffset: 0, day: 8, hour: 8, title: "Morning coffee", category: .food, cents: 610),
        Row(monthOffset: 0, day: 8, hour: 13, title: "Stationery", category: .shopping, cents: 4200),
        Row(monthOffset: 0, day: 8, hour: 16, title: "Returned purchase", category: .shopping, cents: 2400, refund: true),
        Row(monthOffset: 0, day: 9, hour: 17, title: "Groceries", category: .groceries, cents: 8450),
        Row(monthOffset: 0, day: 10, hour: 9, title: "Train pass", category: .transportation, cents: 1860),
        Row(monthOffset: 0, day: 11, hour: 8, title: "Morning coffee", category: .food, cents: 550),
        Row(monthOffset: 0, day: 12, hour: 11, title: "Electricity bill", category: .utilities, cents: 14280),
        Row(monthOffset: 0, day: 13, hour: 18, title: "Groceries", category: .groceries, cents: 11250),
        Row(monthOffset: 0, day: 14, hour: 8, title: "Morning coffee", category: .food, cents: 495),
        Row(monthOffset: 0, day: 14, hour: 15, title: "Household supplies", category: .shopping, cents: 6400),
        Row(monthOffset: 0, day: 15, hour: 9, title: "Train pass", category: .transportation, cents: 1860),
        Row(monthOffset: 0, day: 16, hour: 12, title: "Pharmacy", category: .health, cents: 4280),
        Row(monthOffset: 0, day: 16, hour: 19, title: "Dinner with friends", category: .food, cents: 12400),
        Row(monthOffset: 0, day: 17, hour: 8, title: "Morning coffee", category: .food, cents: 640),
        Row(monthOffset: 0, day: 17, hour: 14, title: "Home goods", category: .shopping, cents: 15965),
        Row(monthOffset: 0, day: 18, hour: 11, title: "Car repair", category: .transportation, cents: 24800),
        Row(monthOffset: 0, day: 18, hour: 18, title: "Groceries", category: .groceries, cents: 16900),
        Row(monthOffset: 0, day: 19, hour: 8, title: "Morning coffee", category: .food, cents: 575),
        Row(monthOffset: 0, day: 19, hour: 10, title: "Car wash", category: .transportation, cents: 9000),
        Row(monthOffset: 0, day: 19, hour: 20, title: "Movie night", category: .entertainment, cents: 2850),
        Row(monthOffset: 0, day: 20, hour: 8, title: "Gym membership", category: .health, cents: 4500),
        Row(monthOffset: 0, day: 20, hour: 19, title: "Dinner with friends", category: .food, cents: 9640),

        // Previous month, so Insights has a comparison period.
        Row(monthOffset: -1, day: 1, hour: 8, title: "Gym membership", category: .health, cents: 4500),
        Row(monthOffset: -1, day: 3, hour: 8, title: "Morning coffee", category: .food, cents: 420),
        Row(monthOffset: -1, day: 4, hour: 9, title: "Train pass", category: .transportation, cents: 1860),
        Row(monthOffset: -1, day: 5, hour: 18, title: "Groceries", category: .groceries, cents: 9800),
        Row(monthOffset: -1, day: 8, hour: 8, title: "Morning coffee", category: .food, cents: 510),
        Row(monthOffset: -1, day: 9, hour: 15, title: "Returned purchase", category: .shopping, cents: 1500, refund: true),
        Row(monthOffset: -1, day: 10, hour: 11, title: "Electricity bill", category: .utilities, cents: 22000),
        Row(monthOffset: -1, day: 12, hour: 20, title: "Movie night", category: .entertainment, cents: 2400),
        Row(monthOffset: -1, day: 14, hour: 8, title: "Morning coffee", category: .food, cents: 480),
        Row(monthOffset: -1, day: 16, hour: 19, title: "Dinner with friends", category: .food, cents: 7200),
        Row(monthOffset: -1, day: 18, hour: 9, title: "Train pass", category: .transportation, cents: 1860),
        Row(monthOffset: -1, day: 19, hour: 18, title: "Groceries", category: .groceries, cents: 24800),
        Row(monthOffset: -1, day: 20, hour: 14, title: "Household supplies", category: .shopping, cents: 16510),
        Row(monthOffset: -1, day: 22, hour: 8, title: "Morning coffee", category: .food, cents: 560),
        Row(monthOffset: -1, day: 25, hour: 19, title: "Dinner with friends", category: .food, cents: 18600),
        Row(monthOffset: -1, day: 27, hour: 11, title: "Car repair", category: .transportation, cents: 42000),
    ]

    static func netCents(monthOffset: Int) -> Int {
        rows.filter { $0.monthOffset == monthOffset }.reduce(0) { partial, row in
            partial + (row.refund ? -row.cents : row.cents)
        }
    }

    static func cents(monthOffset: Int, category: Expense.Category) -> Int {
        rows.filter { $0.monthOffset == monthOffset && $0.category == category && !$0.refund }
            .reduce(0) { $0 + $1.cents }
    }

    // MARK: - Seeding

    static func seedIfRequested(container: NSPersistentContainer) {
        guard demoDataRequested else { return }
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var failure: Error?
        context.performAndWait {
            do {
                try wipe(context)
                try insert(context)
                try context.save()
            } catch {
                failure = error
            }
        }
        if let failure {
            print("PromoDemo: seed failed — \(failure)")
            return
        }
        container.viewContext.reset()
        clearPendingQuickLogs()
        print("PromoDemo: seeded \(rows.count) expenses, 2 budgets. Current month net \(netCents(monthOffset: 0)) cents.")
    }

    private static func wipe(_ context: NSManagedObjectContext) throws {
        for name in ["ExpenseEntity", "BudgetEntity", "SubscriptionEntity", "CustomCategoryEntity"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
    }

    private static func insert(_ context: NSManagedObjectContext) throws {
        let anchor = frozenNow ?? Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor

        for (index, row) in rows.enumerated() {
            guard let month = calendar.date(byAdding: .month, value: row.monthOffset, to: monthStart) else { continue }
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = row.day
            parts.hour = row.hour
            parts.minute = row.day
            guard let date = calendar.date(from: parts) else {
                print("PromoDemo: skipped \(row.title) on day \(row.day) (not a real date).")
                continue
            }
            let expense = Expense(
                id: deterministicID(index + 1),
                title: row.title,
                amount: Double(row.cents) / 100,
                currency: .usd,
                date: date,
                category: row.category,
                isRefund: row.refund,
                paymentMethod: paymentMethod(for: index)
            )
            _ = ExpenseEntity.fromExpense(expense, context: context)
        }

        let overall = Budget(
            id: deterministicID(100),
            name: "Monthly Spend",
            amount: 2500,
            period: .monthly,
            categoryFilter: .overall,
            alertAtPercentages: Budget.defaultAlertPercentages,
            isActive: true,
            createdAt: monthStart
        )
        let groceries = Budget(
            id: deterministicID(101),
            name: "Groceries",
            amount: 400,
            period: .monthly,
            categoryFilter: .defaultCategory(Expense.Category.groceries.rawValue),
            alertAtPercentages: Budget.defaultAlertPercentages,
            isActive: true,
            createdAt: monthStart
        )
        _ = BudgetEntity.fromBudget(overall, context: context)
        _ = BudgetEntity.fromBudget(groceries, context: context)
    }

    private static func paymentMethod(for index: Int) -> PaymentMethod {
        switch index % 3 {
        case 0: return .creditCard
        case 1: return .debitCard
        default: return .cash
        }
    }

    static func deterministicID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }

    /// A widget quick-log waiting in the App Group would be drained
    /// on this launch and shift the totals.
    private static func clearPendingQuickLogs() {
        guard let directory = PendingExpenseQueue.directoryURL else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
#endif
