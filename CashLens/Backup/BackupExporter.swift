import Foundation
import CoreData

/// `BackupExporter` builds a `BackupBundle` from the live Core Data store and
/// `UserDefaults`, then serializes it to disk in either JSON (full restore) or
/// CSV (spreadsheet-friendly, expenses-focused) form.
///
/// All work happens on a background Core Data context — safe to call from any
/// thread. The returned `URL` lives in the app's Documents directory and can
/// be shared via `UIActivityViewController` or written to Files.
enum BackupExporter {

    // MARK: - Public API

    enum Format {
        case json
        case csv
        /// Pure-Swift `.cashlens-archive` zip — `data.json` plus every
        /// receipt file the user has attached, bundled into a single
        /// portable file. The only format that survives an iPhone
        /// upgrade with receipts intact.
        case archive
    }

    /// Build a complete `BackupBundle` reflecting the current state of the app.
    /// Pulls Core Data on a background context and reads UserDefaults on the caller's thread.
    static func buildBundle() -> BackupBundle {
        let payload = fetchPayload()
        let preferences = readPreferences()
        return BackupBundle(
            schema: .current(),
            data: payload,
            preferences: preferences
        )
    }

    /// Write the bundle to disk in the requested format.
    /// - Returns: A file URL on success, `nil` on failure.
    static func write(_ bundle: BackupBundle, as format: Format) -> URL? {
        switch format {
        case .json:
            return writeJSON(bundle)
        case .csv:
            return writeCSV(bundle)
        case .archive:
            return writeArchive(bundle)
        }
    }

    // MARK: - Core Data Fetch

