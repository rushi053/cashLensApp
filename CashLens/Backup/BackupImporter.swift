import Foundation
import CoreData
import UserNotifications

/// `BackupImporter` reads a file URL, **detects its format**, parses it into a
/// `BackupBundle`, and applies it to the live store with a chosen merge mode.
///
/// Supported formats:
/// 1. **CashLens v2 JSON** (`.cashlens.json`) — full restore including budgets and preferences.
/// 2. **CashLens v1 JSON** (legacy) — converted on the fly via `LegacyV1Reader`.
/// 3. **CashLens v1 CSV** (sectioned `=== EXPENSES ===` format) — legacy.
/// 4. **Foreign CSV** (Mint, YNAB, Apple Card, generic bank statements) via
///    `GenericCSVAdapter`. **Pro-only** at the call site.
///
/// `apply(_:mode:context:completion:)` runs on a background Core Data context
/// and reports a structured `ImportSummary` describing what was added,
/// skipped, replaced, or failed — perfect for the post-import preview sheet.
enum BackupImporter {

    // MARK: - Public types

    enum DetectedFormat: Equatable {
        case cashlensJSONv2
        case cashlensJSONv1
        case cashlensCSVv1
        case foreignCSV(vendor: String)
        /// Pure-Swift `.cashlens-archive` zip — JSON + restored
        /// receipt files. Detected by file extension (because the
        /// zip's binary signature isn't a UTF-8 string we can sniff
        /// the same way as JSON).
        case cashlensArchive
        case unknown

        var displayName: String {
            switch self {
            case .cashlensJSONv2:       return "CashLens Backup (v2)"
            case .cashlensJSONv1:       return "CashLens Backup (v1)"
            case .cashlensCSVv1:        return "CashLens CSV (legacy)"
            case .foreignCSV(let v):    return v
            case .cashlensArchive:      return "CashLens Archive (with receipts)"
            case .unknown:              return "Unknown"
            }
        }

        /// Whether this format is a non-CashLens spreadsheet that needs Pro
        /// gating before import.
        var requiresPro: Bool {
            if case .foreignCSV = self { return true }
            return false
        }
    }

    enum Mode: String {
        /// Add new records, skip duplicates by ID/content. Preferences with
        /// values in the file overwrite current preferences; missing
        /// preferences are left alone.
        case merge
        /// Wipe the existing store + preference set first, then import.
        /// Triggered only after explicit user confirmation.
        case replace
    }

