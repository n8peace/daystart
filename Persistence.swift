import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Add sample data for previews
        let newItem = Item(context: viewContext)
        newItem.timestamp = Date()

        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate.
            // You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DayStart")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure persistent store descriptions
        container.persistentStoreDescriptions.forEach { storeDescription in
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        // Set up automatic merging
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Save Context
    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
                DebugLogger.shared.log("Core Data context saved successfully", level: .info)
            } catch {
                DebugLogger.shared.logError(error, context: "Core Data save failed")
                
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // MARK: - Background Context Operations
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) -> T) async -> T {
        return await withCheckedContinuation { continuation in
            container.performBackgroundTask { context in
                let result = block(context)
                continuation.resume(returning: result)
            }
        }
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - Helper Methods
    func deleteAllData() {
        let context = container.viewContext
        
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Item.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
            DebugLogger.shared.log("All Core Data deleted", level: .info)
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to delete all Core Data")
        }
    }
    
    // MARK: - Migration Support
    func migrateStoreIfNeeded() {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            return
        }
        
        do {
            let sourceMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
            
            let destinationModel = container.managedObjectModel
            
            if !destinationModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: sourceMetadata) {
                DebugLogger.shared.log("Core Data store requires migration", level: .info)
                // Migration would be handled here in a production app
            }
        } catch {
            DebugLogger.shared.logError(error, context: "Core Data migration check failed")
        }
    }
}

// MARK: - Core Data Extensions
extension NSManagedObjectContext {
    func saveIfNeeded() {
        if hasChanges {
            do {
                try save()
            } catch {
                DebugLogger.shared.logError(error, context: "NSManagedObjectContext save failed")
            }
        }
    }
}

// MARK: - Fetch Request Helpers
extension Item {
    static func fetchRequest() -> NSFetchRequest<Item> {
        return NSFetchRequest<Item>(entityName: "Item")
    }
    
    static func all() -> NSFetchRequest<Item> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)]
        return request
    }
    
    static func recent(limit: Int = 10) -> NSFetchRequest<Item> {
        let request = all()
        request.fetchLimit = limit
        return request
    }
}

// MARK: - Preview Helpers
#if DEBUG
extension PersistenceController {
    static var empty: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
    
    static var populated: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        
        // Add multiple sample items
        for i in 0..<5 {
            let item = Item(context: context)
            item.timestamp = Date().addingTimeInterval(TimeInterval(-i * 3600)) // Each item 1 hour apart
        }
        
        try? context.save()
        return controller
    }()
}
#endif