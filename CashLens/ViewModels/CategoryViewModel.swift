import Foundation
import SwiftUI
import CoreData
import Combine

class CategoryViewModel: ObservableObject {
    @Published var customCategories: [CustomCategory] = []
    private var hasLoadedInitialData = false
    
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        
        // Load custom categories on init
        loadCustomCategories()
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
    
    // Load custom categories from CoreData
    func loadCustomCategories() {
        // Skip repeated loads if data is already loaded
        // But allow reloading if necessary by specific calls
        let fetchRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CustomCategoryEntity.name, ascending: true)]
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            self.customCategories = results.toCustomCategories()
            self.hasLoadedInitialData = true
            // Removed noisy print statement
        } catch {
            print("Error loading custom categories: \(error.localizedDescription)")
            self.customCategories = []
        }
    }
    
    // Add a new custom category
    func addCustomCategory(_ category: CustomCategory) {
        // Save to CoreData
        _ = CustomCategoryEntity.fromCustomCategory(category, context: viewContext)
        saveContext()
        
        // Update the categories array
        loadCustomCategories()
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
        
        // Update the categories array
        loadCustomCategories()
    }
    
    // Delete a custom category
    func deleteCustomCategory(id: UUID) {
        let fetchRequest: NSFetchRequest<CustomCategoryEntity> = CustomCategoryEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            for entity in results {
                viewContext.delete(entity)
            }
            saveContext()
        } catch {
            print("Error deleting custom category: \(error.localizedDescription)")
        }
        
        // Update the categories array
        loadCustomCategories()
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
                // Removed noisy print statement
            } catch {
                print("Error saving context: \(error.localizedDescription)")
            }
        }
    }
} 