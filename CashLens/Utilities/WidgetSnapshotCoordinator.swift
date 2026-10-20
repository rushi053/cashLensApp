//
//  WidgetSnapshotCoordinator.swift
//  CashLens (main app only)
//
//  Owns the lifecycle of the widget data pipe:
//
//    1. Subscribe to every view model whose state the widgets care
//       about (expenses, budgets, custom categories, pro state, theme,
//       currency, user name).
//    2. Watch the Core Data context for `NSManagedObjectContextDidSave`
//       so subscription mutations are picked up even when the
//       `SubscriptionsView` tab has never been visited (its VM doesn't
//       live at the app level).
//    3. Debounce rapid bursts of mutations so we never write the JSON
//       file on every keystroke.
//    4. Marshal an immutable, `Sendable` `WidgetSnapshotBuilder.Inputs`
//       value, hand it to a `Task.detached`.
//    5. The detached task builds the snapshot, atomically writes it to
//       the App Group container, and hops back to the main actor to
//       call `WidgetCenter.shared.reloadAllTimelines()`.
//
//  Failure modes are deliberately silent — the widget always falls
//  back to its last-known-good snapshot or the placeholder, so a
//  hiccup in the pipe never produces a broken in-app experience.
//

import Foundation
import Combine
import CoreData
import WidgetKit

