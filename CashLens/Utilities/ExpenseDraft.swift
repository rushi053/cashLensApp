import Foundation

struct ExpenseDraft: Codable {
    let title: String
    let amount: String
    let date: Date
    let selectedCategory: Expense.Category
    let selectedCustomCategoryId: UUID?
    let notes: String
    /// Tags captured on the in-progress draft. Optional for backward-compatible
    /// decoding of drafts saved before tags shipped.
    let tags: [String]?
    /// Refund flag captured on the draft. Optional so drafts saved before
    /// the refund feature shipped still decode cleanly (defaulting to nil
    /// → treated as `false` in `AddExpenseView`).
    let isRefund: Bool?
    /// Payment method on the in-progress draft. Optional/Optional so old
    /// drafts (no key) AND unset drafts (key present, nil) both decode
    /// cleanly. We persist as raw String so an enum-rename later doesn't
    /// invalidate stored drafts — `tolerant(from:)` keeps it forward-safe.
    let paymentMethod: String?
    let timestamp: Date

    init(
        title: String,
        amount: String,
        date: Date,
        selectedCategory: Expense.Category,
        selectedCustomCategoryId: UUID?,
        notes: String,
        tags: [String] = [],
        isRefund: Bool = false,
        paymentMethod: PaymentMethod? = nil
    ) {
        self.title = title
        self.amount = amount
        self.date = date
        self.selectedCategory = selectedCategory
        self.selectedCustomCategoryId = selectedCustomCategoryId
        self.notes = notes
        self.tags = tags.isEmpty ? nil : tags
        self.isRefund = isRefund ? true : nil
        self.paymentMethod = paymentMethod?.rawValue
        self.timestamp = Date()
    }

    /// Convenience: read the stored raw string back through the tolerant
    /// decoder so a forgotten/typo-ed value is treated as `nil` rather than
    /// crashing the form on first launch.
    var resolvedPaymentMethod: PaymentMethod? {
        PaymentMethod.tolerant(from: paymentMethod)
    }
}
