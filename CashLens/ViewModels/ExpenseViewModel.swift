import Foundation
import SwiftUI
import Combine
import CoreData

class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    /// Phased-hydration marker. `false` while `expenses` holds only the
    /// synchronous launch window (recent rows); flips to `true` once
    /// `loadExpensesAsync()` has published the full table. Consumers
    /// that must see complete history before doing destructive or
    /// persistent work (receipt orphan sweep, notification digests)
    /// should gate on this / use `waitUntilFullyHydrated()`.
    /// Set from `ExpenseViewModel+CoreData.swift`, hence no `private(set)`.
    @Published var isFullyHydrated: Bool = false
    @Published var filteredExpenses: [Expense] = []
    @Published var selectedCategory: Expense.Category?
    @Published var selectedCustomCategoryId: UUID?
    @Published var selectedTimeFrame: TimeFrame = .all {
        didSet {
            UserDefaults.standard.set(selectedTimeFrame.rawValue, forKey: UserDefaultsKeys.selectedTimeFrame)
        }
    }
    
    // MARK: - Cached Totals (Performance Optimization)
    //
    // PERF: These five caches are written **in lock-step** with
    // `filteredExpenses` from a single MainActor block in
    // `applyFilterAndTotalsResult(_:)`. Doing them in one synchronous
    // burst on main lets SwiftUI coalesce all of the resulting
    // `objectWillChange` emissions into **one** body re-evaluation per
    // logical save, instead of the 5–7 separate ones that used to
    // happen when totals were updated by a second `Task` after
    // `filteredExpenses` landed.
    @Published private(set) var cachedTotalAmount: Double = 0
    @Published private(set) var cachedTotalsByCategory: [Expense.Category: Double] = [:]
    @Published private(set) var cachedTotalsByCustomId: [UUID: Double] = [:]
    @Published private(set) var cachedCountsByCategory: [Expense.Category: Int] = [:]
    @Published private(set) var cachedCountsByCustomId: [UUID: Int] = [:]
    // NOTE: Removed `@Published var isFilteringInProgress` — it was set
    // true at the start of every filter pass and false at the end but
    // never actually read by any view. Each set fired its own
    // `objectWillChange.send()`, adding two needless invalidation
    // passes to every filter recompute (which happens on every save,
    // every filter change, every currency change, every foreground
    // transition).

    /// Aggregate tag usage counts / recent / popular. Recomputed off-main when
    /// `expenses` changes so autocomplete and filter strips stay fresh.
    @Published private(set) var tagStats: TagSuggestionProvider.Stats = .empty

    // Background task management for filtering. `totalsTask` is no
    // longer needed: totals are now computed inside the same detached
    // pass as filtering (see `scheduleFilterRecompute`), so there's a
    // single Task we can cancel instead of two racing each other.
    private var filterTask: Task<Void, Never>?
    private var tagStatsTask: Task<Void, Never>?
    
    /// Controls what Home should default to on launch (when no explicit last selection is stored).
    @Published var defaultHomeTimeFrame: TimeFrame = .month {
        didSet {
            UserDefaults.standard.set(defaultHomeTimeFrame.rawValue, forKey: UserDefaultsKeys.defaultHomeTimeFrame)
        }
    }
    /// SAFETY: Setting this does **not** rewrite stored data. The bulk
    /// relabel of every expense/subscription currency field
    /// (`syncCurrencyAcrossStoredData()`) is destructive — amounts are
    /// NOT converted — so it only runs from `CurrencyPickerView`'s
    /// commit path after explicit user confirmation. Keeping it out of
    /// `didSet` also stops the rewrite from firing on every launch
    /// (`loadSelectedCurrency`), on locale auto-pick, and on backup
    /// restore (where it used to clobber imported currencies).
    @Published var selectedCurrency: Expense.Currency = .usd {
        didSet {
            if oldValue != selectedCurrency {
                // Broadcast so views with **baked-in** formatted strings
                // (e.g. `StatisticsView.cachedInsights`, which embeds the
                // formatter output at compute time) can flush and rebuild.
                // Live `viewModel.formattedAmount(...)` call sites pick up
                // the change automatically via @Published, but anything
                // that already serialized a string with the old symbol
                // needs an explicit nudge.
                NotificationCenter.default.post(name: .currencyDidChange, object: nil)
            }
            UserDefaults.standard.set(selectedCurrency.rawValue, forKey: UserDefaultsKeys.selectedCurrency)
        }
    }
    @Published var userName: String = "CashLens User" {
        didSet {
            UserDefaults.standard.set(userName, forKey: UserDefaultsKeys.userName)
        }
    }
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: UserDefaultsKeys.appearanceMode)
            
            // Post notification immediately for UI update
            NotificationCenter.default.post(name: .appearanceDidChange, object: nil)
        }
    }
    
    enum TimeFrame: String, CaseIterable {
        case day = "Today"
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        case all = "All Time"
        
        /// Returns a half-open date interval: \([start, end)\).
        /// `referenceDate` controls "which" day/week/month/year we mean (enables browsing history).
        func dateRange(referenceDate: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
            switch self {
            case .day:
                let start = calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? referenceDate
                return (start, end)
            case .week:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)) ?? calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? referenceDate
                return (start, end)
            case .month:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? referenceDate
                return (start, end)
            case .year:
                let start = calendar.date(from: calendar.dateComponents([.year], from: referenceDate)) ?? calendar.startOfDay(for: referenceDate)
                let end = calendar.date(byAdding: .year, value: 1, to: start) ?? referenceDate
                return (start, end)
            case .all:
                // BUG FIX: previously this returned `(distantPast, referenceDate)`
                // — i.e. an `end` that's the live current moment rather than a
                // day boundary. `StatisticsView.applyPresetTimeFrame` then
                // subtracts 1 day from `range.end` to convert the half-open
                // interval into the inclusive "Custom range" UI representation
                // (`endDate` shown to the user as the last *included* day).
                // That math is correct when `range.end` is "start of next
                // bucket" (start of next month / week / year), but for `.all`
                // it produced `rangeEndDate = yesterday`, and the downstream
                // `ExpenseFilter` then resolved `endExclusive = startOfToday`,
                // silently dropping every expense dated within today's local
                // day. By returning `startOfTomorrow` here we make `.all`
                // behave like the other cases: subtract 1 day → `startOfToday`,
                // expand → `startOfTomorrow`, and every expense ever is now
                // actually included.
                let startOfToday = calendar.startOfDay(for: referenceDate)
                let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? referenceDate
                return (Date.distantPast, startOfTomorrow)
            }
        }
    }
    
    enum AppearanceMode: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"
        
        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    let viewContext: NSManagedObjectContext

    /// Long-lived background context reused by every `loadExpensesAsync()`
    /// pass. PERF: previously each call built a fresh
    /// `newBackgroundContext()` — a nontrivial setup cost paid on every
    /// foreground transition for no benefit. Only touched from the main
    /// actor (the async load hops onto it via `perform`).
    ///
    /// Derived from `viewContext`'s coordinator (not
    /// `PersistenceController.shared`) so the VM always reads the same
    /// store it was injected with — required by the store-load-failure
    /// recovery path, where the VM is deliberately wired to an in-memory
    /// container and must never fetch against the broken shared
    /// coordinator; also keeps previews/tests self-contained.
    lazy var backgroundLoadContext: NSManagedObjectContext = {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = viewContext.persistentStoreCoordinator
        context.automaticallyMergesChangesFromParent = true
        return context
    }()

    /// In-memory cache backing `categoryDisplayName/Icon/Color(for:)`.
    /// PERF: those helpers used to run a Core Data fetch **per call**
    /// (per rendered row, per sort comparison, per digest line). The
    /// cache is built lazily on first use and invalidated whenever a
    /// context save touches `CustomCategoryEntity` (see `init`), on
    /// `dataDidClear`, and after a backup restore. Main-thread only.
    var customCategoriesByIdCache: [UUID: CustomCategory]? = nil
    
    // Show currency picker on first launch
    @AppStorage(UserDefaultsKeys.hasShownCurrencyPicker) var hasShownCurrencyPicker: Bool = false
    
    // (Removed) Shared `numberFormatter` was here. It was used by both
    // `formattedAmount` and `parseAmount` in `ExpenseViewModel+CRUD.swift`,
    // mutated at format time, and read concurrently from background work
    // (e.g. `StatisticsView.recomputeStatsNow` runs `formattedAmount`
    // inside `Task.detached`). NumberFormatter is documented thread-unsafe
    // for concurrent mutation; the shared instance was a latent crash and
    // produced corrupt strings under contention. Both call sites now build
    // a per-call `NumberFormatter` — small allocation cost, no shared
    // state to race on.
    
    // MARK: - Summary Cards Customization
    
    /// Stored as tokens for backwards compatibility:
    /// - Default categories are stored as their `Expense.Category.rawValue` (e.g. "Food")
    /// - Custom categories are stored as `"custom:<uuid>"`
    @Published var preferredSummaryCategoryTokens: [String] = []
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        
        // Load saved preferences
        loadUserName()
        loadSelectedCurrency()
        loadDefaultHomeTimeFrame()
        loadSelectedTimeFrame()
        loadAppearanceMode()
        loadSummaryPreferences()
        
        // Load initial data
        loadExpenses()
        
        // Auto-select currency based on locale if not set
        autoSelectCurrencyIfNeeded()
        
        // Check if this is the first launch
        checkFirstLaunch()
        
        // Set up filtering
        setupFiltering()

        // Invalidate the custom-category cache whenever any context save
        // touches CustomCategoryEntity (CategoryViewModel CRUD, imports
        // that save normally) or the data is cleared wholesale. Batch
        // operations that bypass save notifications are covered by the
        // explicit invalidation in `reloadAfterBackupRestore()`.
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] note in
                guard Self.saveTouchedCustomCategories(note) else { return }
                DispatchQueue.main.async { self?.customCategoriesByIdCache = nil }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .dataDidClear)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.customCategoriesByIdCache = nil }
            .store(in: &cancellables)

        // Headless write paths (Siri intents, widget queue drain) insert
        // rows on a background context this VM never sees. The diff-gated
        // async reload picks the new rows up in one publish.
        NotificationCenter.default
            .publisher(for: .expensesChangedExternally)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadExpensesAsync() }
            .store(in: &cancellables)
    }

    private static func saveTouchedCustomCategories(_ note: Notification) -> Bool {
        let userInfo = note.userInfo ?? [:]
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey] {
            if let set = userInfo[key] as? Set<NSManagedObject>,
               set.contains(where: { $0 is CustomCategoryEntity }) {
                return true
            }
        }
        return false
    }

    /// Suspend until the full expense table has been published (no-op if
    /// already hydrated). Used by launch-time consumers that must not run
    /// on the partial hot window (notification digests, etc.).
    @MainActor
    func waitUntilFullyHydrated() async {
        if isFullyHydrated { return }
        for await hydrated in $isFullyHydrated.values where hydrated {
            return
        }
    }
    
    // Load individual preferences from UserDefaults
    private func loadSelectedCurrency() {
        if let savedCurrency = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedCurrency),
           let currency = Expense.Currency(rawValue: savedCurrency) {
            selectedCurrency = currency
        }
    }
    
    private func loadUserName() {
        if let savedName = UserDefaults.standard.string(forKey: UserDefaultsKeys.userName) {
            let trimmed = savedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                userName = trimmed
            }
        }
    }
    
    private func loadSelectedTimeFrame() {
        if let savedTimeFrame = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedTimeFrame),
           let timeFrame = TimeFrame(rawValue: savedTimeFrame) {
            selectedTimeFrame = timeFrame
        } else {
            // First launch (or after reset): respect the configured default instead of showing All Time.
            selectedTimeFrame = defaultHomeTimeFrame
        }
    }
    
    private func loadDefaultHomeTimeFrame() {
        if let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.defaultHomeTimeFrame),
           let timeFrame = TimeFrame(rawValue: saved) {
            defaultHomeTimeFrame = timeFrame
        } else {
            // Sensible default for most users
            defaultHomeTimeFrame = .month
        }
    }
    
    private func loadAppearanceMode() {
        if let savedAppearance = UserDefaults.standard.string(forKey: UserDefaultsKeys.appearanceMode),
           let appearance = AppearanceMode(rawValue: savedAppearance) {
            appearanceMode = appearance
        }
    }
    
    /// Re-read every preference + reload Core Data after a backup restore so
    /// the UI immediately reflects the imported state. Kept on the main actor
    /// so all `@Published` writes happen safely.
    func reloadAfterBackupRestore() {
        loadUserName()
        loadSelectedCurrency()
        loadDefaultHomeTimeFrame()
        loadSelectedTimeFrame()
        loadAppearanceMode()
        loadSummaryPreferences()
        // Imports write custom categories via batch operations that don't
        // post save notifications — flush the lookup cache explicitly.
        customCategoriesByIdCache = nil
        // PERF: async reload — the old synchronous `loadExpenses()` here
        // stalled the main thread for large imports right as the
        // "import succeeded" sheet appeared. The summary sheet doesn't
        // need the array synchronously; the diff-gated publish lands a
        // moment later and refreshes every observer.
        loadExpensesAsync()
    }
    
    // Auto-select currency based on user's locale if not already set
    private func autoSelectCurrencyIfNeeded() {
        if UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedCurrency) == nil {
            let locale = Locale.current
            if let currencyCode = locale.currency?.identifier,
               let currency = Expense.Currency(rawValue: currencyCode.uppercased()) {
                selectedCurrency = currency
            }
        }
    }
    
    // Check if this is the first launch
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasLaunchedBefore)
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasLaunchedBefore)
            hasShownCurrencyPicker = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
        }
    }
    
    // MARK: - Filtering Setup (Performance Optimized)
    
    /// Set up filtering with debouncing and background processing for smooth UI
    private func setupFiltering() {
        Publishers.CombineLatest4($expenses, $selectedCategory, $selectedCustomCategoryId, $selectedTimeFrame)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main) // Batch rapid changes
            .sink { [weak self] expenses, category, customCategoryId, timeFrame in
                self?.scheduleFilterRecompute(
                    expenses: expenses,
                    category: category,
                    customCategoryId: customCategoryId,
                    timeFrame: timeFrame
                )
            }
            .store(in: &cancellables)

        // Tag stats recompute — debounced so rapid adds/deletes don't thrash.
        $expenses
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.scheduleTagStatsRecompute(expenses: snapshot)
            }
            .store(in: &cancellables)
    }

    /// Recompute `tagStats` off-main so the input field's autocomplete is up to date
    /// without ever blocking the UI thread.
    private func scheduleTagStatsRecompute(expenses: [Expense]) {
        tagStatsTask?.cancel()
        tagStatsTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let snapshot = expenses
            let stats = await Task.detached(priority: .utility) {
                TagSuggestionProvider.computeStats(from: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            if stats != self.tagStats {
                self.tagStats = stats
            }
        }
    }
    
    // MARK: - Filter + totals pipeline (single batched pass)
    //
    // PERF: Previously this was **two** separate tasks — one to compute
    // and assign `filteredExpenses`, then a second one (`totalsTask`)
    // kicked off after the first finished that recomputed the five
    // `cached*` totals. That meant **two** runloop ticks of SwiftUI
    // invalidation per logical save: one for the filter result, then a
    // second one for the totals — and the totals task itself wrote 5
    // properties back-to-back. We measured ~6–8 `objectWillChange`
    // emissions per save with real data.
    //
    // The current pipeline:
    //   • does **filter + totals** in **one** detached background pass,
    //   • commits the entire result on the main actor in **one**
    //     synchronous burst (`applyFilterAndTotalsResult`), and
    //   • uses a single `filterTask` so cancellation is clean.
    //
    // SwiftUI coalesces multiple `objectWillChange.send()`s that fire
    // in the same runloop tick into one body re-evaluation, so all six
    // writes now produce a single UI invalidation per save instead of
    // up to eight.

    /// The result of one filter+totals pass. Combined so the main
    /// thread can commit it atomically.
    private struct FilterAndTotalsResult: Sendable {
        let filtered: [Expense]
        let total: Double
        let totalsByCategory: [Expense.Category: Double]
        let totalsByCustomId: [UUID: Double]
        let countsByCategory: [Expense.Category: Int]
        let countsByCustomId: [UUID: Int]
    }

    /// Compute filtered expenses **and** totals together off-main, then
    /// commit everything to the view model in one synchronous block on
    /// the main actor.
    private func scheduleFilterRecompute(
        expenses: [Expense],
        category: Expense.Category?,
        customCategoryId: UUID?,
        timeFrame: TimeFrame
    ) {
        filterTask?.cancel()

        filterTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Coalesce very rapid changes (quick category taps, fast typing
            // in filters, etc.). 30 ms is small enough to feel instant but
            // big enough to skip a fan of duplicate runs.
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !Task.isCancelled else { return }

            // Snapshot the currently-published values so the detached
            // pass can equality-check its result OFF-main. When nothing
            // changed (very common: an `$expenses` publish whose rows
            // all fall outside the active timeframe filter, a no-op
            // hydration refresh, etc.) we skip the six `@Published`
            // writes entirely — otherwise every observer of this view
            // model (Today, Activity, Insights, You) got an
            // `objectWillChange` for identical data.
            let previousFiltered = self.filteredExpenses

            let result: FilterAndTotalsResult? = await Task.detached(priority: .userInitiated) {
                let filtered = ExpenseFilter.apply(
                    expenses: expenses,
                    category: category,
                    customCategoryId: customCategoryId,
                    timeFrame: timeFrame,
                    referenceDate: Date()
                )

                var total: Double = 0
                var totalsByCategory: [Expense.Category: Double] = [:]
                var totalsByCustomId: [UUID: Double] = [:]
                var countsByCategory: [Expense.Category: Int] = [:]
                var countsByCustomId: [UUID: Int] = [:]

                for expense in filtered {
                    guard expense.amount.isFinite else { continue }
                    // Refund-aware: refunds subtract from totals so the
                    // headline amount on Home reflects "money actually
                    // spent" rather than "money moved". `signedAmount`
                    // returns -amount for refunds, +amount otherwise.
                    let signed = expense.signedAmount

                    total += signed
                    totalsByCategory[expense.category, default: 0] += signed
                    countsByCategory[expense.category, default: 0] += 1

                    if expense.category == .custom, let customId = expense.customCategoryId {
                        totalsByCustomId[customId, default: 0] += signed
                        countsByCustomId[customId, default: 0] += 1
                    }
                }

                // Everything else in the result is a pure function of
                // `filtered`, so one array comparison decides whether
                // the whole commit is a no-op. O(N), but off-main.
                if filtered == previousFiltered { return nil }

                return FilterAndTotalsResult(
                    filtered: filtered,
                    total: total.isFinite ? total : 0,
                    totalsByCategory: totalsByCategory,
                    totalsByCustomId: totalsByCustomId,
                    countsByCategory: countsByCategory,
                    countsByCustomId: countsByCustomId
                )
            }.value

            guard !Task.isCancelled, let result else { return }
            self.applyFilterAndTotalsResult(result)
        }
    }

    /// Commit a finished filter+totals pass to the view model. **All six
    /// writes must happen in this synchronous block** so SwiftUI batches
    /// them into one body re-evaluation. Do not split this up or insert
    /// `await`s between assignments — that's exactly the pattern this
    /// helper exists to prevent.
    private func applyFilterAndTotalsResult(_ result: FilterAndTotalsResult) {
        filteredExpenses = result.filtered
        cachedTotalAmount = result.total
        cachedTotalsByCategory = result.totalsByCategory
        cachedTotalsByCustomId = result.totalsByCustomId
        cachedCountsByCategory = result.countsByCategory
        cachedCountsByCustomId = result.countsByCustomId
    }
    
    /// Get total expenses - uses cached value for O(1) performance
    /// - Parameter category: Optional category to filter by. If nil, returns total of all filtered expenses.
    /// - Returns: The total amount for the specified category or all expenses
    func totalExpenses(for category: Expense.Category? = nil) -> Double {
        // Use cached values for O(1) access
        if let category = category {
            return cachedTotalsByCategory[category, default: 0]
        }
        return cachedTotalAmount
    }
    
    /// Get total expenses for a custom category - uses cached value for O(1) performance
    /// - Parameter customCategoryId: The UUID of the custom category
    /// - Returns: The total amount for the specified custom category
    func totalExpenses(forCustomCategoryId customCategoryId: UUID) -> Double {
        return cachedTotalsByCustomId[customCategoryId, default: 0]
    }
    
    /// Get expense count for a category - uses cached value for O(1) performance
    func expenseCount(for category: Expense.Category) -> Int {
        return cachedCountsByCategory[category, default: 0]
    }
    
    /// Get expense count for a custom category - uses cached value for O(1) performance
    func expenseCount(forCustomCategoryId customCategoryId: UUID) -> Int {
        return cachedCountsByCustomId[customCategoryId, default: 0]
    }
    
    // NOTE: removed two dead legacy helpers here —
    // `calculateTotalExpenses(for:)` (no call sites, and it summed raw
    // `amount`, ignoring refunds — a landmine for any future caller;
    // live totals come from `cachedTotalAmount` / `signedAmount`) and
    // `filterExpenses(...)` (a pass-through to `ExpenseFilter.apply`,
    // which callers use directly).
    
    // Currency symbol for formatting
    var currencySymbol: String {
        return selectedCurrency.symbol
    }
    
    
    func getSummaryCardsData(customCategories: [CustomCategory]? = nil) -> [(category: Expense.Category?, customCategoryId: UUID?, title: String, amount: Double, icon: String, color: Color)] {
        var cardsData: [(category: Expense.Category?, customCategoryId: UUID?, title: String, amount: Double, icon: String, color: Color)] = []
        
        // Use cached total for O(1) access
        let totalAmount = cachedTotalAmount
        
        // Always include total expenses as first card
        cardsData.append((
            category: nil,
            customCategoryId: nil,
            title: "Total Expenses",
            amount: totalAmount,
            icon: "creditcard.fill",
            color: .appPrimary
        ))
        
        // Add user-selected categories (up to 4 pinned).
        let customCategories = customCategories ?? getCustomCategories()
        for token in preferredSummaryCategoryTokens.prefix(4) {
            if token.lowercased().hasPrefix("custom:") {
                let idString = String(token.dropFirst("custom:".count))
                guard let customId = UUID(uuidString: idString),
                      let custom = customCategories.first(where: { $0.id == customId }) else {
                    continue
                }
                
                // Use cached value for O(1) access
                let amount = cachedTotalsByCustomId[customId, default: 0]
                
                cardsData.append((
                    category: .custom,
                    customCategoryId: customId,
                    title: custom.name,
                    amount: amount,
                    icon: custom.icon,
                    color: Color.forCategory(custom.colorName)
                ))
            } else if let category = Expense.Category(rawValue: token), category != .custom {
                // Use cached value for O(1) access
                let amount = cachedTotalsByCategory[category, default: 0]
                
                cardsData.append((
                    category: category,
                    customCategoryId: nil,
                    title: category.displayName,
                    amount: amount,
                    icon: category.icon,
                    color: Color.forCategory(category.color)
                ))
            }
        }
        
        return cardsData
    }
} 