@MainActor
final class WidgetSnapshotCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = WidgetSnapshotCoordinator()

    // MARK: - State

    private weak var expenseVM: ExpenseViewModel?
    private weak var budgetVM: BudgetViewModel?
    private weak var categoryVM: CategoryViewModel?
    private weak var proManager: ProManager?
    private weak var themeStore: ThemeStore?

    /// Strong reference to the persistent context so we can fetch
    /// subscriptions on demand without depending on `SubscriptionsView`
    /// being mounted (its `SubscriptionViewModel` is tab-scoped).
    private var viewContext: NSManagedObjectContext?

    private var cancellables = Set<AnyCancellable>()

    /// Pending coalesced refresh task. Cancelled and replaced whenever
    /// a fresh mutation arrives inside the debounce window so we only
    /// write one snapshot per logical "change burst".
    private var refreshTask: Task<Void, Never>?

    /// Set the first time `bootstrap` runs to make a re-entry cheap.
    private var bootstrapped = false

    /// Content of the last snapshot we actually wrote, with
    /// `generatedAt` normalized so it doesn't defeat the comparison.
    /// PERF: lets `performRefresh` skip the disk write **and** the
    /// `reloadAllTimelines()` call when a refresh produced byte-identical
    /// content — `reloadAllTimelines` wakes the widget extension
    /// process, which is by far the most expensive step of this pipe
    /// and used to run for every no-op publish upstream.
    private var lastWrittenSnapshot: WidgetSnapshot?

    private init() {}

    // MARK: - Bootstrap

    /// Wire up the coordinator to the live view models. Safe to call
    /// multiple times — only the first call installs subscriptions; any
    /// subsequent calls just trigger an immediate refresh.
    func bootstrap(
        expenseVM: ExpenseViewModel,
        budgetVM: BudgetViewModel,
        categoryVM: CategoryViewModel,
        proManager: ProManager,
        themeStore: ThemeStore,
        viewContext: NSManagedObjectContext
    ) {
        self.expenseVM = expenseVM
        self.budgetVM = budgetVM
        self.categoryVM = categoryVM
        self.proManager = proManager
        self.themeStore = themeStore
        self.viewContext = viewContext

        if !bootstrapped {
            bootstrapped = true
            installSubscriptions()
        }

        // Always do an initial refresh so a freshly-installed widget
        // gets real data on the very first render instead of waiting
        // for the user's next mutation.
        scheduleRefresh()
    }

    /// Force a refresh immediately. Called from app-lifecycle hooks
    /// (foregrounded, post-import) where we want the widget to reflect
    /// the new state right now rather than waiting for a debounce.
    func refreshNow() {
        scheduleRefresh()
    }

    // MARK: - Subscriptions

    private func installSubscriptions() {
        // Expenses — the highest-cardinality input, drives most widget
        // surfaces.
        expenseVM?.$expenses
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Currency / user-name changes show up in widget headers and
        // money formatters.
        expenseVM?.$selectedCurrency
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        expenseVM?.$userName
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Budget set + per-budget progress.
        budgetVM?.$budgets
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        budgetVM?.$budgetProgress
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Custom categories — name / icon / color drift would otherwise
        // ghost in the widget until the next expense mutation.
        categoryVM?.$customCategories
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Pro state flips the upsell variant on/off.
        proManager?.$isPro
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Expense templates feed the Quick Log widget's buttons —
        // adds / removes / renames must re-export.
        ExpenseTemplateStore.shared.$templates
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Theme changes need to re-render the widget with the new
        // accent color.
        themeStore?.$currentTheme
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        // Subscription mutations — pulled directly off Core Data
        // because `SubscriptionViewModel` is tab-scoped (lives only
        // while `SubscriptionsView` is mounted). Listening to context
        // saves catches creates / updates / deletes regardless of
        // which view triggered them.
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] note in
                guard let self else { return }
                guard self.contextDidSaveTouchedSubscriptions(note) else { return }
                self.scheduleRefresh()
            }
            .store(in: &cancellables)
    }

    /// Quick check: did this save event include any `SubscriptionEntity`
    /// objects? Avoids triggering an extra refresh for every Core Data
    /// save (e.g. an expense save would already have been picked up by
    /// the `expenses` subscription above).
    private func contextDidSaveTouchedSubscriptions(_ note: Notification) -> Bool {
        let userInfo = note.userInfo ?? [:]
        let keys: [String] = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey
        ]
        for k in keys {
            if let set = userInfo[k] as? Set<NSManagedObject>,
               set.contains(where: { $0 is SubscriptionEntity }) {
                return true
            }
        }
        return false
    }

    // MARK: - Refresh pipeline

    private func scheduleRefresh() {
        // Coalesce rapid bursts. 300ms is comfortably below "feels
        // instant" while still catching the entire burst of `@Published`
        // emits a single tap can produce (e.g. add expense → updates
        // expenses + tag stats + cached totals, all in <100ms).
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.performRefresh()
        }
    }

    private func performRefresh() async {
        // Snapshot inputs on the main actor — this is the ONLY place
        // we touch the live view models. Everything downstream is value
        // types crossing into a detached task.
        guard
            let expenseVM = self.expenseVM,
            let budgetVM = self.budgetVM,
            let categoryVM = self.categoryVM,
            let proManager = self.proManager,
            let themeStore = self.themeStore
        else { return }

        let expenses = expenseVM.expenses
        let budgets = budgetVM.budgets
        let customCategories = categoryVM.customCategories
        let templates = ExpenseTemplateStore.shared.displayOrder
        let currencyCode = expenseVM.selectedCurrency.rawValue
        let userName = expenseVM.userName
        let activeThemeId = themeStore.currentTheme.id
        let isPro = proManager.isPro

        // Build off-main so even a multi-thousand-row history never
        // touches the UI thread. PERF: the subscription fetch used
        // to run synchronously on the view context (main thread) before
        // hopping off; it now happens on a background context inside the
        // same detached pass.
        let snapshot = await Task.detached(priority: .utility) {
            let subs = Self.fetchSubscriptionsOffMain()
            let inputs = WidgetSnapshotBuilder.Inputs(
                expenses: expenses,
                budgets: budgets,
                subscriptions: subs,
                customCategories: customCategories,
                templates: templates,
                currencyCode: currencyCode,
                userName: userName,
                activeThemeId: activeThemeId,
                isPro: isPro,
                now: Date()
            )
            return WidgetSnapshotBuilder.build(inputs)
        }.value

        // PERF: skip the write + `reloadAllTimelines()` when the freshly
        // built content is identical to what's already on disk (only
        // `generatedAt` moved). Waking the widget extension process is
        // the expensive part of this pipe, and upstream publishers fire
        // for plenty of mutations that don't change any widget-visible
        // aggregate.
        if var previous = lastWrittenSnapshot {
            previous.generatedAt = snapshot.generatedAt
            if previous == snapshot { return }
        }

        let wrote = await Task.detached(priority: .utility) {
            WidgetSnapshotIO.write(snapshot)
        }.value
        // A failed write leaves the old file on disk — don't cache the
        // new content (the next refresh should retry) and don't wake
        // the extension for data it can't read yet.
        guard wrote else { return }
        lastWrittenSnapshot = snapshot

        // Reload all timelines on the main actor (WidgetCenter is
        // safe from any thread but we keep the call site predictable).
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fetch all subscriptions on a fresh background context, blocking
    /// only the calling (non-main) thread. Runs inside the detached
    /// snapshot-build task so the main thread never pays for it.
    private nonisolated static func fetchSubscriptionsOffMain() -> [Subscription] {
        let context = PersistenceController.shared.container.newBackgroundContext()
        var result: [Subscription] = []
        context.performAndWait {
            let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
            ]
            result = (try? context.fetch(request).toSubscriptions()) ?? []
        }
        return result
    }
}
