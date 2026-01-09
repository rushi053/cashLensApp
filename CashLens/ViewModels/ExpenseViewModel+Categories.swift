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
                loadExpenses()
                print("Moved \(results.count) expenses from \(categoryName) to Other")
            }
        } catch {
            print("Error moving expenses from deleted category: \(error.localizedDescription)")
        }
    }
    
    func categoryDisplayName(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            let customCategories = getCustomCategories()
            if let category = customCategories.first(where: { $0.id == customCategoryId }) {
                return category.name
            }
            return "Custom"
        }
        return expense.category.rawValue
    }
    
    func categoryIcon(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            let customCategories = getCustomCategories()
            if let category = customCategories.first(where: { $0.id == customCategoryId }) {
                return category.icon
            }
            return "tag.fill"
        }
        return expense.category.icon
    }
    
    func categoryColor(for expense: Expense) -> String {
        if expense.category == .custom, let customCategoryId = expense.customCategoryId {
            let customCategories = getCustomCategories()
            if let category = customCategories.first(where: { $0.id == customCategoryId }) {
                return category.colorName
            }
            return "appPrimary"
        }
        return expense.category.color
    }
}


