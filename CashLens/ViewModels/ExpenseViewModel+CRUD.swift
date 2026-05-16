import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Core Data Operations (Expenses)
    
    func addExpense(_ expense: Expense) {
        // Ensure the expense uses the current selected currency
        var newExpense = expense
        newExpense.currency = selectedCurrency
        
        _ = ExpenseEntity.fromExpense(newExpense, context: viewContext)
        saveContext()
        // PERF: Skip the O(N) reload — sorted-insert the new row into
        // the in-memory array instead. See the contract on
        // `applyIncrementalInsert` for why this is safe (the entity
        // was just persisted under the same id).
        applyIncrementalInsert(newExpense)
        
        FeedbackManager.shared.incrementSuccessfulAction()
    }
    
    func updateExpense(_ expense: Expense) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let entity = results.first {
                // Capture the previously-stored receipt filename before
                // we overwrite it. If the user removed or replaced the
                // receipt during this edit, we delete the old file once
                // the save succeeds so we don't leak storage.
                let priorReceiptPath = entity.receiptImagePath

                entity.title = expense.title
                entity.amount = expense.amount
                entity.currency = expense.currency.rawValue
                entity.date = expense.date
                entity.category = expense.category.rawValue
                entity.notes = expense.notes
                entity.customCategoryId = expense.customCategoryId
                entity.isRefund = expense.isRefund
                entity.paymentMethod = expense.paymentMethod?.rawValue
                entity.receiptImagePath = expense.receiptImagePath
                if let tagList = expense.tags, !tagList.isEmpty {
                    entity.tags = tagList as NSArray
                } else {
                    entity.tags = nil
                }

                saveContext()
                // PERF: Apply the edit in-memory instead of refetching
                // the entire table. The in-memory `expense` already
                // reflects every field we just wrote into the entity,
                // including any date change which moves the row.
                applyIncrementalUpdate(expense)

                // After the save commits, drop the orphaned old file.
                // The form layer also handles its own cleanup for the
                // in-session attach/replace case (so the user sees the
                // file reclaimed immediately) — this is the safety
                // net for any path that bypasses the form flow.
                //
                // PERF: Hand the actual `unlink` syscall off to a
                // detached background task so we never block the main
                // thread on filesystem I/O after a save. This matches
                // the bulk-delete path (`cleanupReceiptFiles`).
                if let prior = priorReceiptPath, prior != expense.receiptImagePath {
                    Task.detached(priority: .utility) {
                        ReceiptStorage.delete(filename: prior)
                    }
                }
            }
        } catch {
            print("Error updating expense: \(error.localizedDescription)")
        }
    }
    
    func deleteExpense(at indexSet: IndexSet) {
        // Ensure indices are valid to prevent crashes
        let validIndices = indexSet.filter { $0 < filteredExpenses.count }
        
        if validIndices.isEmpty {
            print("Warning: Attempted to delete expenses with invalid indices")
            return
        }
        
        // Map indices to expenses
        let expensesToDelete = validIndices.map { filteredExpenses[$0] }
        // Capture every receipt filename in this delete batch *before*
        // we touch Core Data — otherwise the entities would be tombstoned
        // and we'd lose the link to the file path.
        let receiptPathsToCleanup = expensesToDelete.compactMap { $0.receiptImagePath }
        
        let deletedIds = Set(expensesToDelete.map { $0.id })
        do {
            // Use a batch request for better performance when deleting multiple expenses
            if expensesToDelete.count > 1 {
                let ids = expensesToDelete.map { $0.id }
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = ExpenseEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id IN %@", ids as CVarArg)
                
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                
                let result = try viewContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                }
            } else {
                // Use regular delete for single expense
                for expense in expensesToDelete {
                    let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
                    
                    let results = try viewContext.fetch(fetchRequest)
                    for entity in results {
                        viewContext.delete(entity)
                    }
                    saveContext()
                }
            }
            
            // PERF: Drop the deleted rows from the in-memory array
            // (single linear pass) instead of refetching the whole
            // table from disk.
            applyIncrementalDelete(ids: deletedIds)
            // Drop the now-orphaned receipt files. Off-main so a large
            // batch delete doesn't stutter the list refresh.
            cleanupReceiptFiles(receiptPathsToCleanup)
        } catch {
            print("Error deleting expenses: \(error.localizedDescription)")
            // On failure, the in-memory state may have drifted from
            // disk — fall back to a full reload to re-establish
            // ground truth.
            loadExpenses()
        }
    }
    
    func deleteExpenseById(_ id: UUID) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            // Capture receipt filenames before delete so we can clean
            // them up after the save commits.
            let receiptPaths = results.compactMap { $0.receiptImagePath }
            for entity in results {
                viewContext.delete(entity)
            }
            saveContext()
            // PERF: Single-row in-memory remove instead of full reload.
            applyIncrementalDelete(ids: [id])
            cleanupReceiptFiles(receiptPaths)
        } catch {
            print("Error deleting expense by ID: \(error.localizedDescription)")
        }
    }

    /// Off-main cleanup of orphaned receipt files. Safe to call with an
    /// empty array (no-op). All access is on the file system; Core Data
    /// is not touched.
    private func cleanupReceiptFiles(_ filenames: [String]) {
        guard !filenames.isEmpty else { return }
        Task.detached(priority: .background) {
            for name in filenames {
                ReceiptStorage.delete(filename: name)
            }
        }
    }

    // MARK: - Bulk Operations
    //
    // Used by the bulk-select toolbar in `AllExpensesView`. All three methods
    // do a single `saveContext` followed by **one in-memory mutation** of
    // the `expenses` array, so the UI updates exactly once instead of once
    // per row — and we never pay for a full Core Data refetch after a
    // bulk save.

    /// Delete N expenses by id in a single save.
    ///
    /// Uses `viewContext.delete(_:)` per entity instead of `NSBatchDeleteRequest`.
    /// Batch delete bypasses the context's row cache, which can leave the
    /// immediately-following fetch returning stale objects — meaning the list
    /// view doesn't reflect the deletion until something forces a fresh fetch
    /// (e.g. navigating away and back). Per-row delete + a single `saveContext`
    /// keeps the context honest and is plenty fast for selection-mode counts.
    func deleteExpenses(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id IN %@", Array(ids) as CVarArg)
        do {
            let entities = try viewContext.fetch(fetchRequest)
            // Snapshot receipt paths before delete so the file cleanup
            // can run after the save (and after the entities are gone).
            let receiptPaths = entities.compactMap { $0.receiptImagePath }
            for entity in entities {
                viewContext.delete(entity)
            }
            saveContext()
            // PERF: Bulk in-memory remove instead of full reload.
            applyIncrementalDelete(ids: ids)
            cleanupReceiptFiles(receiptPaths)
        } catch {
            print("Error bulk-deleting expenses: \(error.localizedDescription)")
            loadExpenses()
        }
    }

    /// Reassign the category (and optional custom-category id) on every
    /// expense in `ids`. When `category != .custom`, `customCategoryId` is
    /// always cleared so the row can never end up in an inconsistent
    /// "default category but lingering custom id" state.
    func bulkChangeCategory(ids: Set<UUID>, to category: Expense.Category, customCategoryId: UUID? = nil) {
        guard !ids.isEmpty else { return }
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id IN %@", Array(ids) as CVarArg)
        do {
            let entities = try viewContext.fetch(fetchRequest)
            for entity in entities {
                entity.category = category.rawValue
                entity.customCategoryId = (category == .custom) ? customCategoryId : nil
            }
            saveContext()
            // PERF: Mutate the in-memory rows in place — dates didn't
            // change, so we don't need to resort. Single linear pass
            // followed by one publish, instead of a full reload.
            let newCustomId: UUID? = (category == .custom) ? customCategoryId : nil
            var mutated = expenses
            for i in mutated.indices where ids.contains(mutated[i].id) {
                mutated[i].category = category
                mutated[i].customCategoryId = newCustomId
            }
            expenses = mutated
        } catch {
            print("Error bulk-updating category: \(error.localizedDescription)")
        }
    }

    /// Add a tag to every expense in `ids`, deduplicating against existing
    /// tags. Trims and normalises whitespace; no-op if the trimmed tag is
    /// empty. Tags are stored as a Transformable `NSArray`, so we round-trip
    /// through `[String]` to keep the type consistent with single-row writes.
    func bulkAddTag(ids: Set<UUID>, tag rawTag: String) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ids.isEmpty, !tag.isEmpty else { return }

        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id IN %@", Array(ids) as CVarArg)
        do {
            let entities = try viewContext.fetch(fetchRequest)
            for entity in entities {
                var existing = (entity.tags as? [String]) ?? []
                let lowered = tag.lowercased()
                let alreadyHas = existing.contains { $0.lowercased() == lowered }
                if !alreadyHas {
                    existing.append(tag)
                    entity.tags = existing as NSArray
                }
            }
            saveContext()
            // PERF: Mirror the tag append in-memory instead of full
            // reload. We re-derive tags from the same source-of-truth
            // (the persisted entity) but cheaply since we already know
            // which rows changed and what the tag is.
            let lowered = tag.lowercased()
            var mutated = expenses
            for i in mutated.indices where ids.contains(mutated[i].id) {
                var tags = mutated[i].tags ?? []
                if !tags.contains(where: { $0.lowercased() == lowered }) {
                    tags.append(tag)
                    mutated[i].tags = tags
                }
            }
            expenses = mutated
        } catch {
            print("Error bulk-adding tag: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Formatting

    /// Format an amount using the active currency's natural decimal
    /// count (ISO 4217 minor units):
    ///
    ///   • JPY / KRW / IDR / HUF / VND / …   → 0 decimals (¥1,234)
    ///   • BHD / KWD / OMR / JOD / …         → 3 decimals
    ///   • everything else                   → 2 decimals
    ///
    /// **Concurrency.** Allocates a per-call `NumberFormatter` rather
    /// than mutating a shared instance. `formattedAmount` is called
    /// from background `Task.detached` work in `StatisticsView`, the
    /// forecast pipeline, and the widget snapshot builder — sharing
    /// + mutating one formatter across those raced and produced
    /// corrupt output under contention. The per-call cost is on the
    /// order of microseconds; even formatting hundreds of values for
    /// a stats refresh is invisible at human timescales.
    func formattedAmount(_ amount: Double) -> String {
        let digits = selectedCurrency.fractionDigits
        let zeroFallback = digits == 0 ? "0" : "0." + String(repeating: "0", count: digits)

        guard amount.isFinite else {
            return "\(selectedCurrency.symbol)\(zeroFallback)"
        }

        let safeAmount = max(amount, 0.0)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let formatted = formatter.string(from: NSNumber(value: safeAmount)) ?? zeroFallback
        return "\(selectedCurrency.symbol)\(formatted)"
    }

    /// Parse a user-typed amount string into a `Double`. Builds its
    /// own formatters (no shared state) so this is safe to call from
    /// any thread — same reasoning as `formattedAmount`.
    func parseAmount(_ amountString: String) -> Double? {
        let cleanedAmount = amountString
            .replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedAmount.isEmpty { return nil }

        // Try a default-locale parse first — handles "1,234.56" in
        // en_US, "1.234,56" in de_DE, etc. Per-call instance.
        let defaultFormatter = NumberFormatter()
        defaultFormatter.numberStyle = .decimal
        if let number = defaultFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }

        let standardFormatter = NumberFormatter()
        standardFormatter.decimalSeparator = "."
        if let number = standardFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }

        let commaFormatter = NumberFormatter()
        commaFormatter.decimalSeparator = ","
        if let number = commaFormatter.number(from: cleanedAmount) {
            return number.doubleValue
        }
        
        return nil
    }
}


