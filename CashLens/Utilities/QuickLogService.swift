//
//  QuickLogService.swift
//  CashLens (main app only)
//
//  Headless expense-logging service used by surfaces that run WITHOUT
//  the SwiftUI scene being alive:
//
//    • Siri / Shortcuts App Intents (`LogExpenseIntent`,
//      `GetSpendingIntent`) — App Intents in the app target execute in
//      the app's process, but the process may have been launched in
//      the background with no scene, so `ExpenseViewModel` and
//      `WidgetSnapshotCoordinator` may not be wired up.
//    • The pending-expense queue drain for the interactive Quick Log
//      widget (the widget extension can't reach the app-container
//      Core Data store, so the app drains its queue on foreground).
//
//  Design:
//
//    • All writes go through a fresh background context off
//      `PersistenceController.shared` — never the view context, which
//      may be owned by a live UI session.
//    • After a successful write we post `.expensesChangedExternally`
//      on the main queue; a live `ExpenseViewModel` observes it and
//      re-runs its diff-gated `loadExpensesAsync()` so the in-memory
//      array reconciles without a full-table thrash.
//    • The widget snapshot is rebuilt directly from the store (not
//      from view models) so Home Screen widgets update even when the
//      intent ran headless.
//
import Foundation
import CoreData
import WidgetKit
import os

enum QuickLogService {

    /// Diagnostic trail for headless writes (Siri intents + widget queue
    /// drain). Console.app filter: subsystem com.rushi.CashLens
    private static let log = Logger(subsystem: "com.rushi.CashLens", category: "QuickLog")

    /// Diagnostic trail for headless writes (Siri intents + widget queue
    /// drain).
    ///
    /// PRIVACY: trail lines can contain expense titles and amounts, so in
    /// Release they are redacted (`privacy: .private`) and the plain-text
    /// Documents log is neither written nor kept. Debug builds keep the
    /// public log + file because os_log from a background App Intents
    /// launch is hard to capture off-device.
    static func diagTrail(_ line: String) {
        #if DEBUG
        log.info("\(line, privacy: .public)")
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("quicklog-diagnostics.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(line)"
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        lines.append(entry)
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #else
        log.info("\(line, privacy: .private)")
        Self.removeDebugDiagFileIfPresent()
        #endif
    }

    #if !DEBUG
    /// One-shot cleanup: a device that previously ran a Debug build may
    /// still carry the plain-text diagnostics file. Remove it the first
    /// time a Release build logs anything.
    private static let removeDebugDiagFileOnce: Void = {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("quicklog-diagnostics.log"))
    }()

    private static func removeDebugDiagFileIfPresent() {
        _ = removeDebugDiagFileOnce
    }
    #endif

    enum QuickLogError: LocalizedError {
        case storeUnavailable
        case invalidAmount

        var errorDescription: String? {
            switch self {
            case .storeUnavailable:
                return "CashLens couldn't open its data store. Open the app to fix this."
            case .invalidAmount:
                return "That amount doesn't look right. Try a positive number."
            }
        }
    }

    // MARK: - Preferences (UserDefaults-backed, scene-independent)

