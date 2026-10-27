import Foundation
import CoreData

extension ExpenseViewModel {
    // MARK: - Category Helpers
    
    func getCustomCategories() -> [CustomCategory] {
        let fetchRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            return results.toCustomCategories()
        } catch {
            print("Error loading custom categories in ExpenseViewModel: \(error.localizedDescription)")
            return []
        }
    }
    
    func getAvailableDefaultCategories() -> [Expense.Category] {
        let deletedCategories = getDeletedDefaultCategories()
        return Expense.Category.allCases.filter { category in
            category != .custom && !deletedCategories.contains(category.rawValue)
        }
    }
    
    func getDeletedDefaultCategories() -> Set<String> {
        if let deleted = UserDefaults.standard.array(forKey: UserDefaultsKeys.deletedDefaultCategories) as? [String] {
            return Set(deleted)
        }
        return []
    }
    
    func moveExpensesFromDeletedCategory(_ categoryName: String) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "category == %@", categoryName)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                entity.category = Expense.Category.other.rawValue
            }
            
            if !results.isEmpty {
                saveContext()
                // PERF: Mirror the reassignment in-memory instead of
                // refetching every expense from disk. The category
                // rename is a one-shot move from `categoryName` to
                // `.other`; date order is unaffected so no resort.
                var mutated = expenses
                for i in mutated.indices where mutated[i].category.rawValue == categoryName {
                    mutated[i].category = .other
                }
                expenses = mutated
                print("Moved \(results.count) expenses from \(categoryName) to Other")
            }
        } catch {
            print("Error moving expenses from deleted category: \(error.localizedDescription)")
        }
    }
    
    /// Cleanup half of custom-category deletion: every expense that
    /// pointed at the deleted category moves to "Other" (as the delete
    /// confirmation promises), and its dangling `customCategoryId` is
    /// cleared. Mirrors the change in-memory so observers update in
    /// one publish without a disk refetch — same pattern as
    /// `moveExpensesFromDeletedCategory` above.
    func moveExpensesFromDeletedCustomCategory(_ id: UUID) {
        let fetchRequest: NSFetchRequest<ExpenseEntity> = ExpenseEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "category == %@ AND customCategoryId == %@",
            Expense.Category.custom.rawValue, id as CVarArg
        )

        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                entity.category = Expense.Category.other.rawValue
                entity.customCategoryId = nil
            }

            if !results.isEmpty {
                saveContext()
                var mutated = expenses
                for i in mutated.indices
                where mutated[i].category == .custom && mutated[i].customCategoryId == id {
                    mutated[i].category = .other
                    mutated[i].customCategoryId = nil
                }
                expenses = mutated
            }
        } catch {
            print("Error moving expenses from deleted custom category: \(error.localizedDescription)")
        }
    }

    /// Cached `[UUID: CustomCategory]` lookup backing the three display
    /// helpers below. PERF: they used to call `getCustomCategories()` —
    /// a full Core Data fetch — **on every call**, i.e. per rendered
    /// row / per digest line. Built lazily, invalidated by the
    /// subscriptions installed in `ExpenseViewModel.init` (and by
    /// `reloadAfterBackupRestore`). Main-thread only, like the helpers.
    func customCategoryLookup() -> [UUID: CustomCategory] {
        if let cached = customCategoriesByIdCache { return cached }
        let map = Dictionary(
            getCustomCategories().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        customCategoriesByIdCache = map
        return map
    }

    func categoryDisplayName(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            return customCategoryLookup()[customCategoryId]?.name ?? "Custom"
        }
        return expense.category.rawValue
    }
    
    func categoryIcon(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            return customCategoryLookup()[customCategoryId]?.icon ?? "tag.fill"
        }
        return expense.category.icon
    }
    
    func categoryColor(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            return customCategoryLookup()[customCategoryId]?.colorName ?? "appPrimary"
        }
        return expense.category.color
    }
}


