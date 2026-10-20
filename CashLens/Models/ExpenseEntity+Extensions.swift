import Foundation
import CoreData

extension ExpenseEntity {
    // Convert from Expense struct to ExpenseEntity
    static func fromExpense(_ expense: Expense, context: NSManagedObjectContext) -> ExpenseEntity {
        let entity = ExpenseEntity(context: context)
        entity.id = expense.id
        entity.title = expense.title
        entity.amount = expense.amount
        entity.currency = expense.currency.rawValue
        entity.date = expense.date
        entity.category = expense.category.rawValue
        entity.notes = expense.notes
        entity.customCategoryId = expense.customCategoryId
        entity.isFromSubscription = expense.isFromSubscription
        entity.subscriptionId = expense.subscriptionId
        entity.isRefund = expense.isRefund
        // Persist as the canonical raw value (`"credit"`, `"upi"`, …). `nil`
        // means "not specified" — never a default like `.cash`, because that
        // would invent data the user didn't enter.
        entity.paymentMethod = expense.paymentMethod?.rawValue
        // Round-trip the receipt filename — never the absolute path. See
        // `Expense.receiptImagePath` doc for why; `ReceiptStorage` resolves
        // the actual URL from this filename at read time.
        entity.receiptImagePath = expense.receiptImagePath
        if let tagList = expense.tags, !tagList.isEmpty {
            entity.tags = tagList as NSArray
        } else {
            entity.tags = nil
        }
        return entity
    }

    // Convert to Expense struct
    func toExpense() -> Expense {
        return Expense(
            id: self.id ?? UUID(),
            title: self.title ?? "",
            amount: self.amount,
            currency: Expense.Currency(rawValue: self.currency ?? "USD") ?? .usd,
            date: self.date ?? Date(),
            category: Expense.Category(rawValue: self.category ?? "Other") ?? .other,
            notes: self.notes,
            customCategoryId: self.customCategoryId,
            isFromSubscription: self.isFromSubscription,
            subscriptionId: self.subscriptionId,
            tags: decodedTags(),
            isRefund: self.isRefund,
            paymentMethod: PaymentMethod.tolerant(from: self.paymentMethod),
            receiptImagePath: self.receiptImagePath
        )
    }

    /// The `tags` attribute is a Transformable `NSArray`. Extract a clean `[String]?`
    /// from whatever representation Core Data hands back (NSArray of NSStrings or a
    /// Swift `[String]`), dropping anything empty.
    private func decodedTags() -> [String]? {
        guard let stored = self.tags else { return nil }
        // Core Data declares the attribute as `NSArray?` (customClassName).
        // Elements may be `String` or `NSString` depending on how they were encoded.
        let rawStrings: [String] = stored.compactMap { element in
            (element as? String) ?? (element as? NSString) as String?
        }
        let cleaned = rawStrings.compactMap { Tag.normalize($0) }
        return cleaned.isEmpty ? nil : cleaned
    }
}

// Extension for fetching and sorting expenses
extension Collection where Element == ExpenseEntity {
    func toExpenses() -> [Expense] {
        return self.map { $0.toExpense() }
    }
}
