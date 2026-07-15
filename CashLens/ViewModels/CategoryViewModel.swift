import Foundation
import SwiftUI
import CoreData
import Combine
import UserNotifications

@MainActor
class CategoryViewModel: NSObject, ObservableObject {
    @Published var customCategories: [CustomCategory] = []
    private let viewContext: NSManagedObjectContext
    private var fetchedResultsController: NSFetchedResultsController<CustomCategoryEntity>?
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        super.init()
        // Keep categories in sync automatically
        setupFetchedResultsController()
    }
    
    // Create default custom categories if none exist
    func createDefaultCategoriesIfNeeded() {
        if customCategories.isEmpty {
            let defaultCategories = [
                CustomCategory(name: "Pets", icon: "pawprint.fill", colorName: "celadon"),
                CustomCategory(name: "Gifts", icon: "gift.fill", colorName: "teaRose"),
                CustomCategory(name: "Tech", icon: "desktopcomputer", colorName: "electricBlue")
            ]
            
            for category in defaultCategories {
                addCustomCategory(category)
            }
        }
    }
    
    // Load custom categories from CoreData (manual refresh; usually not needed because of FRC)
    func loadCustomCategories() {
        do {
            try fetchedResultsController?.performFetch()
            updateFromFetchedResults()
        } catch {
            print("Error loading custom categories: \(error.localizedDescription)")
            self.customCategories = []
        }
    }
    
    // Add a new custom category
    func addCustomCategory(_ category: CustomCategory) {
        _ = CustomCategoryEntity.fromCustomCategory(category, context: viewContext)
        saveContext()
    }
    
    // Get a custom category by ID
    func getCustomCategory(id: UUID) -> CustomCategory? {
        return customCategories.first { $0.id == id }
    }
    
    // Update a custom category
    func updateCustomCategory(_ category: CustomCategory) {
        let fetchRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", category.id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let entity = results.first {
                entity.name = category.name
                entity.icon = category.icon
                entity.colorName = category.colorName
                saveContext()
            }
        } catch {
            print("Error updating custom category: \(error.localizedDescription)")
        }
    }
    
    // Delete a custom category.
    //
    // Also cleans up everything that references the deleted id so no
    // dangling `customCategoryId` survives:
    //   • Subscriptions retarget to "Other" (they're real recurring
    //     bills — keep them, relabel them).
    //   • Budgets filtered to this category are deleted (a cap on a
    //     category that no longer exists is meaningless; silently
    //     retargeting it to all-spending would misfire alerts).
    //   • Expenses are handled by the caller via
    //     `ExpenseViewModel.moveExpensesFromDeletedCustomCategory`,
    //     which also mirrors the change into its in-memory array.
    //
    // Subscription/Budget view models observe the same viewContext via
    // fetched-results controllers, so their published arrays update on
    // this save without extra wiring.
    func deleteCustomCategory(id: UUID) {
        let fetchRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let subscriptionFetch: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        subscriptionFetch.predicate = NSPredicate(format: "customCategoryId == %@", id as CVarArg)

        let budgetFetch: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
        budgetFetch.predicate = NSPredicate(format: "categoryFilterCustomId == %@", id as CVarArg)

        do {
            for subscription in try viewContext.fetch(subscriptionFetch) {
                subscription.category = Expense.Category.other.rawValue
                subscription.customCategoryId = nil
            }

            for budgetEntity in try viewContext.fetch(budgetFetch) {
                // Same cleanup `BudgetViewModel.deleteBudget` performs:
                // drop alert-crossing state and any queued notification
                // so a deleted budget can't buzz from beyond the grave.
                let budget = budgetEntity.toBudget()
                BudgetAlertState.clearTracking(for: budget)
                let prefix = "budget_alert_\(budget.id.uuidString)_"
                UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                    let ids = requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
                    if !ids.isEmpty {
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                    }
                }
                viewContext.delete(budgetEntity)
            }

            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                viewContext.delete(entity)
            }
            saveContext()
        } catch {
            print("Error deleting custom category: \(error.localizedDescription)")
        }
    }
    
    // Mirror of the cleanup above for *hiding a default category*.
    // Hiding used to only retarget expenses (the caller handles that),
    // leaving subscriptions billed under an invisible category and
    // budgets tracking a filter whose spend just moved to "Other" —
    // those budgets would sit at 0% forever while the real spending
    // went uncounted.
    func cleanupAfterHidingDefaultCategory(rawValue: String) {
        let subscriptionFetch: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        subscriptionFetch.predicate = NSPredicate(
            format: "category == %@ AND customCategoryId == nil", rawValue
        )

        let budgetFetch: NSFetchRequest<BudgetEntity> = BudgetEntity.fetchRequest()
        budgetFetch.predicate = NSPredicate(
            format: "categoryFilterType == %@ AND categoryFilterDefaultRaw == %@", "default", rawValue
        )

        do {
            for subscription in try viewContext.fetch(subscriptionFetch) {
                subscription.category = Expense.Category.other.rawValue
            }

            for budgetEntity in try viewContext.fetch(budgetFetch) {
                let budget = budgetEntity.toBudget()
                BudgetAlertState.clearTracking(for: budget)
                let prefix = "budget_alert_\(budget.id.uuidString)_"
                UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                    let ids = requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
                    if !ids.isEmpty {
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                    }
                }
                viewContext.delete(budgetEntity)
            }

            saveContext()
        } catch {
            print("Error cleaning up after hiding default category: \(error.localizedDescription)")
        }
    }
    
    // Check if a category name already exists
    func categoryNameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        if let id = id {
            return customCategories.contains { $0.name.lowercased() == name.lowercased() && $0.id != id }
        } else {
            return customCategories.contains { $0.name.lowercased() == name.lowercased() }
        }
    }
    
    // Save context
    private func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                // Surface failures to the global save-error banner
                // so a silent persistence failure doesn't leave
                // category UI looking saved when it isn't.
                SaveErrorReporter.report(operation: "saving category", error: error)
            }
        }
    }
    
    private func setupFetchedResultsController() {
        let fetchRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
        
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
            print("Error setting up category fetched results controller: \(error.localizedDescription)")
            customCategories = []
        }
    }
    
    private func updateFromFetchedResults() {
        let entities = fetchedResultsController?.fetchedObjects ?? []
        customCategories = entities.toCustomCategories()
    }
} 

extension CategoryViewModel: NSFetchedResultsControllerDelegate {
    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        // FRC delegate callbacks may arrive on the context queue; hop back to the main actor for @Published updates.
        Task { @MainActor in
            self.updateFromFetchedResults()
        }
    }
} 