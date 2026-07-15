import Foundation

struct Subscription: Identifiable, Codable, Equatable {
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

    /// The first occurrence of this subscription's cycle strictly after
    /// `referenceDate`, computed **from the `startDate` anchor** as
    /// startDate + n·frequency (smallest n ≥ 1).
    ///
    /// Anchor-based advancement fixes the drift bug in the old
    /// "add one frequency to the current due date" approach: a monthly
    /// subscription anchored on Jan 31 used to become Feb 28 → Mar 28 →
    /// Apr 28, permanently losing the billing day. Adding n months to
    /// the anchor instead clamps only when the target month is short
    /// (Feb 28/29) and returns to the 31st in longer months.
    static func nextOccurrence(after referenceDate: Date, anchor: Date, frequency: Frequency, calendar: Calendar = .current) -> Date {
        let (component, step): (Calendar.Component, Int) = {
            switch frequency {
            case .daily:     return (.day, 1)
            case .weekly:    return (.weekOfYear, 1)
            case .monthly:   return (.month, 1)
            case .quarterly: return (.month, 3)
            case .yearly:    return (.year, 1)
            }
        }()

        // PERF: Estimate n from elapsed time instead of walking one cycle
        // at a time — a years-old daily subscription would otherwise loop
        // thousands of iterations. Start a couple of cycles early (the
        // day-count intervals are approximations for month/quarter/year)
        // and walk forward to the exact answer.
        let elapsedDays = referenceDate.timeIntervalSince(anchor) / 86_400
        var n = max(1, Int(elapsedDays / Double(frequency.daysInterval)) - 2)

        var candidate = calendar.date(byAdding: component, value: n * step, to: anchor) ?? anchor
        // Safety cap so a pathological calendar result can never spin
        // forever; 1000 extra cycles is far beyond any real drift between
        // the day-count estimate and calendar arithmetic.
        var iterations = 0
        while candidate <= referenceDate && iterations < 1000 {
            n += 1
            iterations += 1
            candidate = calendar.date(byAdding: component, value: n * step, to: anchor) ?? candidate.addingTimeInterval(86_400)
        }
        return candidate
    }
    
    /// Advance to the next due date after a payment. Anchor-based (see
    /// `nextOccurrence`): the result is the first startDate-anchored
    /// occurrence strictly after both the current due date and now, so
    /// paying early advances exactly one cycle and paying an overdue
    /// bill skips straight past all missed cycles to the next future one.
    mutating func updateNextDueDate() {
        let reference = max(Date(), nextDueDate)
        self.nextDueDate = Self.nextOccurrence(after: reference, anchor: startDate, frequency: frequency)
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
    
    // Days until next payment (can be negative for overdue)
    var daysUntilNext: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: nextDueDate)
        return components.day ?? 0
    }
    
    // PERF: Both of these formatters used to be allocated fresh on
    // every property read — and SwiftUI reads them on every body
    // re-render of every row that displays a subscription. Hoisting
    // them to file-private statics removes the per-row allocation and
    // setup cost (which is the dominant cost of NumberFormatter /
    // DateFormatter), making subscription list scrolling appreciably
    // smoother.

    var formattedNextDueDate: String {
        Self.dueDateFormatter.string(from: nextDueDate)
    }

    var formattedAmount: String {
        let formatted = Self.amountFormatter.string(from: NSNumber(value: amount)) ?? "0.00"
        return "\(currency.symbol)\(formatted)"
    }

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
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

// MARK: - Import Extensions
extension Subscription {
    init(from json: [String: Any]) throws {
        guard let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = json["name"] as? String,
              let amount = json["amount"] as? Double,
              let currencyRaw = json["currency"] as? String,
              let currency = Expense.Currency(rawValue: currencyRaw),
              let startDateString = json["startDate"] as? String,
              let startDate = ISO8601DateFormatter().date(from: startDateString),
              let frequencyRaw = json["frequency"] as? String,
              let frequency = Frequency(rawValue: frequencyRaw),
              let nextDueDateString = json["nextDueDate"] as? String,
              let nextDueDate = ISO8601DateFormatter().date(from: nextDueDateString),
              let categoryRaw = json["category"] as? String,
              let category = Expense.Category(rawValue: categoryRaw) else {
            throw ImportError.parseError("Invalid subscription data")
        }
        
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.startDate = startDate
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.category = category
        self.notes = json["notes"] as? String
        
        // Safety check for NaN or invalid amounts
        guard amount.isFinite && amount >= 0 else {
            throw ImportError.parseError("Invalid subscription amount in JSON: \(amount). Amount must be a positive finite number.")
        }
        
        if let customCategoryIdString = json["customCategoryId"] as? String {
            self.customCategoryId = UUID(uuidString: customCategoryIdString)
        }
        
        self.isActive = json["isActive"] as? Bool ?? true
        self.reminderEnabled = json["reminderEnabled"] as? Bool ?? true
        self.reminderDaysBefore = json["reminderDaysBefore"] as? Int ?? 1
    }
    
