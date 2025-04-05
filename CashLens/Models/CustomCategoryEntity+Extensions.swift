import Foundation
import CoreData

extension CustomCategoryEntity {
    // Convert from CustomCategory struct to CustomCategoryEntity
    static func fromCustomCategory(_ category: CustomCategory, context: NSManagedObjectContext) -> CustomCategoryEntity {
        let entity = CustomCategoryEntity(context: context)
        entity.id = category.id
        entity.name = category.name
        entity.icon = category.icon
        entity.colorName = category.colorName
        return entity
    }
    
    // Convert to CustomCategory struct
    func toCustomCategory() -> CustomCategory {
        return CustomCategory(
            id: self.id ?? UUID(),
            name: self.name ?? "",
            icon: self.icon ?? "tag.fill",
            colorName: self.colorName ?? "appPrimary"
        )
    }
}

// Extension for fetching and sorting custom categories
extension Collection where Element == CustomCategoryEntity {
    func toCustomCategories() -> [CustomCategory] {
        return self.map { $0.toCustomCategory() }
    }
} 