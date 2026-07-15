import Foundation
@preconcurrency import CoreData

extension ExpenseViewModel {
    // MARK: - Core Data (shared helpers)
    
    /// Load expenses with **phased hydration**.
    ///
    /// PERF: This used to synchronously fetch and materialize the *entire*
    /// ExpenseEntity table on the main thread. It runs inside
    /// `ExpenseViewModel.init`, which runs inside `CashLensApp.init` —
    /// i.e. before SwiftUI renders anything — so at 10k+ rows it blocked
    /// the first frame for 0.5s+ (and risked the launch watchdog at 50k).
    ///
    /// Phase 1 (synchronous, here): fetch only a recent "hot window" —
    /// everything from the start of last month, capped at 2,000 rows.
    /// That's enough for everything visible at first paint (Today's
    /// verdict, current budget progress, recent list) and is O(window),
    /// not O(N).
    ///
    /// Phase 2 (async): `loadExpensesAsync()` backfills the full table on
    /// a background context and publishes the complete array in a single
    /// replace, setting `isFullyHydrated`. Consumers that need full
    /// history (Statistics all-time, forecast, notification digests,
    /// receipt orphan sweep) either recompute on that publish or
    /// explicitly await `waitUntilFullyHydrated()`.
    func loadExpenses() {
        viewContext.performAndWait {
            let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
            // Hot window: start of the previous month → now. Uses the
            // `byDate` fetch index. The row cap bounds the worst case
            // (e.g. a huge same-day import) so the sync phase can never
            // degrade back into a full-table materialization.
            let calendar = Calendar.current
            let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let windowStart = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth
            fetchRequest.predicate = NSPredicate(format: "date >= %@", windowStart as NSDate)
            fetchRequest.fetchLimit = 2000

            do {
                var results = try viewContext.fetch(fetchRequest)
                if results.isEmpty {
                    // All data may be older than the window (lapsed user).
                    // Fall back to the most recent rows regardless of date
                    // so first paint isn't a false empty state.
                    let fallback: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fallback.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
                    fallback.fetchLimit = 500
                    results = try viewContext.fetch(fallback)
                }
                self.isFullyHydrated = false
                self.expenses = results.toExpenses()
            } catch {
                print("Error loading expenses: \(error.localizedDescription)")
                self.expenses = []
            }
        }
        // Phase 2: backfill the full table off-main. Skipped in Xcode
        // previews so `ExpenseViewModel.preview`'s hand-assigned sample
        // data isn't clobbered by an empty-store publish a beat later.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            loadExpensesAsync()
        }
    }
    
    /// Load expenses asynchronously on a background context (initial
    /// backfill + foreground refreshes).
    ///
    /// PERF: the publish is **diff-gated** — the freshly fetched array is
    /// compared against the current one *off-main*, and if nothing changed
    /// we skip the `expenses = ...` assignment entirely. That single guard
    /// kills the every-foreground recompute cascade (filter pipeline,
    /// Today, AllExpenses, budgets, widget snapshot) for the common case
    /// where the user just switched apps and back. The comparison itself
    /// is O(N) but runs on the background context's queue, never on main.
    func loadExpensesAsync() {
        Task { @MainActor in
            let backgroundContext = self.backgroundLoadContext
            let current = self.expenses
            
            // `changed` is nil when the fetch failed OR nothing changed;
            // `succeeded` distinguishes the two so hydration is only
            // marked complete after a real full-table read.
            let outcome: (succeeded: Bool, changed: [Expense]?) = await Task.detached(priority: .userInitiated) {
                await backgroundContext.perform {
                    let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
                    fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ExpenseEntity.date, ascending: false)]
                    fetchRequest.fetchBatchSize = 100
                    
                    do {
                        let results = try backgroundContext.fetch(fetchRequest)
                        let loaded = results.toExpenses()
                        return (true, loaded == current ? nil : loaded)
                    } catch {
                        print("Error loading expenses async: \(error.localizedDescription)")
                        // Keep the in-memory data rather than wiping the
                        // UI (and everything downstream) on a transient
                        // fetch failure.
                        return (false, nil)
                    }
                }
            }.value
            
            if let changed = outcome.changed {
                self.expenses = changed
            }
            // Guarded so an already-hydrated refresh doesn't fire a
            // no-op objectWillChange on every foreground.
            if outcome.succeeded && !self.isFullyHydrated {
                self.isFullyHydrated = true
            }
        }
    }
    
    // PERF: Removed `updateFilteredExpenses()` — it was only called
    // by `refreshData()` on foreground and ran the filter
    // **synchronously on the main thread**. It also fought the
    // off-main pipeline in `setupFiltering` which would publish a
    // newer result a frame later, causing one wasted O(N) main-thread
    // pass per foreground transition. Filtering is now exclusively
    // driven by the debounced Combine sink → `scheduleFilterRecompute`.

    // MARK: - Incremental in-memory updates
    //
    // PERF: Every CRUD method used to call `loadExpenses()` at the
    // end, which re-fetched the **entire** ExpenseEntity table from
    // SQLite, mapped every row to a Swift `Expense` value, and then
    // reassigned `expenses` — an O(N) main-thread pass for every
    // single-row save. The audit identified this as the single
    // biggest source of "slow with data, fast without" perception.
    //
    // The three helpers below mutate the in-memory `expenses` array
    // in place to mirror what just happened on disk. Because
    // `expenses` is `@Published`, assignment still triggers the
    // downstream filter / budget / widget / digest pipelines exactly
    // once — but we skip the full Core Data fetch and the row-by-row
    // `toExpense()` allocations. Saves go from O(N) to O(log N) or
    // O(1) work on the main thread for typical edits.
    //
    // Contract:
    //   • Each helper must be called **only after `saveContext()`
    //     succeeds**, so the in-memory array can never get ahead of
    //     Core Data.
    //   • If the targeted row is not present in `expenses` (which
    //     would mean the in-memory state has drifted from Core Data —
    //     e.g. after a backup restore), we fall back to a full
    //     `loadExpenses()` to re-establish ground truth.
    //   • The array must remain sorted by date descending to match
    //     `loadExpenses()`'s `NSSortDescriptor`, since every consumer
    //     downstream (filter, hero average, recent titles, recent
    //     expenses list) assumes that order.

    /// Insert one new expense into the in-memory array at the
    /// correct date-desc position. O(N) worst case (single linear
    /// scan + shift) but with no Core Data round-trip and no
    /// allocation per existing row.
    func applyIncrementalInsert(_ expense: Expense) {
        let insertIndex = expenses.firstIndex(where: { $0.date < expense.date }) ?? expenses.count
        expenses.insert(expense, at: insertIndex)
    }

    /// Replace one expense in-place. If the date changed we also
    /// move it to the correct position so the array stays sorted.
    /// Falls back to a full reload if the row isn't present
    /// in-memory (drift case).
    func applyIncrementalUpdate(_ expense: Expense) {
        guard let idx = expenses.firstIndex(where: { $0.id == expense.id }) else {
            loadExpenses()
            return
        }
        let oldDate = expenses[idx].date
        if oldDate == expense.date {
            expenses[idx] = expense
        } else {
            expenses.remove(at: idx)
            let insertIndex = expenses.firstIndex(where: { $0.date < expense.date }) ?? expenses.count
            expenses.insert(expense, at: insertIndex)
        }
    }

    /// Remove zero or more expenses by id in one publish. Cheap
    /// even for large bulk-delete selections because the Swift
    /// `removeAll(where:)` does a single pass over the array.
    func applyIncrementalDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        expenses.removeAll(where: { ids.contains($0.id) })
    }

    /// Save the view context. Returns `false` when the save threw —
    /// callers that mirror the write in-memory (e.g. `addExpense`'s
    /// incremental insert) must check the result so the UI can never
    /// get ahead of what's actually on disk. Discardable for the many
    /// call sites where a failure is already fully handled by the
    /// save-error banner.
    @discardableResult
    func saveContext() -> Bool {
        var succeeded = true
        viewContext.performAndWait {
            guard viewContext.hasChanges else { return }
            do {
                try viewContext.save()
            } catch {
                succeeded = false
                // Surface to the user via the global save-error
                // banner so silent failures don't leave the UI in
                // a "looks saved" state. See `SaveErrorReporter`.
                SaveErrorReporter.report(operation: "saving your changes", error: error)
            }
        }
        return succeeded
    }
    
    // NOTE: removed the dead `saveContextAsync()` helper — no call
    // sites; every save path uses the synchronous, result-reporting
    // `saveContext()` above so callers can gate follow-on state on
    // the outcome.
}


