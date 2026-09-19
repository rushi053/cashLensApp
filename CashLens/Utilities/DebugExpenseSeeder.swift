#if DEBUG
import CoreData
import Foundation

/// Debug-only stress seeder for the 2.2 performance measurement plan
/// (Project store `docs/performance-investigation-2.2.md`, §7.1).
///
/// Nothing in this file is compiled into Release builds (`#if DEBUG`
/// wraps the whole file), and the two entry points are Debug-only too:
/// `DiagnosticsView` (itself `#if DEBUG`) and the `-CLSeedExpenses <n>`
/// launch argument read in `CashLensApp.init`.
///
/// Every seeded expense carries `subscriptionId == sentinelSubscriptionID`
/// (with `isFromSubscription == false`, so nothing treats it as a
/// recurring charge — that flag is what the app reads; the id is only
/// used to look up a real subscription, which the sentinel never is).
/// "Delete seeded data" removes exactly those rows plus the six custom
/// categories whose names start with `seededCategoryPrefix`. Real data
/// is never matched.
///
/// Rows are written with `NSBatchInsertRequest` on a background context
/// (no per-row `NSManagedObject` churn on the view context), then the
/// object IDs are merged into the view context and
/// `.expensesChangedExternally` is posted so the live `ExpenseViewModel`
/// reloads through its normal diff-gated `loadExpensesAsync()` path.
///
/// Distributions mirror `Scripts/generate_stress_test_export.swift`
/// (same titles, amount tiers, 730-day window, 18 % custom categories,
/// 12 % notes) plus the report's additions (3 % dated today, 3 %
/// refunds, 20 % tagged, 40 % payment method). Subscriptions and
/// budgets are **not** seeded — add a budget by hand to exercise Today.
enum DebugExpenseSeeder {

    // MARK: - Markers

    /// Never a real subscription id: fixed, version-4-shaped, all zeros
    /// except a readable "C1EE 5EED" (CashLens seed) prefix.
    static let sentinelSubscriptionID = UUID(uuidString: "0000C1EE-5EED-4000-8000-000000000000")!
    /// Seeded custom categories are named "Seed Coffee", "Seed Games", …
    static let seededCategoryPrefix = "Seed "
    /// `-CLSeedExpenses 20000` (argument-domain `UserDefaults` key).
    static let launchArgumentKey = "CLSeedExpenses"

    struct Summary {
        let insertedExpenses: Int
        let insertedCategories: Int
        let elapsed: TimeInterval
    }

    // MARK: - Entry points

    /// Launch-argument hook. Runs synchronously (`performAndWait`) so the
    /// store is full before the view models hydrate and cold start can
    /// be measured against it. Skips when the store already holds at
    /// least `n` seeded rows, so relaunching with the same argument is
    /// idempotent.
    static func seedFromLaunchArgumentsIfRequested(container: NSPersistentContainer) {
        let requested = UserDefaults.standard.integer(forKey: launchArgumentKey)
        guard requested > 0 else { return }
        let existing = seededCount(container: container)
        guard existing < requested else {
            print("DebugExpenseSeeder: store already has \(existing) seeded rows (requested \(requested)); skipping.")
            return
        }
        let summary = seedSynchronously(
            count: requested - existing,
            container: container,
            currencyCode: currentCurrencyCode()
        )
        print("DebugExpenseSeeder: launch-argument seed inserted \(summary.insertedExpenses) expenses in \(String(format: "%.2f", summary.elapsed))s.")
    }

