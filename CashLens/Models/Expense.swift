import Foundation

struct Expense: Identifiable, Codable {
    var id = UUID()
    var title: String
    var amount: Double
    var currency: Currency
    var date: Date
    var category: Category
    var notes: String?
    var customCategoryId: UUID?
    
    enum Currency: String, CaseIterable, Codable {
        case usd = "USD"
        case eur = "EUR"
        case gbp = "GBP"
        case jpy = "JPY"
        case cad = "CAD"
        case aud = "AUD"
        case inr = "INR"
        case cny = "CNY"
        
        private static let symbols: [Currency: String] = [
            .usd: "$", .eur: "€", .gbp: "£", .jpy: "¥",
            .cad: "C$", .aud: "A$", .inr: "₹", .cny: "¥"
        ]
        
        private static let names: [Currency: String] = [
            .usd: "US Dollar", .eur: "Euro", .gbp: "British Pound", .jpy: "Japanese Yen",
            .cad: "Canadian Dollar", .aud: "Australian Dollar", .inr: "Indian Rupee", .cny: "Chinese Yuan"
        ]
        
        var symbol: String {
            return Currency.symbols[self] ?? "$"
        }
        
        var name: String {
            return Currency.names[self] ?? rawValue
        }
    }
    
    enum Category: String, CaseIterable, Codable {
        case groceries = "Groceries"
        case food = "Food"
        case transportation = "Transportation"
        case entertainment = "Entertainment"
        case shopping = "Shopping"
        case utilities = "Utilities"
        case health = "Health"
        case education = "Education"
        case travel = "Travel"
        case custom = "Custom"
        case other = "Other"
        
        private static let icons: [Category: String] = [
            .groceries: "cart.fill", .food: "fork.knife", .transportation: "car.fill",
            .entertainment: "tv.fill", .shopping: "bag.fill", .utilities: "bolt.fill",
            .health: "heart.fill", .education: "book.fill", .travel: "airplane",
            .custom: "tag.fill", .other: "ellipsis.circle.fill"
        ]
        
        private static let colors: [Category: String] = [
            .groceries: "groceries", .food: "food", .transportation: "transportation",
            .entertainment: "entertainment", .shopping: "shopping", .utilities: "utilities",
            .health: "health", .education: "education", .travel: "travel",
            .custom: "appPrimary", .other: "other"
        ]
        
        var icon: String {
            return Category.icons[self] ?? "questionmark.circle"
        }
        
        var color: String {
            return Category.colors[self] ?? "appPrimary"
        }
    }
}

// Sample data for previews
extension Expense {
    static var sampleData: [Expense] = [
        Expense(title: "Grocery Shopping", amount: 45.67, currency: .usd, date: Date().addingTimeInterval(-86400), category: .food),
        Expense(title: "Movie Tickets", amount: 24.99, currency: .usd, date: Date().addingTimeInterval(-172800), category: .entertainment),
        Expense(title: "Uber Ride", amount: 12.50, currency: .usd, date: Date().addingTimeInterval(-259200), category: .transportation),
        Expense(title: "Coffee", amount: 4.25, currency: .usd, date: Date(), category: .food, notes: "Morning coffee with Sarah"),
        Expense(title: "New Headphones", amount: 89.99, currency: .usd, date: Date().addingTimeInterval(-432000), category: .shopping)
    ]
} 