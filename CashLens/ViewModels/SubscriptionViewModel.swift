import Foundation
import SwiftUI
import Combine
import CoreData
import UserNotifications

@MainActor
class SubscriptionViewModel: NSObject, ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var dueSubscriptions: [Subscription] = []
    @Published var filteredSubscriptions: [Subscription] = []
    @Published var activeFilter: SubscriptionFilter = .all
    
    enum SubscriptionFilter: CaseIterable {
        case all
        case dueSoon
        case active
        case paused
        
        var title: String {
            switch self {
            case .all: return "All Subscriptions"
            case .dueSoon: return "Due Soon"
            case .active: return "Active"
            case .paused: return "Paused"
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .dueSoon: return "clock.fill"
            case .active: return "checkmark.circle.fill"
            case .paused: return "pause.circle.fill"
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    private weak var expenseViewModel: ExpenseViewModel?
    private var fetchedResultsController: NSFetchedResultsController<SubscriptionEntity>?
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext, expenseViewModel: ExpenseViewModel? = nil) {
        self.viewContext = context
        self.expenseViewModel = expenseViewModel
        super.init()
        setupFetchedResultsController()
        setupDueSubscriptionsFiltering()
        setupSubscriptionFiltering()
        setupCurrencyUpdateListener()
    }
    
    // MARK: - Core Data Operations
    
    func loadSubscriptions() {
        do {
            try fetchedResultsController?.performFetch()
            updateFromFetchedResults()
        } catch {
            print("Error loading subscriptions: \(error.localizedDescription)")
            subscriptions = []
        }
    }
    
    func addSubscription(_ subscription: Subscription) async {
        // Request notification permission only if reminders are enabled
        if subscription.reminderEnabled {
            await requestNotificationPermissionIfNeeded()
        }
        
        viewContext.performAndWait {
            _ = SubscriptionEntity.fromSubscription(subscription, context: viewContext)
            saveContext()
        }
        syncNotification(for: subscription)
        
        // Track successful action for feedback request
        FeedbackManager.shared.incrementSuccessfulAction()
    }
    
    func updateSubscription(_ subscription: Subscription) async {
        // Request notification permission only if reminders are enabled
        if subscription.reminderEnabled {
            await requestNotificationPermissionIfNeeded()
        }
        
        updateSubscriptionInternal(subscription)
    }
    
    // Internal synchronous method for updating subscriptions without permission requests
    private func updateSubscriptionInternal(_ subscription: Subscription) {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", subscription.id as CVarArg)
        
        viewContext.performAndWait {
            do {
                let results = try viewContext.fetch(fetchRequest)
                if let entity = results.first {
                    entity.updateFromSubscription(subscription)
                    saveContext()
                }
            } catch {
                print("Error updating subscription: \(error.localizedDescription)")
            }
        }
        syncNotification(for: subscription)
    }
    
    func deleteSubscription(_ subscription: Subscription) {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", subscription.id as CVarArg)
        
        viewContext.performAndWait {
            do {
                let results = try viewContext.fetch(fetchRequest)
                for entity in results {
                    viewContext.delete(entity)
                }
                saveContext()
            } catch {
                print("Error deleting subscription: \(error.localizedDescription)")
            }
        }
        cancelNotificationForSubscription(subscription)
    }
    
    func toggleSubscriptionStatus(_ subscription: Subscription) async {
        var updatedSubscription = subscription
        updatedSubscription.isActive.toggle()
        await updateSubscription(updatedSubscription)
    }
    
    private func saveContext() {
        do {
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            print("Error saving subscription context: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Auto-sync via NSFetchedResultsController
    
    private func setupFetchedResultsController() {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
            NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
        ]
        
        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
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
            print("Error setting up subscription fetched results controller: \(error.localizedDescription)")
            subscriptions = []
        }
    }
    
    private func updateFromFetchedResults() {
        let entities = fetchedResultsController?.fetchedObjects ?? []
        
        // Repair legacy/bad data: some older records may have a missing UUID id.
        // Without a stable id, edits won't persist (update fetch can't find the entity),
        // and notification identifiers become unstable.
        var repairedMissingIDs = false
        viewContext.performAndWait {
            for entity in entities where entity.id == nil {
                entity.id = UUID()
                repairedMissingIDs = true
            }
            if repairedMissingIDs {
                saveContext()
            }
        }
        
        subscriptions = entities.map { $0.toSubscription() }
        
        if repairedMissingIDs {
            resyncAllSubscriptionNotifications()
        }
    }

    /// Cleans up any stale pending subscription reminder notifications and re-schedules
    /// reminders for the current in-memory subscriptions list.
    private func resyncAllSubscriptionNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            
            let staleIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("subscription_") }
            
            if !staleIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
            
            Task { @MainActor in
                // Re-schedule reminders based on latest subscription state
                for subscription in self.subscriptions where subscription.isActive && subscription.reminderEnabled {
                    self.scheduleNotificationForSubscription(subscription)
                }
            }
        }
    }
    
    // MARK: - Due Subscriptions Management
    
    private func setupDueSubscriptionsFiltering() {
        $subscriptions
            .map { subscriptions in
                subscriptions.filter { $0.isDue }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.dueSubscriptions, on: self)
            .store(in: &cancellables)
    }
    
    func checkAndProcessDueSubscriptions() {
        for subscription in dueSubscriptions {
            processSubscription(subscription)
        }
    }
    
    private func processSubscription(_ subscription: Subscription) {
        // Create expense from subscription
        var expense = subscription.toExpense()
        expense.isFromSubscription = true
        expense.subscriptionId = subscription.id
        
        // Add expense through the expense view model
        expenseViewModel?.addExpense(expense)
        
        // Update subscription's next due date
        var updatedSubscription = subscription
        updatedSubscription.updateNextDueDate()
        updateSubscriptionInternal(updatedSubscription)
        
        print("Processed subscription: \(subscription.name) - Next due: \(updatedSubscription.formattedNextDueDate)")
    }
    
    // MARK: - Statistics
    
    func monthlyEquivalentAmount(for subscription: Subscription) -> Double {
        switch subscription.frequency {
        case .daily: return subscription.amount * 30 // Approximate
        case .weekly: return subscription.amount * 4.33 // Approximate
        case .monthly: return subscription.amount
        case .quarterly: return subscription.amount / 3
        case .yearly: return subscription.amount / 12
        }
    }
    
    var totalMonthlyAmount: Double {
        subscriptions
            .filter { $0.isActive }
            .reduce(0) { total, subscription in
                total + monthlyEquivalentAmount(for: subscription)
            }
    }
    
    func formattedMonthlyEquivalent(for subscription: Subscription) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: monthlyEquivalentAmount(for: subscription))) ?? "0.00"
        return "\(subscription.currency.symbol)\(formatted)/mo"
    }
    
    var activeSubscriptionsCount: Int {
        subscriptions.filter { $0.isActive }.count
    }
    
    var upcomingSubscriptions: [Subscription] {
        let calendar = Calendar.current
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        
        return subscriptions
            .filter { $0.isActive && $0.nextDueDate <= nextWeek }
            .sorted { $0.nextDueDate < $1.nextDueDate }
    }
    
    // MARK: - Notifications
    
    // Request notification permission only when needed (contextually)
    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        
        // Check current authorization status
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .notDetermined:
            // Only request permission if not determined yet
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied")
                }
            } catch {
                print("Notification permission error: \(error.localizedDescription)")
            }
        case .authorized, .provisional:
            // Already authorized, no need to request again
            break
        case .denied:
            // Permission was denied, we can't request again programmatically
            print("Notification permission was previously denied")
        case .ephemeral:
            // For app clips, not applicable here
            break
        @unknown default:
            break
        }
    }
    
    private func scheduleNotificationForSubscription(_ subscription: Subscription) {
        guard subscription.reminderEnabled && subscription.isActive else { return }
        
        // Check notification permission before scheduling
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("Cannot schedule notification: permission not granted")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Subscription Due"
            content.body = "\(subscription.name) payment of \(subscription.formattedAmount) is due soon"
            content.sound = .default
            content.categoryIdentifier = "SUBSCRIPTION_REMINDER"
            
            let calendar = Calendar.current
            let reminderDate = calendar.date(byAdding: .day, value: -subscription.reminderDaysBefore, to: subscription.nextDueDate) ?? subscription.nextDueDate
            
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: "subscription_\(subscription.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error.localizedDescription)")
                } else {
                    print("Successfully scheduled notification for \(subscription.name)")
                }
            }
        }
    }
    
    private func cancelNotificationForSubscription(_ subscription: Subscription) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["subscription_\(subscription.id.uuidString)"]
        )
    }
    
    /// Ensure the correct reminder is scheduled for the given subscription.
    /// - If reminders are disabled or subscription is inactive: cancel any pending reminder.
    /// - If enabled and active: replace existing reminder with an updated one.
    private func syncNotification(for subscription: Subscription) {
        // Always cancel first to avoid stale reminders when toggling settings
        cancelNotificationForSubscription(subscription)
        
        // Then schedule only if the subscription should have an active reminder
        guard subscription.isActive && subscription.reminderEnabled else { return }
        scheduleNotificationForSubscription(subscription)
    }
    
    // MARK: - Helper Methods
    
    func setExpenseViewModel(_ viewModel: ExpenseViewModel) {
        self.expenseViewModel = viewModel
    }
    
    func formattedTotalMonthlyAmount(currency: Expense.Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: totalMonthlyAmount)) ?? "0.00"
        return "\(currency.symbol)\(formatted)"
    }
    
    // Manual trigger for testing
    func manuallyProcessDueSubscriptions() {
        checkAndProcessDueSubscriptions()
    }
    
    // MARK: - Manual Payment Processing
    
    func markSubscriptionAsPaid(_ subscription: Subscription) async {
        // Create expense from subscription
        var expense = subscription.toExpense()
        expense.isFromSubscription = true
        expense.subscriptionId = subscription.id
        
        // Add expense through the expense view model
        expenseViewModel?.addExpense(expense)
        
        // Update subscription's next due date
        var updatedSubscription = subscription
        updatedSubscription.updateNextDueDate()
        await updateSubscription(updatedSubscription)
        
        print("Marked subscription as paid: \(subscription.name) - Next due: \(updatedSubscription.formattedNextDueDate)")
    }
    
    // Setup listener for currency updates
    private func setupCurrencyUpdateListener() {
        NotificationCenter.default
            .publisher(for: .subscriptionCurrencyUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let userInfo = notification.userInfo,
                   let updateCount = userInfo["updateCount"] as? Int,
                   let newCurrency = userInfo["newCurrency"] as? String {
                    print("🔄 Currency update: \(updateCount) subscription(s) updated to \(newCurrency)")
                } else {
                    print("🔄 Received subscription currency update notification")
                }
                self?.loadSubscriptions()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Filtering
    
    func setFilter(_ filter: SubscriptionFilter) {
        activeFilter = filter
        applyCurrentFilter()
    }
    
    private func setupSubscriptionFiltering() {
        // Set up filtering that responds to changes in subscriptions or active filter
        Publishers.CombineLatest($subscriptions, $activeFilter)
            .map { [weak self] subscriptions, filter in
                self?.filterSubscriptions(subscriptions, by: filter) ?? []
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.filteredSubscriptions, on: self)
            .store(in: &cancellables)
    }
    
    private func filterSubscriptions(_ subscriptions: [Subscription], by filter: SubscriptionFilter) -> [Subscription] {
        switch filter {
        case .all:
            return subscriptions
        case .dueSoon:
            return subscriptions.filter { $0.isActive && $0.daysUntilNext <= 7 }
        case .active:
            return subscriptions.filter { $0.isActive }
        case .paused:
            return subscriptions.filter { !$0.isActive }
        }
    }
    
    private func applyCurrentFilter() {
        filteredSubscriptions = filterSubscriptions(subscriptions, by: activeFilter)
    }
    
    func clearFilter() {
        activeFilter = .all
    }
} 

extension SubscriptionViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            self.updateFromFetchedResults()
        }
    }
}