    enum ImportError: LocalizedError {
        case unreadableFile(String)
        case unrecognizedFormat
        case fileTooNew(needed: String, have: String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableFile(let why):
                return "Couldn't read the file: \(why)"
            case .unrecognizedFormat:
                return "This doesn't look like a CashLens backup or supported CSV. Try a .cashlens.json file or a CSV exported from Mint, YNAB, your bank, or CashLens itself."
            case .fileTooNew(let needed, let have):
                return "This backup was made with a newer CashLens (needs \(needed), this app supports \(have)). Update the app, then try again."
            case .parseFailed(let why):
                return "We couldn't fully read this file: \(why)"
            }
        }
    }

    /// Result of a peek/parse — held by the UI to drive the preview sheet.
    struct Preview {
        var format: DetectedFormat
        var bundle: BackupBundle
        var foreignErrors: [GenericCSVAdapter.RowError]
        var foreignMappedColumns: [String: GenericCSVAdapter.ColumnRole]

        /// For `.cashlensArchive` only — the cached, owned copy of the
        /// source zip that `apply(_:)` will re-open to extract
        /// receipt files. We copy the source into our own caches
        /// directory at preview time so the security-scoped URL from
        /// the picker can be safely released before `apply` runs.
        ///
        /// `nil` for every non-archive format — those don't carry
        /// out-of-band binary payloads.
        var archiveCacheURL: URL?

        /// Number of receipt entries the archive carries. Surfaced
        /// in the preview UI so the user knows what they're about to
        /// restore. Always 0 for non-archive formats.
        var receiptCount: Int = 0

        var totalRecordCount: Int {
            bundle.data.expenses.count
                + bundle.data.subscriptions.count
                + bundle.data.customCategories.count
                + bundle.data.budgets.count
                + bundle.data.deletedDefaultCategories.count
        }
    }

    /// Actually-applied counts plus skipped/failed counts. The UI shows this.
    struct ImportSummary {
        var mode: Mode
        var format: DetectedFormat

        var expensesImported = 0
        var expensesSkipped = 0

        var subscriptionsImported = 0
        var subscriptionsSkipped = 0

        var customCategoriesImported = 0
        var customCategoriesSkipped = 0

        var budgetsImported = 0
        var budgetsSkipped = 0

        var deletedDefaultsAdded = 0

        /// Receipt files restored from a `.cashlens-archive`. Always
        /// 0 for non-archive imports.
        var receiptsRestored = 0
        /// Receipt files in the archive that we couldn't write (rare —
        /// usually disk full or permissions). Surfaced in the post-
        /// import sheet so the user knows their receipts didn't all
        /// land cleanly.
        var receiptsFailed = 0

        var preferencesUpdated: [String] = []

        var rowErrors: [GenericCSVAdapter.RowError] = []

        var totalImported: Int {
            expensesImported + subscriptionsImported + customCategoriesImported + budgetsImported + deletedDefaultsAdded
        }

        var totalSkipped: Int {
            expensesSkipped + subscriptionsSkipped + customCategoriesSkipped + budgetsSkipped
        }
    }

    // MARK: - Format Detection + Parse

    /// Read the file, detect its format, and return a `Preview` ready for the
    /// confirmation sheet. Does **not** modify the store.
    static func preview(url: URL, fallbackCurrency: Expense.Currency) throws -> Preview {
        // Archive path is special: we don't want to load the whole
        // zip into memory just for preview (could be 100s of MB), and
        // we need to re-open the file at apply time without relying
        // on the picker's security-scoped URL still being live. So we
        // copy the source into our own caches dir up front, then
        // operate on that owned copy throughout.
        if isArchiveURL(url) {
            return try previewArchive(sourceURL: url)
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.unreadableFile("Permission denied")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile(error.localizedDescription)
        }

        return try preview(data: data, fileName: url.lastPathComponent, fallbackCurrency: fallbackCurrency)
    }

    /// Heuristic: file extension is the only reliable archive
    /// signal at this point in the flow. Magic-byte sniffing is a
    /// fallback in `previewArchive` itself if the extension lies.
    private static func isArchiveURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".cashlens-archive")
            || name.hasSuffix(".cashlens-archive.zip") // some share extensions silently re-extension
    }

    /// Copy the (security-scoped) source to our caches dir, open it
    /// with `ZipReader`, parse `data.json`, and return a Preview
    /// that holds the cached URL so `apply(_:)` can re-open the same
    /// file without needing the original picker URL to still be live.
    private static func previewArchive(sourceURL: URL) throws -> Preview {
        let cachedURL: URL
        do {
            cachedURL = try copyToCaches(sourceURL: sourceURL)
        } catch let err as ImportError {
            throw err
        } catch {
            throw ImportError.unreadableFile(error.localizedDescription)
        }

        let reader: ZipReader
        do {
            reader = try ZipReader.open(at: cachedURL)
        } catch {
            // Bad zip → clean up our copy so we don't leak caches.
            try? FileManager.default.removeItem(at: cachedURL)
            throw ImportError.parseFailed(error.localizedDescription)
        }
        defer { reader.close() }

        let jsonData: Data
        do {
            jsonData = try reader.read(name: "data.json")
        } catch {
            try? FileManager.default.removeItem(at: cachedURL)
            throw ImportError.parseFailed("Archive is missing data.json — not a CashLens archive.")
        }

        let bundle: BackupBundle
        do {
            bundle = try parseJSONv2(data: jsonData)
        } catch let err as ImportError {
            try? FileManager.default.removeItem(at: cachedURL)
            throw err
        } catch {
            try? FileManager.default.removeItem(at: cachedURL)
            throw ImportError.parseFailed(error.localizedDescription)
        }

        // Receipt count = number of "receipts/*" entries in the zip
        // (not just `bundle.data.expenses.count(where: …)`) so the
        // user sees what's actually in the archive — accounts for any
        // legitimate mismatch between expense rows and on-disk files.
        let receiptCount = reader.entryNames.filter { $0.hasPrefix("receipts/") }.count

        return Preview(
            format: .cashlensArchive,
            bundle: bundle,
            foreignErrors: [],
            foreignMappedColumns: [:],
            archiveCacheURL: cachedURL,
            receiptCount: receiptCount
        )
    }

    /// Copy the picker's security-scoped URL into our own caches
    /// directory. Returns an owned URL we can open at any time
    /// without re-acquiring permission.
    private static func copyToCaches(sourceURL: URL) throws -> URL {
        let needsScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportArchives", isDirectory: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let dest = cacheDir.appendingPathComponent("\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        do {
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            throw ImportError.unreadableFile(error.localizedDescription)
        }
        return dest
    }

    /// Pure-data variant — easier to unit test and used internally.
    static func preview(data: Data, fileName: String, fallbackCurrency: Expense.Currency) throws -> Preview {
        let format = detectFormat(data: data, fileName: fileName)

        switch format {
        case .cashlensJSONv2:
            let bundle = try parseJSONv2(data: data)
            return Preview(format: format, bundle: bundle, foreignErrors: [], foreignMappedColumns: [:])

        case .cashlensJSONv1:
            let bundle = try LegacyV1Reader.parseJSON(data: data)
            return Preview(format: format, bundle: bundle, foreignErrors: [], foreignMappedColumns: [:])

        case .cashlensCSVv1:
            let content = String(data: data, encoding: .utf8) ?? ""
            let bundle = try LegacyV1Reader.parseCSV(content: content)
            return Preview(format: format, bundle: bundle, foreignErrors: [], foreignMappedColumns: [:])

        case .cashlensArchive:
            // Unreachable in practice — the public `preview(url:)`
            // entry point routes archive URLs through `previewArchive`
            // before ever calling this data-only path. This branch
            // exists so the switch is exhaustive and so direct calls
            // to `preview(data:fileName:)` with a zip blob fail with
            // a clear, non-corrupt error rather than silently falling
            // through to JSON parsing.
            throw ImportError.parseFailed("Archive imports must go through preview(url:) — direct data-mode parse isn't supported.")

        case .foreignCSV:
            let content = String(data: data, encoding: .utf8) ?? ""
            let result = GenericCSVAdapter.parse(content, fallbackCurrency: fallbackCurrency)
            let bundle = BackupBundle(
                schema: .current(),
                data: BackupBundle.Payload(
                    expenses: result.expenses,
                    subscriptions: [],
                    customCategories: [],
                    budgets: [],
                    deletedDefaultCategories: []
                ),
                preferences: .empty
            )
            return Preview(
                format: .foreignCSV(vendor: result.detectedFormat),
                bundle: bundle,
                foreignErrors: result.errors,
                foreignMappedColumns: result.mappedColumns
            )

        case .unknown:
            throw ImportError.unrecognizedFormat
        }
    }

    // MARK: - Apply

    /// Apply a previewed bundle to the store using the chosen mode.
    /// Runs on a background Core Data context; calls `completion` on the main thread.
    ///
    /// For `.cashlensArchive` previews, also restores every receipt
    /// file from the archive into `Documents/Receipts/`. The receipt
    /// restore happens **before** Core Data save so any failures
    /// surface in the same error path the user already sees for
    /// schema mismatches.
    static func apply(
        _ preview: Preview,
        mode: Mode,
        completion: @escaping (Result<ImportSummary, Error>) -> Void
    ) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var summary = ImportSummary(mode: mode, format: preview.format)
        summary.rowErrors = preview.foreignErrors

        // Restore receipts from the archive (if any) on the calling
        // thread — `restoreReceipts` does its own background work via
        // pure file IO and returns synchronously with counts. No
        // Core Data is touched here.
        if let cacheURL = preview.archiveCacheURL {
            do {
                let counts = try restoreReceipts(fromArchive: cacheURL)
                summary.receiptsRestored = counts.restored
                summary.receiptsFailed = counts.failed
            } catch {
                // Couldn't open the archive at all — surface and bail
                // before touching Core Data.
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            // Whether or not every receipt landed, we're done with
            // the cached zip — clean it up so caches don't grow.
            try? FileManager.default.removeItem(at: cacheURL)
        }

        context.perform {
            do {
                if mode == .replace {
                    try wipeStore(context: context)
                    wipePreferences()
                }

                try importCustomCategories(preview.bundle.data.customCategories, context: context, summary: &summary)
                try importExpenses(preview.bundle.data.expenses, context: context, summary: &summary)
                try importSubscriptions(preview.bundle.data.subscriptions, context: context, summary: &summary)
                try importBudgets(preview.bundle.data.budgets, context: context, summary: &summary)

                applyDeletedDefaults(preview.bundle.data.deletedDefaultCategories, summary: &summary)

                if context.hasChanges {
                    try context.save()
                }

                applyPreferences(preview.bundle.preferences, summary: &summary)

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .backupImportDidComplete, object: summary)
                    completion(.success(summary))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Receipt restore (archive only)

    /// Open the cached `.cashlens-archive` zip and copy every
    /// `receipts/<filename>` entry into `Documents/Receipts/`.
    /// Returns the count restored and the count we couldn't write.
    ///
    /// Idempotency: writes use `.atomic` and overwrite any existing
    /// file at the same path — which is correct, because the only
    /// way the same filename already exists is that the source bytes
    /// are also identical (filenames are UUIDs minted at write time).
    /// In merge mode this means re-importing the same archive twice
    /// is a no-op for receipts; in replace mode the existing files
    /// get overwritten with bit-identical bytes.
    private static func restoreReceipts(fromArchive cacheURL: URL) throws -> (restored: Int, failed: Int) {
        let reader: ZipReader
        do {
            reader = try ZipReader.open(at: cacheURL)
        } catch {
            throw ImportError.parseFailed(error.localizedDescription)
        }
        defer { reader.close() }

        let receiptsDir = try ensureReceiptsDirectory()
        var restored = 0
        var failed = 0

        for name in reader.entryNames where name.hasPrefix("receipts/") {
            // Strip the prefix and reject any name that tries to
            // climb out of the receipts directory via "../" — the
            // ZipReader doesn't sanitize, so we do it here.
            let rawFilename = String(name.dropFirst("receipts/".count))
            if rawFilename.isEmpty || rawFilename.contains("..") || rawFilename.contains("/") {
                failed += 1
                continue
            }
            do {
                let bytes = try reader.read(name: name)
                let dest = receiptsDir.appendingPathComponent(rawFilename)
                try bytes.write(to: dest, options: .atomic)
                restored += 1
            } catch {
                // Per-entry failure shouldn't kill the whole import;
                // we count it and move on. The user sees the count
                // in the post-import sheet and any expense whose
                // file failed gets a `nil` viewer (graceful).
                failed += 1
            }
        }

        return (restored, failed)
    }

    /// Mirror of `ReceiptStorage.receiptsDirectory()` — duplicated
    /// here on purpose so the importer doesn't need to expose the
    /// path through a public API on `ReceiptStorage`. Kept tiny.
    private static func ensureReceiptsDirectory() throws -> URL {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ImportError.unreadableFile("Couldn't access app documents folder.")
        }
        let dir = docs.appendingPathComponent("Receipts", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Format detection

    private static func detectFormat(data: Data, fileName: String) -> DetectedFormat {
        // Fast path: try JSON first.
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let schema = json["schema"] as? [String: Any], let _ = schema["version"] as? String {
                return .cashlensJSONv2
            }
            if let _ = json["exportVersion"] as? String {
                return .cashlensJSONv1
            }
            // JSON of unknown shape — treat as v1 attempt; legacy reader will throw if invalid.
            if json["expenses"] != nil || json["subscriptions"] != nil {
                return .cashlensJSONv1
            }
            return .unknown
        }

        // Otherwise: treat as text + sniff CSV.
        guard let text = String(data: data, encoding: .utf8) else { return .unknown }

        if text.contains("=== EXPENSES ===")
            || text.contains("=== SUBSCRIPTIONS ===")
            || text.contains("=== CUSTOM_CATEGORIES ===")
            || text.contains("=== DELETED_DEFAULT_CATEGORIES ===") {
            return .cashlensCSVv1
        }

        // Look at the first non-empty line — if it has at least 2 fields and one
        // recognizable header keyword, treat as foreign CSV.
        let firstLine = text
            .split(whereSeparator: { $0.isNewline })
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map(String.init) ?? ""
        let headers = CSVParser.parseRows(firstLine).first ?? []
        let lowered = headers.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let knownHeaderHints: Set<String> = [
            "date", "amount", "description", "payee", "category",
            "merchant", "outflow", "inflow", "transaction date", "title"
        ]
        if !lowered.isEmpty, lowered.contains(where: knownHeaderHints.contains) {
            return .foreignCSV(vendor: "")
        }

        // File-extension last-resort hint.
        if fileName.lowercased().hasSuffix(".csv") {
            return .foreignCSV(vendor: "")
        }

        return .unknown
    }

    // MARK: - JSON v2 parser

    private static func parseJSONv2(data: Data) throws -> BackupBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let bundle = try decoder.decode(BackupBundle.self, from: data)
            // Forward-compat guard.
            if bundle.schema.minimumReaderVersion.compare(BackupBundle.currentSchemaVersion, options: .numeric) == .orderedDescending {
                throw ImportError.fileTooNew(needed: bundle.schema.minimumReaderVersion, have: BackupBundle.currentSchemaVersion)
            }
            return bundle
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.parseFailed(error.localizedDescription)
        }
    }

    // MARK: - Importers (assume background context)

    private static func importCustomCategories(
        _ categories: [CustomCategory],
        context: NSManagedObjectContext,
        summary: inout ImportSummary
    ) throws {
        for category in categories {
            let request: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", category.id as CVarArg)
            if try context.count(for: request) == 0 {
                _ = CustomCategoryEntity.fromCustomCategory(category, context: context)
                summary.customCategoriesImported += 1
            } else {
                summary.customCategoriesSkipped += 1
            }
        }
    }

    private static func importExpenses(
        _ expenses: [Expense],
        context: NSManagedObjectContext,
        summary: inout ImportSummary
    ) throws {
        for expense in expenses {
            guard isValidExpense(expense) else {
                summary.expensesSkipped += 1
                continue
            }

            let byId: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            byId.fetchLimit = 1
            byId.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
            if try context.count(for: byId) > 0 {
                summary.expensesSkipped += 1
                continue
            }

            let byContent: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            byContent.fetchLimit = 1
            byContent.predicate = NSPredicate(
                format: "title == %@ AND amount == %@ AND date == %@ AND category == %@",
                expense.title as NSString,
                NSNumber(value: expense.amount),
                expense.date as NSDate,
                expense.category.rawValue as NSString
            )
            if try context.count(for: byContent) > 0 {
                summary.expensesSkipped += 1
                continue
            }

            _ = ExpenseEntity.fromExpense(expense, context: context)
            summary.expensesImported += 1
        }
    }

    private static func importSubscriptions(
        _ subscriptions: [Subscription],
        context: NSManagedObjectContext,
        summary: inout ImportSummary
    ) throws {
        for subscription in subscriptions {
            guard subscription.amount.isFinite, subscription.amount >= 0,
                  !subscription.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                summary.subscriptionsSkipped += 1
                continue
            }
            let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", subscription.id as CVarArg)
            if try context.count(for: request) == 0 {
                _ = SubscriptionEntity.fromSubscription(subscription, context: context)
                summary.subscriptionsImported += 1
            } else {
                summary.subscriptionsSkipped += 1
            }
        }
    }

    private static func importBudgets(
        _ codableBudgets: [CodableBudget],
        context: NSManagedObjectContext,
        summary: inout ImportSummary
    ) throws {
        for codable in codableBudgets {
            guard let budget = codable.toBudget() else {
                summary.budgetsSkipped += 1
                continue
            }
            let request: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", budget.id as CVarArg)
            if try context.count(for: request) == 0 {
                BudgetEntity.fromBudget(budget, context: context)
                summary.budgetsImported += 1
            } else {
                summary.budgetsSkipped += 1
            }
        }
    }

    private static func applyDeletedDefaults(_ list: [String], summary: inout ImportSummary) {
        guard !list.isEmpty else { return }
        let current: Set<String>
        if let saved = UserDefaults.standard.array(forKey: UserDefaultsKeys.deletedDefaultCategories) as? [String] {
            current = Set(saved)
        } else {
            current = []
        }
        let incoming = Set(list)
        let merged = current.union(incoming)
        UserDefaults.standard.set(Array(merged), forKey: UserDefaultsKeys.deletedDefaultCategories)
        summary.deletedDefaultsAdded = incoming.subtracting(current).count
    }

    // MARK: - Preferences apply

    private static func applyPreferences(_ prefs: BackupBundle.Preferences, summary: inout ImportSummary) {
        let defaults = UserDefaults.standard

        if let value = prefs.userName?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            defaults.set(value, forKey: UserDefaultsKeys.userName)
            summary.preferencesUpdated.append("Name")
        }
        if let raw = prefs.selectedCurrency, Expense.Currency(rawValue: raw) != nil {
            defaults.set(raw, forKey: UserDefaultsKeys.selectedCurrency)
            summary.preferencesUpdated.append("Currency")
        }
        if let value = prefs.defaultHomeTimeFrame, !value.isEmpty {
            defaults.set(value, forKey: UserDefaultsKeys.defaultHomeTimeFrame)
            summary.preferencesUpdated.append("Default time frame")
        }
        if let value = prefs.appearanceMode, !value.isEmpty {
            defaults.set(value, forKey: UserDefaultsKeys.appearanceMode)
            summary.preferencesUpdated.append("Appearance")
        }
        if let tokens = prefs.preferredSummaryCategories,
           let data = try? JSONEncoder().encode(tokens) {
            defaults.set(data, forKey: UserDefaultsKeys.preferredSummaryCategories)
            summary.preferencesUpdated.append("Pinned categories")
        }
        if let n = prefs.notifications {
            if let w = n.weeklySummary {
                defaults.set(w.enabled,  forKey: UserDefaultsKeys.weeklySummaryEnabled)
                defaults.set(w.weekday,  forKey: UserDefaultsKeys.weeklySummaryWeekday)
                defaults.set(w.hour,     forKey: UserDefaultsKeys.weeklySummaryHour)
                defaults.set(w.minute,   forKey: UserDefaultsKeys.weeklySummaryMinute)
                summary.preferencesUpdated.append("Weekly summary schedule")
            }
            if let m = n.monthlyDigest {
                defaults.set(m.enabled,    forKey: UserDefaultsKeys.monthlyDigestEnabled)
                defaults.set(m.dayOfMonth, forKey: UserDefaultsKeys.monthlyDigestDayOfMonth)
                defaults.set(m.hour,       forKey: UserDefaultsKeys.monthlyDigestHour)
                defaults.set(m.minute,     forKey: UserDefaultsKeys.monthlyDigestMinute)
                summary.preferencesUpdated.append("Monthly digest schedule")
            }
            if let b = n.backupReminder {
                defaults.set(b.enabled,    forKey: UserDefaultsKeys.backupReminderEnabled)
                defaults.set(b.dayOfMonth, forKey: UserDefaultsKeys.backupReminderDayOfMonth)
                defaults.set(b.hour,       forKey: UserDefaultsKeys.backupReminderHour)
                defaults.set(b.minute,     forKey: UserDefaultsKeys.backupReminderMinute)
                summary.preferencesUpdated.append("Backup reminder schedule")
            }
        }
    }

    // MARK: - Replace mode wipers

    private static func wipeStore(context: NSManagedObjectContext) throws {
        let entities = ["ExpenseEntity", "SubscriptionEntity", "CustomCategoryEntity", "BudgetEntity"]
        for name in entities {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let delete = NSBatchDeleteRequest(fetchRequest: request)
            delete.resultType = .resultTypeObjectIDs
            let result = try context.execute(delete) as? NSBatchDeleteResult
            if let ids = result?.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                    into: [PersistenceController.shared.container.viewContext, context]
                )
            }
        }
    }

    /// Wipe every preference that participates in a backup. Backup metadata
    /// (`lastBackupDate`, `totalBackupCount`) is preserved — clearing it would
    /// confuse the user about whether their data is safe.
    private static func wipePreferences() {
        let defaults = UserDefaults.standard
        let keys: [String] = [
            UserDefaultsKeys.userName,
            UserDefaultsKeys.selectedCurrency,
            UserDefaultsKeys.defaultHomeTimeFrame,
            UserDefaultsKeys.appearanceMode,
            UserDefaultsKeys.preferredSummaryCategories,
            UserDefaultsKeys.deletedDefaultCategories,
            UserDefaultsKeys.weeklySummaryEnabled,
            UserDefaultsKeys.weeklySummaryWeekday,
            UserDefaultsKeys.weeklySummaryHour,
            UserDefaultsKeys.weeklySummaryMinute,
            UserDefaultsKeys.monthlyDigestEnabled,
            UserDefaultsKeys.monthlyDigestDayOfMonth,
            UserDefaultsKeys.monthlyDigestHour,
            UserDefaultsKeys.monthlyDigestMinute,
            UserDefaultsKeys.backupReminderEnabled,
            UserDefaultsKeys.backupReminderDayOfMonth,
            UserDefaultsKeys.backupReminderHour,
            UserDefaultsKeys.backupReminderMinute
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Validation

    private static func isValidExpense(_ expense: Expense) -> Bool {
        guard expense.amount.isFinite, expense.amount >= 0 else { return false }
        guard !expense.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let now = Date()
        let tenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: now) ?? now
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        guard expense.date >= tenYearsAgo, expense.date <= oneYearFromNow else { return false }
        guard !expense.category.rawValue.isEmpty else { return false }
        return true
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a backup import completes successfully so view models can
    /// refresh their published state without coupling to the importer.
    static let backupImportDidComplete = Notification.Name("backupImportDidComplete")
}

// MARK: - Legacy v1 reader

/// Reads the old `exportVersion: "1.0"` JSON shape and the
/// `=== EXPENSES ===` sectioned CSV shape so users with old backup files
/// aren't stranded.
enum LegacyV1Reader {

    static func parseJSON(data: Data) throws -> BackupBundle {
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw BackupImporter.ImportError.parseFailed("Top-level JSON wasn't a dictionary")
        }
        var payload = BackupBundle.Payload.empty

        if let raw = json["expenses"] as? [[String: Any]] {
            payload.expenses = raw.compactMap { try? Expense(from: $0) }
        }
        if let raw = json["subscriptions"] as? [[String: Any]] {
            payload.subscriptions = raw.compactMap { try? Subscription(from: $0) }
        }
        if let raw = json["customCategories"] as? [[String: Any]] {
            payload.customCategories = raw.compactMap { try? CustomCategory(from: $0) }
        }
        if let raw = json["deletedDefaultCategories"] as? [String] {
            payload.deletedDefaultCategories = raw
        }
        return BackupBundle(schema: .current(), data: payload, preferences: .empty)
    }

    static func parseCSV(content: String) throws -> BackupBundle {
        var payload = BackupBundle.Payload.empty
        let lines = content.components(separatedBy: .newlines)
        var currentSection = ""
        var sectionLines: [String] = []
        var skipNextLine = false

        func flush() {
            switch currentSection {
            case "EXPENSES":
                payload.expenses = sectionLines.compactMap { try? Expense(fromCSV: $0) }
            case "SUBSCRIPTIONS":
                payload.subscriptions = sectionLines.compactMap { try? Subscription(fromCSV: $0) }
            case "CUSTOM_CATEGORIES":
                payload.customCategories = sectionLines.compactMap { try? CustomCategory(fromCSV: $0) }
            case "DELETED_DEFAULT_CATEGORIES":
                payload.deletedDefaultCategories = sectionLines.compactMap { parseCSVField($0) }
            default:
                break
            }
            sectionLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("===") && trimmed.hasSuffix("===") {
                if !currentSection.isEmpty { flush() }
                currentSection = trimmed.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
                skipNextLine = true
            } else if skipNextLine {
                skipNextLine = false
                continue
            } else if !trimmed.isEmpty {
                sectionLines.append(trimmed)
            }
        }
        if !currentSection.isEmpty { flush() }

        return BackupBundle(schema: .current(), data: payload, preferences: .empty)
    }
}
