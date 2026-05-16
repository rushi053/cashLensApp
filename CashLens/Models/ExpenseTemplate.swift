import Foundation

/// User-saved preset for fast, repeated expense entry — e.g. "Morning coffee · $4 · Food".
///
/// Templates only capture the *prefilled* fields. They never carry a date —
/// the current date is always used when applying — and they never hold draft
/// state. They are intentionally lightweight so we can store the whole
/// collection in `UserDefaults` (no Core Data migration needed) and still
/// keep loads/saves cheap on the main thread.
///
/// Backward compatibility: `tags` and `isRefund` are decoded with
/// `decodeIfPresent` so older serialized templates that pre-date those
/// fields continue to load cleanly.
struct ExpenseTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    /// User-visible name of the template. Defaults to `title` when the user
    /// didn't supply a custom name; trimmed and capped on save.
    var name: String
    /// Default expense title applied to the form. Can be empty when the user
    /// only wants to lock category + amount.
    var title: String
    /// Default amount in the user's selected currency. Stored as `Double` and
    /// rendered through `viewModel.formattedAmount` at apply time.
    var amount: Double
    var category: Expense.Category
    /// Set when the template targets a custom category.
    var customCategoryId: UUID?
    var notes: String?
    var tags: [String]?
    var isRefund: Bool
    /// Optional default payment method baked into the template. `nil` means
    /// "leave whatever's currently selected on the form" — the same
    /// additive-fill rule we use for tags and notes.
    var paymentMethod: PaymentMethod?
    /// Timestamp of the most recent application — used to sort the chip strip
    /// "most recently used first" so frequent presets stay at the top.
    var lastUsedAt: Date?
    /// Creation timestamp — fallback sort key when a template has never been
    /// applied yet (`lastUsedAt == nil`).
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        title: String,
        amount: Double,
        category: Expense.Category,
        customCategoryId: UUID? = nil,
        notes: String? = nil,
        tags: [String]? = nil,
        isRefund: Bool = false,
        paymentMethod: PaymentMethod? = nil,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.amount = amount
        self.category = category
        self.customCategoryId = customCategoryId
        self.notes = notes
        self.tags = tags
        self.isRefund = isRefund
        self.paymentMethod = paymentMethod
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, amount, category, customCategoryId, notes, tags, isRefund, paymentMethod, lastUsedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.title = try c.decode(String.self, forKey: .title)
        self.amount = try c.decode(Double.self, forKey: .amount)
        self.category = try c.decode(Expense.Category.self, forKey: .category)
        self.customCategoryId = try c.decodeIfPresent(UUID.self, forKey: .customCategoryId)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags)
        self.isRefund = try c.decodeIfPresent(Bool.self, forKey: .isRefund) ?? false
        // Decoded through `tolerant(from:)` so a stale rawValue from a
        // future build never throws and breaks the whole template list.
        let pmRaw = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
        self.paymentMethod = PaymentMethod.tolerant(from: pmRaw)
        self.lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Display label for chips: "☕ Coffee · $4" style. Built by the view
    /// layer — kept off the model so locale formatting (currency) stays in
    /// the view's hands.
    var trimmedName: String {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? title : s
    }
}