    private static func fetchPayload() -> BackupBundle.Payload {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var expenses: [Expense] = []
        var subscriptions: [Subscription] = []
        var customs: [CustomCategory] = []
        var budgets: [CodableBudget] = []

        context.performAndWait {
            do {
                let expenseRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                expenseRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
                expenses = try context.fetch(expenseRequest).toExpenses()

                let subRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
                subRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
                    NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
                ]
                subscriptions = try context.fetch(subRequest).toSubscriptions()

                let catRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
                catRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
                customs = try context.fetch(catRequest).toCustomCategories()

                let budgetRequest: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
                budgetRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \BudgetEntity.isActive, ascending: false),
                    NSSortDescriptor(keyPath: \BudgetEntity.createdAt, ascending: true)
                ]
                budgets = try context.fetch(budgetRequest).toBudgets().map(CodableBudget.init)
            } catch {
                print("BackupExporter: fetch failed — \(error.localizedDescription)")
            }
        }

        let deleted = (UserDefaults.standard.array(forKey: UserDefaultsKeys.deletedDefaultCategories) as? [String]) ?? []

        return BackupBundle.Payload(
            expenses: expenses,
            subscriptions: subscriptions,
            customCategories: customs,
            budgets: budgets,
            deletedDefaultCategories: deleted
        )
    }

    // MARK: - Preferences

    private static func readPreferences() -> BackupBundle.Preferences {
        let defaults = UserDefaults.standard

        var prefs = BackupBundle.Preferences()

        if let name = defaults.string(forKey: UserDefaultsKeys.userName)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            prefs.userName = name
        }
        if let currency = defaults.string(forKey: UserDefaultsKeys.selectedCurrency), !currency.isEmpty {
            prefs.selectedCurrency = currency
        }
        if let timeFrame = defaults.string(forKey: UserDefaultsKeys.defaultHomeTimeFrame), !timeFrame.isEmpty {
            prefs.defaultHomeTimeFrame = timeFrame
        }
        if let appearance = defaults.string(forKey: UserDefaultsKeys.appearanceMode), !appearance.isEmpty {
            prefs.appearanceMode = appearance
        }
        if let data = defaults.data(forKey: UserDefaultsKeys.preferredSummaryCategories),
           let tokens = try? JSONDecoder().decode([String].self, from: data) {
            prefs.preferredSummaryCategories = tokens
        }

        prefs.notifications = readNotifications()

        return prefs
    }

    private static func readNotifications() -> BackupBundle.NotificationPreferences? {
        let defaults = UserDefaults.standard
        var notifs = BackupBundle.NotificationPreferences()
        var any = false

        if defaults.object(forKey: UserDefaultsKeys.weeklySummaryEnabled) != nil {
            notifs.weeklySummary = BackupBundle.WeeklySchedule(
                enabled: defaults.bool(forKey: UserDefaultsKeys.weeklySummaryEnabled),
                weekday: defaults.integer(forKey: UserDefaultsKeys.weeklySummaryWeekday),
                hour: defaults.integer(forKey: UserDefaultsKeys.weeklySummaryHour),
                minute: defaults.integer(forKey: UserDefaultsKeys.weeklySummaryMinute)
            )
            any = true
        }
        if defaults.object(forKey: UserDefaultsKeys.monthlyDigestEnabled) != nil {
            notifs.monthlyDigest = BackupBundle.MonthlySchedule(
                enabled: defaults.bool(forKey: UserDefaultsKeys.monthlyDigestEnabled),
                dayOfMonth: defaults.integer(forKey: UserDefaultsKeys.monthlyDigestDayOfMonth),
                hour: defaults.integer(forKey: UserDefaultsKeys.monthlyDigestHour),
                minute: defaults.integer(forKey: UserDefaultsKeys.monthlyDigestMinute)
            )
            any = true
        }
        if defaults.object(forKey: UserDefaultsKeys.backupReminderEnabled) != nil {
            notifs.backupReminder = BackupBundle.MonthlySchedule(
                enabled: defaults.bool(forKey: UserDefaultsKeys.backupReminderEnabled),
                dayOfMonth: defaults.integer(forKey: UserDefaultsKeys.backupReminderDayOfMonth),
                hour: defaults.integer(forKey: UserDefaultsKeys.backupReminderHour),
                minute: defaults.integer(forKey: UserDefaultsKeys.backupReminderMinute)
            )
            any = true
        }

        return any ? notifs : nil
    }

    // MARK: - JSON Writer

    private static func writeJSON(_ bundle: BackupBundle) -> URL? {
        let url = makeFileURL(extension: "cashlens.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bundle)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("BackupExporter: JSON write failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - CSV Writer

    /// CashLens v2 CSV is a **flat, RFC 4180-style** file optimized for
    /// spreadsheet apps (Excel, Numbers, Google Sheets). It exports expenses
    /// only — subscriptions, custom categories, budgets, and preferences are
    /// **not** included. Use the JSON format for a full restore.
    ///
    /// Columns:
    /// `Date, Title, Amount, Currency, Category, Custom Category, Notes, Tags, ID, Subscription ID, From Subscription`
    ///
    /// `Date` uses ISO 8601 (`yyyy-MM-dd'T'HH:mm:ssXXXXX`) so spreadsheet apps
    /// can parse it unambiguously regardless of locale.
    private static func writeCSV(_ bundle: BackupBundle) -> URL? {
        let url = makeFileURL(extension: "csv")

        // `Is Refund` was added in v2.1 and `Payment Method` in v2.2; both
        // live at the end so older importers that hard-coded the v2 column
        // count keep working — they just ignore the trailing columns.
        let header = [
            "Date", "Title", "Amount", "Currency", "Category",
            "Custom Category", "Notes", "Tags", "ID", "Subscription ID", "From Subscription", "Is Refund", "Payment Method"
        ]
        var lines: [String] = [header.map(csvEscape).joined(separator: ",")]

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        // Map custom category id → display name once for readable CSV.
        let customNames: [UUID: String] = bundle.data.customCategories.reduce(into: [:]) { map, cat in
            map[cat.id] = cat.name
        }

        for e in bundle.data.expenses {
            let categoryDisplay = e.category == .custom
                ? (e.customCategoryId.flatMap { customNames[$0] } ?? "Custom")
                : e.category.rawValue
            let customColumn = e.category == .custom
                ? (e.customCategoryId.flatMap { customNames[$0] } ?? "")
                : ""
            let amountString = String(format: "%.2f", e.amount)
            let row: [String] = [
                dateFormatter.string(from: e.date),
                e.title,
                amountString,
                e.currency.rawValue,
                categoryDisplay,
                customColumn,
                e.notes ?? "",
                (e.tags ?? []).joined(separator: ";"),
                e.id.uuidString,
                e.subscriptionId?.uuidString ?? "",
                e.isFromSubscription ? "true" : "false",
                e.isRefund ? "true" : "false",
                e.paymentMethod?.rawValue ?? ""
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n") + "\n"

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("BackupExporter: CSV write failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Archive (.cashlens-archive zip) writer
    //
    // Layout inside the zip:
    //
    //   data.json                 — full BackupBundle, identical bytes to
    //                               what `writeJSON` would produce.
    //   receipts/<filename>.jpg   — every receipt file currently
    //                               referenced by an expense's
    //                               `receiptImagePath`. Filename matches
    //                               the path stored in the model so the
    //                               importer can drop them straight back
    //                               into Documents/Receipts/ without any
    //                               renaming / fixup.
    //
    // The archive is **STORE-method only** (no compression) — JPEGs are
    // already compressed, and JSON is small enough that re-deflating it
    // for a few KB savings doesn't justify pulling in the Compression
    // framework.
    //
    // Backward compatibility: this is a brand-new format, so nothing to
    // be backward-compatible with. Forward compatibility lives in the
    // existing JSON schema (`BackupBundle.minimumReaderVersion`) — if a
    // future archive needs richer features, the JSON inside bumps the
    // schema and old readers refuse cleanly.

    /// Write the bundle plus all referenced receipt files to a single
    /// `.cashlens-archive` zip on disk. Returns the file URL on
    /// success, `nil` on failure (with an error logged via `print`).
    private static func writeArchive(_ bundle: BackupBundle) -> URL? {
        let url = makeFileURL(extension: "cashlens-archive")

        // Encode the JSON payload identically to `writeJSON` so an
        // importer that strips the zip and looks at `data.json` sees
        // the exact same bytes as a `.cashlens.json` export. Kept
        // pretty-printed + sorted for diff-friendliness when users
        // inspect their backups manually.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        do {
            jsonData = try encoder.encode(bundle)
        } catch {
            print("BackupExporter: archive JSON encode failed — \(error.localizedDescription)")
            return nil
        }

        var entries: [ZipWriter.Entry] = [
            ZipWriter.Entry(name: "data.json", data: jsonData)
        ]

        // Walk every expense and pull its receipt file off disk into
        // the archive. We dedupe by filename in case multiple
        // expenses point at the same image (currently impossible —
        // each save creates a new UUID — but defensible against any
        // future "share receipt across split-bills" feature).
        var seenReceiptNames: Set<String> = []
        for expense in bundle.data.expenses {
            guard let filename = expense.receiptImagePath,
                  !seenReceiptNames.contains(filename),
                  let fileURL = ReceiptStorage.url(for: filename),
                  let data = try? Data(contentsOf: fileURL) else {
                continue
            }
            // Path inside the zip — `receipts/<filename>` mirrors the
            // on-disk structure under Documents/, so the importer's
            // restore step is a literal "move to Documents/Receipts/".
            entries.append(
                ZipWriter.Entry(name: "receipts/\(filename)", data: data)
            )
            seenReceiptNames.insert(filename)
        }

        do {
            try ZipWriter.write(entries: entries, to: url)
            return url
        } catch {
            print("BackupExporter: archive write failed — \(error.localizedDescription)")
            // Don't leave a partially-written file lying around — the
            // writer already does atomic swap, but the rare failure
            // before swap could still leave a `.tmp` sibling. Sweep.
            try? FileManager.default.removeItem(at: url.appendingPathExtension("tmp"))
            return nil
        }
    }

    // MARK: - Helpers

    /// Escape a CSV field per RFC 4180:
    /// - Wrap in double quotes if the field contains comma, quote, newline, or carriage return.
    /// - Escape internal `"` as `""`.
    private static func csvEscape(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        if !needsQuoting { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func makeFileURL(extension ext: String) -> URL {
        let stamp = formattedTimestamp()
        let name = "CashLens_Backup_\(stamp).\(ext)"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    private static func formattedTimestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }
}
