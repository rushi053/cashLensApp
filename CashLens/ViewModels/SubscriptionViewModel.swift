import Foundation
import SwiftUI
import Combine
import CoreData
import UserNotifications

@MainActor
class SubscriptionViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var dueSubscriptions: [Subscription] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    private weak var expenseViewModel: ExpenseViewModel?
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext, expenseViewModel: ExpenseViewModel? = nil) {
        self.viewContext = context
        self.expenseViewModel = expenseViewModel
        
        loadSubscriptions()
        setupDueSubscriptionsFiltering()
    }
    
    // MARK: - Core Data Operations
    
    func loadSubscriptions() {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
            NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
        ]
        
        do {
            let entities = try viewContext.fetch(fetchRequest)
            subscriptions = entities.map { $0.toSubscription() }
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
        
        _ = SubscriptionEntity.fromSubscription(subscription, context: viewContext)
        saveContext()
        loadSubscriptions()
        scheduleNotificationForSubscription(subscription)
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
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let entity = results.first {
                entity.updateFromSubscription(subscription)
                saveContext()
                loadSubscriptions()
                scheduleNotificationForSubscription(subscription)
            }
        } catch {
            print("Error updating subscription: \(error.localizedDescription)")
        }
    }
    
    func deleteSubscription(_ subscription: Subscription) {
        let fetchRequest: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", subscription.id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                viewContext.delete(entity)
            }
            saveContext()
            loadSubscriptions()
            cancelNotificationForSubscription(subscription)
        } catch {
            print("Error deleting subscription: \(error.localizedDescription)")
        }
    }
    
    func toggleSubscriptionStatus(_ subscription: Subscription) async {
        var updatedSubscription = subscription
        updatedSubscription.isActive.toggle()
        await updateSubscription(updatedSubscription)
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving subscription context: \(error.localizedDescription)")
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
    
    var totalMonthlyAmount: Double {
        subscriptions
            .filter { $0.isActive }
            .reduce(0) { total, subscription in
                switch subscription.frequency {
                case .daily: return total + (subscription.amount * 30) // Approximate
                case .weekly: return total + (subscription.amount * 4.33) // Approximate
                case .monthly: return total + subscription.amount
                case .quarterly: return total + (subscription.amount / 3)
                case .yearly: return total + (subscription.amount / 12)
                }
            }
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
} 