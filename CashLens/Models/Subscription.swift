import Foundation

struct Subscription: Identifiable, Codable {
    var id = UUID()
    var name: String
    var amount: Double
    var currency: Expense.Currency
    var startDate: Date
    var frequency: Frequency
    var nextDueDate: Date
    var category: Expense.Category
    var customCategoryId: UUID?
    var notes: String?
    var isActive: Bool = true
    var reminderEnabled: Bool = true
    var reminderDaysBefore: Int = 1
    
    enum Frequency: String, CaseIterable, Codable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case yearly = "Yearly"
        
        var icon: String {
            switch self {
            case .daily: return "sun.max.fill"
            case .weekly: return "calendar.badge.clock"
            case .monthly: return "calendar"
            case .quarterly: return "calendar.circle"
            case .yearly: return "calendar.badge.plus"
            }
        }
        
        var description: String {
            switch self {
            case .daily: return "Every day"
            case .weekly: return "Every week"
            case .monthly: return "Every month"
            case .quarterly: return "Every 3 months"
            case .yearly: return "Every year"
            }
        }
        
        var daysInterval: Int {
            switch self {
            case .daily: return 1
            case .weekly: return 7
            case .monthly: return 30 // Approximate, will use Calendar for exact calculation
            case .quarterly: return 90 // Approximate, will use Calendar for exact calculation
            case .yearly: return 365 // Approximate, will use Calendar for exact calculation
            }
        }
    }
    
    init(name: String, amount: Double, currency: Expense.Currency, startDate: Date, frequency: Frequency, category: Expense.Category, customCategoryId: UUID? = nil, notes: String? = nil) {
        self.name = name
        self.amount = amount
        self.currency = currency
        self.startDate = startDate
        self.frequency = frequency
        self.category = category
        self.customCategoryId = customCategoryId
        self.notes = notes
        self.nextDueDate = Self.calculateNextDueDate(from: startDate, frequency: frequency)
    }
    
    // Calculate the next due date based on frequency
    static func calculateNextDueDate(from date: Date, frequency: Frequency) -> Date {
        let calendar = Calendar.current
        
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
    
    // Update next due date after creating an expense
    mutating func updateNextDueDate() {
        self.nextDueDate = Self.calculateNextDueDate(from: self.nextDueDate, frequency: self.frequency)
    }
    
    // Check if the subscription is due
    var isDue: Bool {
        return Date() >= nextDueDate && isActive
    }
    
    // Check if reminder should be sent
    var shouldSendReminder: Bool {
        guard reminderEnabled && isActive else { return false }
        let calendar = Calendar.current
        let reminderDate = calendar.date(byAdding: .day, value: -reminderDaysBefore, to: nextDueDate) ?? nextDueDate
        return Date() >= reminderDate && Date() < nextDueDate
    }
    
    // Convert to Expense when due
    func toExpense() -> Expense {
        return Expense(
            title: name,
            amount: amount,
            currency: currency,
            date: Date(), // Use current date when creating the expense
            category: category,
            notes: notes,
            customCategoryId: customCategoryId
        )
    }
    
    // Days until next payment
    var daysUntilNext: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: nextDueDate)
        return max(0, components.day ?? 0)
    }
    
    // Formatted next due date
    var formattedNextDueDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: nextDueDate)
    }
    
    // Formatted amount with currency
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "0.00"
        return "\(currency.symbol)\(formatted)"
    }
}

// Sample data for previews
extension Subscription {
    static var sampleData: [Subscription] = [
        Subscription(
            name: "Netflix",
            amount: 15.99,
            currency: .usd,
            startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            frequency: .monthly,
            category: .entertainment,
            notes: "Family plan"
        ),
        Subscription(
            name: "Spotify Premium",
            amount: 9.99,
            currency: .usd,
            startDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(),
            frequency: .monthly,
            category: .entertainment
        ),
        Subscription(
            name: "iCloud Storage",
            amount: 2.99,
            currency: .usd,
            startDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
            frequency: .monthly,
            category: .utilities,
            notes: "200GB plan"
        ),
        Subscription(
            name: "Gym Membership",
            amount: 45.00,
            currency: .usd,
            startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            frequency: .monthly,
            category: .health
        )
    ]
} 