    /// The user's selected app currency. Reads the same key the app
    /// writes so Siri-logged expenses land in the right currency.
    static func selectedCurrency() -> Expense.Currency {
        if let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedCurrency),
           let currency = Expense.Currency(rawValue: raw) {
            return currency
        }
        return .usd
    }

    /// Currency-aware "₹1,240" formatting without needing a live
    /// `ExpenseViewModel`. Mirrors `formattedAmount`'s digit rules.
    static func formatAmount(_ amount: Double, currency: Expense.Currency) -> String {
        let digits = currency.fractionDigits
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let magnitude = formatter.string(from: NSNumber(value: abs(amount.isFinite ? amount : 0)))
            ?? (digits == 0 ? "0" : "0." + String(repeating: "0", count: digits))
        let sign = amount < 0 ? "-" : ""
        return "\(sign)\(currency.symbol)\(magnitude)"
    }

    // MARK: - Category resolution

    /// Display names offered by the intent's category picker: available
    /// default categories (respecting user deletions) followed by
    /// custom categories from Core Data.
    static func availableCategoryNames() -> [String] {
        let deleted = Set(
            (UserDefaults.standard.array(forKey: UserDefaultsKeys.deletedDefaultCategories) as? [String]) ?? []
        )
        let defaults = Expense.Category.allCases
            .filter { $0 != .custom && !deleted.contains($0.rawValue) }
            .map(\.displayName)
        let custom = fetchCustomCategories().map(\.name)
        return defaults + custom
    }

    /// Map a user-facing category name back to a `(category, customId)`
    /// pair. Tolerant: matches display name or raw value
    /// case-insensitively, falls back to `.other` for anything unknown
    /// (e.g. a free-typed string from the Shortcuts app).
    static func resolveCategory(named name: String?) -> (category: Expense.Category, customCategoryId: UUID?) {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return (.other, nil)
        }
        if let match = Expense.Category.allCases.first(where: {
            $0 != .custom &&
            ($0.displayName.caseInsensitiveCompare(name) == .orderedSame ||
             $0.rawValue.caseInsensitiveCompare(name) == .orderedSame)
        }) {
            return (match, nil)
        }
        if let custom = fetchCustomCategories().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return (.custom, custom.id)
        }
        return (.other, nil)
    }

    /// Best-effort category inference from a spoken/typed title, used
    /// when the intent got no explicit category. Word-boundary keyword
    /// match against a small curated map + the user's custom category
    /// names ("coffee" → Food, "uber" → Transportation, "gym" →
    /// custom "Gym" if one exists). Falls back to `.other`.
    static func inferCategory(fromTitle title: String) -> (category: Expense.Category, customCategoryId: UUID?) {
        let words = Set(
            title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        guard !words.isEmpty else { return (.other, nil) }

        // A custom category the user created is the strongest signal —
        // check those first ("gym", "pets", whatever they named it).
        for custom in fetchCustomCategories() {
            let nameWords = custom.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            if !nameWords.isEmpty && nameWords.allSatisfy(words.contains) {
                return (.custom, custom.id)
            }
        }

        let keywordMap: [Expense.Category: Set<String>] = [
            .groceries: ["grocery", "groceries", "supermarket", "vegetables", "fruits", "milk", "bread", "eggs"],
            .food: ["food", "lunch", "dinner", "breakfast", "coffee", "tea", "snack", "snacks", "restaurant",
                    "pizza", "burger", "biryani", "swiggy", "zomato", "juice", "dessert", "icecream", "chai"],
            .transportation: ["uber", "ola", "taxi", "cab", "bus", "train", "metro", "fuel", "petrol", "diesel",
                              "gas", "parking", "toll", "auto", "rickshaw"],
            .entertainment: ["movie", "movies", "cinema", "netflix", "concert", "game", "games", "gaming",
                             "show", "tickets"],
            .shopping: ["shopping", "clothes", "shoes", "amazon", "flipkart", "myntra", "dress", "shirt",
                        "jeans", "electronics", "gadget"],
            .health: ["medicine", "medicines", "pharmacy", "doctor", "hospital", "clinic", "dental",
                      "vitamins", "checkup"],
            .education: ["book", "books", "course", "class", "classes", "tuition", "udemy", "workshop"],
            .travel: ["flight", "hotel", "trip", "vacation", "holiday", "airbnb", "visa", "luggage"]
        ]
        let deleted = Set(
            (UserDefaults.standard.array(forKey: UserDefaultsKeys.deletedDefaultCategories) as? [String]) ?? []
        )
        for (category, keywords) in keywordMap where !deleted.contains(category.rawValue) {
            if !keywords.isDisjoint(with: words) {
                return (category, nil)
            }
        }
        return (.other, nil)
    }

    /// Display name for a resolved category pair (used in dialogs).
    static func displayName(for category: Expense.Category, customCategoryId: UUID?) -> String {
        if category == .custom, let id = customCategoryId,
           let custom = fetchCustomCategories().first(where: { $0.id == id }) {
            return custom.name
        }
        return category.displayName
    }

    private static func fetchCustomCategories() -> [CustomCategory] {
        guard !PersistenceController.shared.storeLoadFailed else { return [] }
        let context = PersistenceController.shared.container.newBackgroundContext()
        var result: [CustomCategory] = []
        context.performAndWait {
            let request: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
            result = (try? context.fetch(request).toCustomCategories()) ?? []
        }
        return result
    }

    // MARK: - Write path

    /// Persist one expense directly to the store on a background
    /// context. Dedup-safe: if a row with the same `id` already exists
    /// the write is skipped (required by the widget queue drain, where
    /// a crash between "insert" and "clear queue" could replay records).
    ///
    /// On success, posts `.expensesChangedExternally` so a live
    /// `ExpenseViewModel` reconciles its in-memory array.
    @discardableResult
    static func logExpense(
        id: UUID = UUID(),
        amount: Double,
        title: String,
        category: Expense.Category,
        customCategoryId: UUID? = nil,
        date: Date = Date(),
        notifyChange: Bool = true
    ) throws -> Expense {
        guard !PersistenceController.shared.storeLoadFailed else {
            throw QuickLogError.storeUnavailable
        }
        guard amount.isFinite, amount > 0 else {
            throw QuickLogError.invalidAmount
        }
        diagTrail("logExpense writing amount=\(amount) title=\(title) category=\(category.rawValue) id=\(id.uuidString.prefix(8))")

        let expense = Expense(
            id: id,
            title: title,
            amount: amount,
            currency: selectedCurrency(),
            date: date,
            category: category,
            customCategoryId: category == .custom ? customCategoryId : nil
        )

        let context = PersistenceController.shared.container.newBackgroundContext()
        var saveError: Error?
        var insertedNew = false
        context.performAndWait {
            do {
                // Dedup guard — never double-log the same record id.
                let existing: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                existing.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
                existing.fetchLimit = 1
                if try context.count(for: existing) > 0 { return }

                _ = ExpenseEntity.fromExpense(expense, context: context)
                try context.save()
                insertedNew = true
            } catch {
                saveError = error
            }
        }
        if let saveError { throw saveError }

        if insertedNew && notifyChange {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .expensesChangedExternally, object: nil)
            }
        }
        return expense
    }

    // MARK: - Widget pending-queue drain

    /// Drain every `PendingExpenseRecord` the Quick Log widget has
    /// queued in the App Group into Core Data. Idempotent: each
    /// record's file is deleted only after its insert commits, and the
    /// insert itself dedups on the record id, so a crash mid-drain
    /// replays harmlessly. Records that fail to insert stay queued for
    /// the next foreground.
    ///
    /// Returns the number of newly-drained expenses so the caller can
    /// surface an "Added from widget" toast. Call off the main thread.
    @discardableResult
    static func drainWidgetQueue() -> Int {
        guard !PersistenceController.shared.storeLoadFailed else { return 0 }
        let records = PendingExpenseQueue.readAll()   // already oldest-first
        guard !records.isEmpty else { return 0 }
        diagTrail("drainWidgetQueue found \(records.count) pending record(s): \(records.map { "\($0.amount)/\($0.categoryRaw)" }.joined(separator: ", "))")

        var drained = 0
        for record in records {
            let category = Expense.Category(rawValue: record.categoryRaw) ?? .other
            do {
                try logExpense(
                    id: record.id,
                    amount: record.amount,
                    title: record.title,
                    category: category,
                    customCategoryId: record.customCategoryId,
                    date: record.createdAt,
                    notifyChange: false   // one batched notification below
                )
                PendingExpenseQueue.remove(id: record.id)
                drained += 1
            } catch {
                // Leave the record queued — a transient store error
                // shouldn't drop the user's expense.
                continue
            }
        }

        if drained > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .expensesChangedExternally, object: nil)
            }
            // Reconcile the widget's optimistic total: the queue is now
            // (mostly) empty and the store has the real rows.
            rebuildWidgetSnapshotFromStore()
        }
        return drained
    }

    // MARK: - Read path (spending summary)

    /// Net spend (refund-aware) for today and the current month,
    /// computed with a direct Core Data fetch — no view model needed.
    static func spendingSummary(now: Date = Date()) -> (today: Double, month: Double) {
        guard !PersistenceController.shared.storeLoadFailed else { return (0, 0) }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday

        let context = PersistenceController.shared.container.newBackgroundContext()
        var today: Double = 0
        var month: Double = 0
        context.performAndWait {
            let request: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            // One fetch covers both windows — today is always inside
            // the current month. The upper bound excludes any
            // future-dated rows so "this month" means "so far".
            request.predicate = NSPredicate(
                format: "date >= %@ AND date < %@",
                startOfMonth as NSDate, startOfTomorrow as NSDate
            )
            guard let rows = try? context.fetch(request) else { return }
            for row in rows {
                guard row.amount.isFinite else { continue }
                let signed = row.isRefund ? -row.amount : row.amount
                month += signed
                if let d = row.date, d >= startOfToday {
                    today += signed
                }
            }
        }
        return (today, month)
    }

    // MARK: - Widget snapshot rebuild (headless)

    /// Rebuild and write the widget snapshot straight from the store +
    /// UserDefaults, then reload timelines. Used after headless writes
    /// where `WidgetSnapshotCoordinator` (which needs live view models)
    /// may not be bootstrapped. Safe to call alongside the coordinator —
    /// both writers are atomic and produce equivalent content.
    static func rebuildWidgetSnapshotFromStore(now: Date = Date()) {
        guard !PersistenceController.shared.storeLoadFailed else { return }

        let context = PersistenceController.shared.container.newBackgroundContext()
        var expenses: [Expense] = []
        var budgets: [Budget] = []
        var subscriptions: [Subscription] = []
        var customCategories: [CustomCategory] = []
        context.performAndWait {
            let expenseRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            expenseRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
            expenseRequest.fetchBatchSize = 200
            expenses = (try? context.fetch(expenseRequest).toExpenses()) ?? []

            let budgetRequest: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
            budgets = (try? context.fetch(budgetRequest).toBudgets()) ?? []

            let subRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
            subRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)]
            subscriptions = (try? context.fetch(subRequest).toSubscriptions()) ?? []

            let categoryRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
            customCategories = (try? context.fetch(categoryRequest).toCustomCategories()) ?? []
        }

        let defaults = UserDefaults.standard
        let inputs = WidgetSnapshotBuilder.Inputs(
            expenses: expenses,
            budgets: budgets,
            subscriptions: subscriptions,
            customCategories: customCategories,
            templates: ExpenseTemplateStore.snapshotTemplates(),
            currencyCode: selectedCurrency().rawValue,
            userName: defaults.string(forKey: UserDefaultsKeys.userName) ?? "",
            activeThemeId: defaults.string(forKey: UserDefaultsKeys.activeThemeId) ?? "mauve",
            isPro: defaults.bool(forKey: UserDefaultsKeys.lastKnownIsPro),
            now: now
        )
        WidgetSnapshotIO.write(WidgetSnapshotBuilder.build(inputs))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
