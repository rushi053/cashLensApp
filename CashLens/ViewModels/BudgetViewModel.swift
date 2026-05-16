import Foundation
import SwiftUI
import Combine
@preconcurrency import CoreData
import UserNotifications

@MainActor
class BudgetViewModel: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var budgetProgress: [UUID: BudgetProgress] = [:]

    struct BudgetProgress: Equatable {
        let spent: Double
        let limit: Double
        let percentage: Double
        let daysRemaining: Int
        let totalDays: Int
        let status: Status

        enum Status: Equatable {
            case safe
            case warning
            case exceeded
        }

        /// Average spent per day elapsed in period (for "pace" insight).
        var dailyPace: Double {
            let elapsedDays = max(1, totalDays - daysRemaining)
            return spent / Double(elapsedDays)
        }

        var projectedTotal: Double {
            guard totalDays > 0 else { return spent }
            return dailyPace * Double(totalDays)
        }

        var remainingBudget: Double {
            max(0, limit - spent)
        }

        var dailyAllowance: Double {
            guard daysRemaining > 0 else { return 0 }
            return remainingBudget / Double(daysRemaining)
        }
    }

    // MARK: - Dependencies

    nonisolated private let viewContext: NSManagedObjectContext
    private weak var expenseViewModel: ExpenseViewModel?
    private var fetchedResultsController: NSFetchedResultsController<BudgetEntity>?
    private var cancellables = Set<AnyCancellable>()
    private var recomputeTask: Task<Void, Never>?

    /// In-memory snapshot for crossing detection within the same session (instant updates).
    private var lastPublishedProgress: [UUID: BudgetProgress] = [:]

    // MARK: - Init

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        super.init()
        setupFetchedResultsController()
    }

    func setExpenseViewModel(_ vm: ExpenseViewModel) {
        self.expenseViewModel = vm

        vm.$expenses
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)

        scheduleRecompute()
    }

    // MARK: - FRC

    private func setupFetchedResultsController() {
        let request: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BudgetEntity.isActive, ascending: false),
            NSSortDescriptor(keyPath: \BudgetEntity.createdAt, ascending: true)
        ]

        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        fetchedResultsController = controller

        do {
            try controller.performFetch()
            updateFromFetchedResults()
        } catch {
            budgets = []
        }
    }

    private func updateFromFetchedResults() {
        budgets = (fetchedResultsController?.fetchedObjects ?? []).toBudgets()
        scheduleRecompute()
    }

    // MARK: - CRUD

    func addBudget(_ budget: Budget) {
        viewContext.performAndWait {
            BudgetEntity.fromBudget(budget, context: viewContext)
            persistIfNeeded()
        }
        cancelPendingNotifications(for: budget.id)
    }

    func updateBudget(_ budget: Budget) {
        let request: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", budget.id as CVarArg)

        viewContext.performAndWait {
            if let entity = try? viewContext.fetch(request).first {
                entity.updateFromBudget(budget)
                persistIfNeeded()
            }
        }
        BudgetAlertState.clearTracking(for: budget)
        cancelPendingNotifications(for: budget.id)
    }

    func deleteBudget(_ budget: Budget) {
        let request: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", budget.id as CVarArg)

        viewContext.performAndWait {
            if let entities = try? viewContext.fetch(request) {
                for entity in entities { viewContext.delete(entity) }
                persistIfNeeded()
            }
        }
        BudgetAlertState.clearTracking(for: budget)
        cancelPendingNotifications(for: budget.id)
        lastPublishedProgress[budget.id] = nil
    }

    func toggleBudgetActive(_ budget: Budget) {
        var updated = budget
        updated.isActive.toggle()
        updateBudget(updated)
    }

    /// Nonisolated Core Data save helper. Safe to call from inside a
    /// `viewContext.performAndWait` closure; the enclosing perform block
    /// serializes access to the context.
    private nonisolated func persistIfNeeded() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            // Surface to the global save-error banner — budgets that
            // silently fail to persist are particularly bad because
            // the alert thresholds are the user's spending guardrails.
            SaveErrorReporter.report(operation: "saving budget", error: error)
        }
    }

    // MARK: - Progress Computation (debounced + background)

    private func scheduleRecompute() {
        recomputeTask?.cancel()
        recomputeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 55_000_000)
            guard !Task.isCancelled else { return }

            guard let vm = self.expenseViewModel else { return }

            let expenses = vm.expenses
            let activeBudgets = self.budgets.filter(\.isActive)
            let memorySnapshot = self.lastPublishedProgress

            let results = await Task.detached(priority: .userInitiated) { [expenses, activeBudgets, memorySnapshot] in
                var progressMap: [UUID: BudgetProgress] = [:]
                for budget in activeBudgets {
                    let range = budget.period.dateRange
                    let matching = expenses.filter { expense in
                        guard expense.date >= range.start && expense.date < range.end else { return false }
                        switch budget.categoryFilter {
                        case .overall:
                            return true
                        case .defaultCategory(let raw):
                            return expense.category.rawValue == raw
                        case .customCategory(let id):
                            return expense.category == .custom && expense.customCategoryId == id
                        }
                    }
                    // Refund-aware: refunds reduce a budget's "spent" total
                    // so a $200 returned headphone reads as $200 freed up.
                    // Floor at 0 so a budget can never look negative.
                    let raw = matching.reduce(0) { partial, e in
                        let v = e.amount.isFinite ? e.signedAmount : 0
                        return partial + v
                    }
                    let spent = max(0, raw)
                    let pct = budget.amount > 0 ? spent / budget.amount : 0

                    let status: BudgetProgress.Status
                    if pct >= 1.0 { status = .exceeded }
                    else if pct >= 0.8 { status = .warning }
                    else { status = .safe }

                    progressMap[budget.id] = BudgetProgress(
                        spent: spent,
                        limit: budget.amount,
                        percentage: pct,
                        daysRemaining: budget.period.daysRemaining,
                        totalDays: budget.period.totalDays,
                        status: status
                    )
                }
                return (progressMap, memorySnapshot)
            }.value

            guard !Task.isCancelled else { return }

            self.applyProgressAndEvaluateAlerts(
                newMap: results.0,
                memorySnapshot: results.1
            )
        }
    }

    private func applyProgressAndEvaluateAlerts(
        newMap: [UUID: BudgetProgress],
        memorySnapshot: [UUID: BudgetProgress]
    ) {
        let activeBudgets = budgets.filter(\.isActive)

        for budget in activeBudgets {
            let newPct = newMap[budget.id]?.percentage ?? 0

            let oldFromMemory = memorySnapshot[budget.id]?.percentage
            let oldFromDisk = BudgetAlertState.lastPercent(for: budget)
            let oldPct: Double?
            if let m = oldFromMemory {
                oldPct = m
            } else if let d = oldFromDisk {
                oldPct = d
            } else {
                oldPct = nil
            }

            if let old = oldPct {
                for threshold in budget.alertAtPercentages.sorted() where threshold > 0 {
                    if old < threshold && newPct >= threshold - 0.000_001,
                       !BudgetAlertState.hasFired(budget: budget, threshold: threshold) {
                        scheduleBudgetNotification(budget: budget, threshold: threshold, spentFraction: newPct)
                        BudgetAlertState.markFired(budget: budget, threshold: threshold)
                    }
                }
            }

            BudgetAlertState.setLastPercent(newPct, for: budget)
        }

        lastPublishedProgress = newMap
        budgetProgress = newMap
    }

    /// Foreground hook: ensures progress matches data after long background (no-op if already synced).
    func refreshProgressFromData() {
        scheduleRecompute()
    }

    // MARK: - Notifications

    private func notificationIdentifier(budgetId: UUID, threshold: Double, periodStart: TimeInterval) -> String {
        let t = Int((threshold * 100).rounded())
        return "budget_alert_\(budgetId.uuidString)_\(t)_\(Int(periodStart))"
    }

    private func cancelPendingNotifications(for budgetId: UUID) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix("budget_alert_\(budgetId.uuidString)_") }
                .map(\.identifier)
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    private func scheduleBudgetNotification(budget: Budget, threshold: Double, spentFraction: Double) {
        let periodStart = budget.period.dateRange.start.timeIntervalSince1970
        let id = notificationIdentifier(budgetId: budget.id, threshold: threshold, periodStart: periodStart)

        Task {
            let ok = await NotificationScheduler.ensureAuthorized()
            guard ok else { return }

            let content = UNMutableNotificationContent()
            let pctText = "\(Int((threshold * 100).rounded()))%"

            if threshold >= 1.0 {
                content.title = "Budget exceeded"
                content.body = "You've gone over your \"\(budget.name)\" budget. Open CashLens to review."
            } else {
                content.title = "Budget alert"
                content.body = "You've reached \(pctText) of your \"\(budget.name)\" budget."
            }
            content.sound = .default
            let range = budget.period.dateRange
            // AllExpenses date range uses inclusive end-of-period day; budget range.end is exclusive.
            let lastInclusiveDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            var info: [String: Any] = [
                NotificationUserInfoKeys.route: NotificationRouteTypes.allExpenses,
                NotificationUserInfoKeys.rangeStart: range.start.timeIntervalSince1970,
                NotificationUserInfoKeys.rangeEnd: lastInclusiveDay.timeIntervalSince1970
            ]
            switch budget.categoryFilter {
            case .overall:
                break
            case .defaultCategory(let raw):
                info[NotificationUserInfoKeys.categoryRaw] = raw
            case .customCategory(let uuid):
                info[NotificationUserInfoKeys.customCategoryId] = uuid.uuidString
            }
            content.userInfo = info

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, 1), repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("BudgetViewModel: notification add failed — \(error.localizedDescription)")
            }

            await MainActor.run {
                HapticManager.shared.warning()
            }
        }
    }

    // MARK: - Helpers

    var activeBudgets: [Budget] {
        budgets.filter(\.isActive)
    }

    func progress(for budget: Budget) -> BudgetProgress {
        budgetProgress[budget.id] ?? BudgetProgress(
            spent: 0, limit: budget.amount, percentage: 0,
            daysRemaining: budget.period.daysRemaining,
            totalDays: budget.period.totalDays,
            status: .safe
        )
    }

    var primaryBudget: Budget? {
        activeBudgets.first { $0.categoryFilter.isOverall } ?? activeBudgets.first
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension BudgetViewModel: NSFetchedResultsControllerDelegate {
    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            self.updateFromFetchedResults()
        }
    }
}
