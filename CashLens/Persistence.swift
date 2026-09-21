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

    /// Set when `loadPersistentStores` fails (e.g. a model-version hash
    /// mismatch after a bad update, or store corruption). The store files
    /// on disk are NEVER deleted — `CashLensApp` observes this and shows
    /// `StoreRecoveryView` instead of the normal UI, which offers a raw
    /// export of the store files so the user's data is always retrievable.
    /// Populated synchronously during `init` (the default store load is
    /// synchronous), so it's safe to read immediately after construction.
    private(set) var storeLoadError: NSError?

    var storeLoadFailed: Bool { storeLoadError != nil }

    /// The on-disk files backing the SQLite store that currently exist:
    /// the main `.sqlite` plus its `-wal` / `-shm` sidecars. Used by the
    /// recovery flow's "export my data" share sheet. Empty for in-memory
    /// stores or if the store URL is unknown.
    var storeFileURLs: [URL] {
        guard let storeURL = container.persistentStoreDescriptions.first?.url,
              storeURL.isFileURL, storeURL.path != "/dev/null" else { return [] }
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

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

            // Lightweight migration. These are the framework defaults, but
            // they're spelled out because they are load-bearing: the model
            // is now versioned (CashLens → CashLens 2) and every future
            // schema change must migrate 3k+ production stores in place.
            description?.shouldMigrateStoreAutomatically = true
            description?.shouldInferMappingModelAutomatically = true
        }
        
        var loadError: NSError?
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // NEVER crash and NEVER delete the store here. The user's
                // financial history is irreplaceable; a load failure flips
                // `storeLoadError` and the app presents a recovery screen
                // that keeps the data exportable.
                print("Persistent store failed to load: \(error), \(error.userInfo)")
                loadError = error
            }
        })
        storeLoadError = loadError
        
        // Configure container settings for better performance
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Optimize fetch performance
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
    }
}