    /// Diagnostics entry point. Work happens on a background context;
    /// `completion` is delivered on the main queue after the view
    /// context has merged the inserts and the reload notification has
    /// been posted.
    static func seed(
        count: Int,
        container: NSPersistentContainer,
        currencyCode: String,
        completion: @escaping (Summary) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let summary = seedSynchronously(count: count, container: container, currencyCode: currencyCode)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .expensesChangedExternally, object: nil)
                completion(summary)
            }
        }
    }

    /// Removes every seeded expense and seeded custom category. Nothing
    /// else matches the two predicates.
    static func deleteSeededData(
        container: NSPersistentContainer,
        completion: @escaping (_ deletedExpenses: Int, _ deletedCategories: Int) -> Void
    ) {
        let context = container.newBackgroundContext()
        context.perform {
            var deletedExpenses = 0
            var deletedCategories = 0

            let expenseFetch: NSFetchRequest<NSFetchRequestResult> = ExpenseEntity.fetchRequest()
            expenseFetch.predicate = NSPredicate(format: "subscriptionId == %@", sentinelSubscriptionID as CVarArg)
            deletedExpenses = batchDelete(expenseFetch, in: context, container: container)

            let categoryFetch: NSFetchRequest<NSFetchRequestResult> = CustomCategoryEntity.fetchRequest()
            categoryFetch.predicate = NSPredicate(format: "name BEGINSWITH %@", seededCategoryPrefix)
            deletedCategories = batchDelete(categoryFetch, in: context, container: container)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .expensesChangedExternally, object: nil)
                completion(deletedExpenses, deletedCategories)
            }
        }
    }

    /// Number of seeded expense rows currently in the store.
    static func seededCount(container: NSPersistentContainer) -> Int {
        let context = container.newBackgroundContext()
        var count = 0
        context.performAndWait {
            let request: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            request.predicate = NSPredicate(format: "subscriptionId == %@", sentinelSubscriptionID as CVarArg)
            count = (try? context.count(for: request)) ?? 0
        }
        return count
    }

    // MARK: - Seeding

    private static func seedSynchronously(count: Int, container: NSPersistentContainer, currencyCode: String) -> Summary {
        let started = Date()
        let context = container.newBackgroundContext()
        var insertedExpenses = 0
        var insertedCategories = 0

        context.performAndWait {
            let categoryIDs = ensureSeededCategories(in: context, inserted: &insertedCategories)
            insertedExpenses = batchInsertExpenses(
                count: count,
                customCategoryIDs: categoryIDs,
                currencyCode: currencyCode,
                in: context,
                container: container
            )
        }

        return Summary(
            insertedExpenses: insertedExpenses,
            insertedCategories: insertedCategories,
            elapsed: Date().timeIntervalSince(started)
        )
    }

    /// Six custom categories (same names / icons / colors as the script,
    /// prefixed so they can be deleted by name). Reused if present.
    private static func ensureSeededCategories(in context: NSManagedObjectContext, inserted: inout Int) -> [UUID] {
        let specs: [(name: String, icon: String, color: String)] = [
            ("Coffee", "cup.and.saucer.fill", "mauve"),
            ("Games", "gamecontroller.fill", "jordyBlue"),
            ("Pets", "pawprint.fill", "teaRose"),
            ("Tech", "desktopcomputer", "electricBlue"),
            ("Self Care", "leaf.fill", "celadon"),
            ("Events", "ticket.fill", "pinkLavender")
        ]

        let request: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "name BEGINSWITH %@", seededCategoryPrefix)
        let existing = (try? context.fetch(request)) ?? []
        var idsByName: [String: UUID] = [:]
        for entity in existing {
            if let name = entity.name, let id = entity.id { idsByName[name] = id }
        }

        var ids: [UUID] = []
        for spec in specs {
            let fullName = seededCategoryPrefix + spec.name
            if let id = idsByName[fullName] {
                ids.append(id)
                continue
            }
            let entity = CustomCategoryEntity(context: context)
            let id = UUID()
            entity.id = id
            entity.name = fullName
            entity.icon = spec.icon
            entity.colorName = spec.color
            ids.append(id)
            inserted += 1
        }
        if context.hasChanges {
            try? context.save()
        }
        return ids
    }

    private static let titles = [
        "Coffee", "Lunch", "Groceries", "Uber", "Snacks", "Movie", "Fuel", "Pharmacy",
        "Online Order", "Dinner", "Bus Ticket", "Gym Day Pass", "Gift", "Hotel", "Flight",
        "Book", "Subscription", "Electricity Bill", "Water Bill", "Phone Recharge"
    ]

    private static let defaultCategories: [Expense.Category] = [
        .groceries, .food, .transportation, .entertainment, .shopping,
        .utilities, .health, .education, .travel, .other
    ]

    private static let tagPool: [String] = (1...30).map { "tag\($0)" }

    private static let paymentMethods = PaymentMethod.allCases

    /// One `NSBatchInsertRequest` for all rows. The managed-object
    /// handler variant is used (not the dictionary one) so the
    /// Transformable `tags` attribute goes through the normal property
    /// setter and its value transformer.
    private static func batchInsertExpenses(
        count: Int,
        customCategoryIDs: [UUID],
        currencyCode: String,
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) -> Int {
        guard count > 0 else { return 0 }

        var rng = SeedRNG(seed: UInt64(Date().timeIntervalSince1970))
        let calendar = Calendar.current
        let now = Date()
        var index = 0

        let request = NSBatchInsertRequest(entity: ExpenseEntity.entity()) { (object: NSManagedObject) -> Bool in
            guard index < count else { return true }
            guard let entity = object as? ExpenseEntity else { return true }
            defer { index += 1 }

            entity.id = UUID()
            entity.title = titles[rng.nextInt(titles.count)]
            entity.currency = currencyCode

            // Amount tiers: 80 % small, 17 % medium, 3 % large.
            let p = rng.nextDouble01()
            if p < 0.80 {
                entity.amount = Double(20 + rng.nextInt(800)) + (rng.nextDouble01() * 0.99)
            } else if p < 0.97 {
                entity.amount = Double(800 + rng.nextInt(5000)) + (rng.nextDouble01() * 0.99)
            } else {
                entity.amount = Double(5000 + rng.nextInt(20000)) + (rng.nextDouble01() * 0.99)
            }

            // 3 % today (hot window / streak paths), rest uniform over
            // the last 730 days with a random time of day.
            if rng.nextDouble01() < 0.03 {
                let startOfToday = calendar.startOfDay(for: now)
                let secondsIntoToday = min(rng.nextInt(24 * 60 * 60), max(1, Int(now.timeIntervalSince(startOfToday))))
                entity.date = startOfToday.addingTimeInterval(TimeInterval(secondsIntoToday))
            } else {
                let offsetDays = 1 + rng.nextInt(729)
                let offsetSeconds = rng.nextInt(24 * 60 * 60)
                let day = calendar.date(byAdding: .day, value: -offsetDays, to: now) ?? now
                entity.date = calendar.date(byAdding: .second, value: -offsetSeconds, to: day) ?? day
            }

            // 18 % custom categories, rest spread over the defaults.
            if !customCategoryIDs.isEmpty, rng.nextDouble01() < 0.18 {
                entity.category = Expense.Category.custom.rawValue
                entity.customCategoryId = customCategoryIDs[rng.nextInt(customCategoryIDs.count)]
            } else {
                entity.category = defaultCategories[rng.nextInt(defaultCategories.count)].rawValue
                entity.customCategoryId = nil
            }

            entity.isRefund = rng.nextDouble01() < 0.03
            entity.notes = rng.nextDouble01() < 0.12 ? "[seed] Note \(index % 17)" : nil
            entity.paymentMethod = rng.nextDouble01() < 0.40
                ? paymentMethods[rng.nextInt(paymentMethods.count)].rawValue
                : nil
            entity.receiptImagePath = nil

            // 20 % tagged with 1–3 distinct tags from a pool of 30.
            if rng.nextDouble01() < 0.20 {
                var picked: [String] = []
                let wanted = 1 + rng.nextInt(3)
                while picked.count < wanted {
                    let tag = tagPool[rng.nextInt(tagPool.count)]
                    if !picked.contains(tag) { picked.append(tag) }
                }
                entity.tags = picked as NSArray
            } else {
                entity.tags = nil
            }

            // Marker. `isFromSubscription` stays false so the row never
            // reads as a recurring charge.
            entity.isFromSubscription = false
            entity.subscriptionId = sentinelSubscriptionID

            return false
        }
        request.resultType = .objectIDs

        do {
            let result = try context.execute(request) as? NSBatchInsertResult
            let objectIDs = (result?.result as? [NSManagedObjectID]) ?? []
            mergeChanges([NSInsertedObjectsKey: objectIDs], into: container)
            // `index` is how many rows the handler actually filled; the
            // object-ID list is the authoritative count when present.
            return objectIDs.isEmpty ? index : objectIDs.count
        } catch {
            print("DebugExpenseSeeder: batch insert failed — \(error)")
            return 0
        }
    }

    // MARK: - Helpers

    private static func batchDelete(
        _ fetch: NSFetchRequest<NSFetchRequestResult>,
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) -> Int {
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        request.resultType = .resultTypeObjectIDs
        do {
            let result = try context.execute(request) as? NSBatchDeleteResult
            let objectIDs = (result?.result as? [NSManagedObjectID]) ?? []
            mergeChanges([NSDeletedObjectsKey: objectIDs], into: container)
            return objectIDs.count
        } catch {
            print("DebugExpenseSeeder: batch delete failed — \(error)")
            return 0
        }
    }

    /// Batch requests bypass contexts, so the view context (and the
    /// category FRC that watches it) is told explicitly.
    private static func mergeChanges(_ changes: [AnyHashable: Any], into container: NSPersistentContainer) {
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [container.viewContext])
    }

    /// Mirrors `ExpenseViewModel`'s persisted selection so seeded rows
    /// use the user's currency (falls back to USD, like the model).
    private static func currentCurrencyCode() -> String {
        let stored = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedCurrency)
        return Expense.Currency(rawValue: stored ?? "")?.rawValue ?? Expense.Currency.usd.rawValue
    }

    /// Same LCG as `Scripts/generate_stress_test_export.swift`.
    private struct SeedRNG {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
        mutating func next() -> UInt64 {
            state = 6364136223846793005 &* state &+ 1
            return state
        }
        mutating func nextInt(_ upperBound: Int) -> Int {
            precondition(upperBound > 0)
            return Int(next() % UInt64(upperBound))
        }
        mutating func nextDouble01() -> Double {
            let v = next() >> 11
            return Double(v) / Double(1 << 53)
        }
    }
}
#endif
