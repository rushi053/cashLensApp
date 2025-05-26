import Foundation
import CoreData

extension SubscriptionEntity {
    
    // Convert Core Data entity to Subscription struct
    func toSubscription() -> Subscription {
        var subscription = Subscription(
            name: self.name ?? "",
            amount: self.amount,
            currency: Expense.Currency(rawValue: self.currency ?? "USD") ?? .usd,
            startDate: self.startDate ?? Date(),
            frequency: Subscription.Frequency(rawValue: self.frequency ?? "Monthly") ?? .monthly,
            category: Expense.Category(rawValue: self.category ?? "Other") ?? .other,
            customCategoryId: self.customCategoryId,
            notes: self.notes
        )
        
        subscription.id = self.id ?? UUID()
        subscription.nextDueDate = self.nextDueDate ?? Date()
        subscription.isActive = self.isActive
        subscription.reminderEnabled = self.reminderEnabled
        subscription.reminderDaysBefore = Int(self.reminderDaysBefore)
        
        return subscription
    }
    
    // Create Core Data entity from Subscription struct
    static func fromSubscription(_ subscription: Subscription, context: NSManagedObjectContext) -> SubscriptionEntity {
        let entity = SubscriptionEntity(context: context)
        
        entity.id = subscription.id
        entity.name = subscription.name
        entity.amount = subscription.amount
        entity.currency = subscription.currency.rawValue
        entity.startDate = subscription.startDate
        entity.frequency = subscription.frequency.rawValue
        entity.nextDueDate = subscription.nextDueDate
        entity.category = subscription.category.rawValue
        entity.customCategoryId = subscription.customCategoryId
        entity.notes = subscription.notes
        entity.isActive = subscription.isActive
        entity.reminderEnabled = subscription.reminderEnabled
        entity.reminderDaysBefore = Int16(subscription.reminderDaysBefore)
        
        return entity
    }
    
    // Update existing entity with Subscription data
    func updateFromSubscription(_ subscription: Subscription) {
        self.name = subscription.name
        self.amount = subscription.amount
        self.currency = subscription.currency.rawValue
        self.startDate = subscription.startDate
        self.frequency = subscription.frequency.rawValue
        self.nextDueDate = subscription.nextDueDate
        self.category = subscription.category.rawValue
        self.customCategoryId = subscription.customCategoryId
        self.notes = subscription.notes
        self.isActive = subscription.isActive
        self.reminderEnabled = subscription.reminderEnabled
        self.reminderDaysBefore = Int16(subscription.reminderDaysBefore)
    }
} 