    init(fromCSV line: String) throws {
        let fields = parseCSVFields(line)
        guard fields.count >= 13 else {
            throw ImportError.parseError("Invalid CSV subscription format: expected 13 fields, got \(fields.count)")
        }
        
        // Helper function to parse dates with multiple formats.
        //
        // Order matters: the app's own exports (ISO 8601) must re-import
        // on ANY device locale, so machine formats are tried first with a
        // fixed `en_US_POSIX` locale — a style-based formatter in, say,
        // an fr_FR locale would silently fail on "Jan 5, 2025" and a
        // fixed-format parse without POSIX can be corrupted by 12/24-hour
        // user overrides. The locale-aware style attempts stay last for
        // human-edited files.
        func parseDate(_ dateString: String) -> Date? {
            // 1. ISO 8601 — what the app's JSON/CSV exports write.
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: dateString) {
                return date
            }
            
            // 2. Fixed formats, locale-pinned so they parse identically
            //    on every device.
            let posixFormatter = DateFormatter()
            posixFormatter.locale = Locale(identifier: "en_US_POSIX")
            let formats = ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "MMM d, yyyy", "yyyy-MM-dd", "MM/dd/yyyy"]
            for format in formats {
                posixFormatter.dateFormat = format
                if let date = posixFormatter.date(from: dateString) {
                    return date
                }
            }
            
            // 3. Locale-aware styles for files written/edited by hand in
            //    the user's own locale (matches legacy in-locale exports).
            let styleFormatter = DateFormatter()
            styleFormatter.dateStyle = .medium
            if let date = styleFormatter.date(from: dateString) {
                return date
            }
            styleFormatter.dateStyle = .short
            if let date = styleFormatter.date(from: dateString) {
                return date
            }
            
            return nil
        }
        
        guard let id = UUID(uuidString: parseCSVField(fields[0])),
              let amount = Double(parseCSVField(fields[2])),
              let currency = Expense.Currency(rawValue: parseCSVField(fields[3])),
              let startDate = parseDate(parseCSVField(fields[4])),
              let frequency = Frequency(rawValue: parseCSVField(fields[5])),
              let nextDueDate = parseDate(parseCSVField(fields[6])),
              let category = Expense.Category(rawValue: parseCSVField(fields[7])) else {
            throw ImportError.parseError("Invalid CSV subscription data: id='\(parseCSVField(fields[0]))', amount='\(parseCSVField(fields[2]))', currency='\(parseCSVField(fields[3]))', startDate='\(parseCSVField(fields[4]))', frequency='\(parseCSVField(fields[5]))', nextDueDate='\(parseCSVField(fields[6]))', category='\(parseCSVField(fields[7]))'")
        }
        
        // Safety check for NaN or invalid amounts
        guard amount.isFinite && amount >= 0 else {
            throw ImportError.parseError("Invalid subscription amount: \(amount). Amount must be a positive finite number.")
        }
        
        self.id = id
        self.name = parseCSVField(fields[1])
        self.amount = amount
        self.currency = currency
        self.startDate = startDate
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.category = category
        
        let customCategoryIdString = parseCSVField(fields[8])
        if !customCategoryIdString.isEmpty {
            self.customCategoryId = UUID(uuidString: customCategoryIdString)
        }
        
        let notes = parseCSVField(fields[9])
        self.notes = notes.isEmpty ? nil : notes
        
        self.isActive = parseCSVField(fields[10]).lowercased() == "true"
        self.reminderEnabled = parseCSVField(fields[11]).lowercased() == "true"
        self.reminderDaysBefore = Int(parseCSVField(fields[12])) ?? 1
    }
} 