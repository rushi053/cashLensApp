//
//  Persistence.swift
//  CashLens
//
//  Created by Rushiraj Jadeja on 10/03/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create some sample expenses for preview
        let sampleExpense = ExpenseEntity(context: viewContext)
        sampleExpense.id = UUID()
        sampleExpense.title = "Sample Expense"
        sampleExpense.amount = 49.99
        sampleExpense.currency = "USD"
        sampleExpense.date = Date()
        sampleExpense.category = "Food"
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Error creating preview data: \(nsError), \(nsError.userInfo)")
        }
        
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "CashLens")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Optimize SQLite store with pragmas for better performance
            let description = container.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Add SQLite pragmas for performance optimization
            let pragmas: [String: String] = [
                "journal_mode": "WAL",       // Use Write-Ahead Logging
                "synchronous": "NORMAL"      // Less synchronization (still safe for most cases)
            ]
            description?.setOption(pragmas as NSDictionary, forKey: NSSQLitePragmasOption)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Log the error with more detailed information for debugging
                fatalError("Persistent store failed to load: \(error), \(error.userInfo)")
            }
        })
        
        // Configure container settings for better performance
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Optimize fetch performance
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
    }
}
