import Foundation
import SwiftUI

// MARK: - Transaction Source
enum TransactionSource: String, Codable, CaseIterable {
    case applePay = "Apple Pay"
    case upi = "UPI"
    case manual = "Manual"
    
    var icon: String {
        switch self {
        case .applePay: return "creditcard.fill"
        case .upi: return "indianrupeesign.circle.fill"
        case .manual: return "hand.tap.fill"
        }
    }
    
    var color: String {
        switch self {
        case .applePay: return "blue"
        case .upi: return "green"
        case .manual: return "orange"
        }
    }
}

// MARK: - Transaction Automation Data Model
struct AutomatedTransaction: Identifiable, Codable {
    var id = UUID()
    var amount: Double
    var merchant: String
    var paymentMethod: String
    var date: Date
    var isProcessed: Bool = false
    var suggestedCategory: Expense.Category = .other
    var notes: String?
    var source: TransactionSource = .applePay
    var upiReference: String?
    var bankName: String?
    var accountLastFour: String?
    
    // Convert to Expense for processing
    func toExpense(with currency: Expense.Currency, category: Expense.Category? = nil, title: String? = nil) -> Expense {
        let finalNotes = buildNotesString()
        
        return Expense(
            title: title ?? merchant,
            amount: amount,
            currency: currency,
            date: date,
            category: category ?? suggestedCategory,
            notes: finalNotes
        )
    }
    
    private func buildNotesString() -> String {
        var notesArray: [String] = []
        
        if let notes = notes, !notes.isEmpty {
            notesArray.append(notes)
        }
        
        // Add source-specific details
        switch source {
        case .upi:
            if let upiRef = upiReference {
                notesArray.append("UPI Ref: \(upiRef)")
            }
            if let bank = bankName {
                notesArray.append("Bank: \(bank)")
            }
            if let account = accountLastFour {
                notesArray.append("A/c: ****\(account)")
            }
        case .applePay:
            notesArray.append("Apple Pay")
        case .manual:
            break
        }
        
        return notesArray.joined(separator: " • ")
    }
    
    // Smart category suggestion based on merchant name
    mutating func suggestCategory() {
        let merchantLower = merchant.lowercased()
        
        // Food & Restaurants
        if merchantLower.contains("restaurant") || merchantLower.contains("cafe") || 
           merchantLower.contains("coffee") || merchantLower.contains("pizza") ||
           merchantLower.contains("mcdonald") || merchantLower.contains("starbucks") ||
           merchantLower.contains("food") || merchantLower.contains("dining") ||
           merchantLower.contains("zomato") || merchantLower.contains("swiggy") ||
           merchantLower.contains("dunzo") || merchantLower.contains("dominos") {
            suggestedCategory = .food
        }
        // Groceries
        else if merchantLower.contains("grocery") || merchantLower.contains("market") ||
                merchantLower.contains("walmart") || merchantLower.contains("target") ||
                merchantLower.contains("supermarket") || merchantLower.contains("costco") ||
                merchantLower.contains("bigbasket") || merchantLower.contains("grofers") ||
                merchantLower.contains("reliance") || merchantLower.contains("dmart") ||
                merchantLower.contains("spencer") || merchantLower.contains("more") {
            suggestedCategory = .groceries
        }
        // Transportation
        else if merchantLower.contains("gas") || merchantLower.contains("fuel") ||
                merchantLower.contains("uber") || merchantLower.contains("lyft") ||
                merchantLower.contains("taxi") || merchantLower.contains("metro") ||
                merchantLower.contains("parking") || merchantLower.contains("ola") ||
                merchantLower.contains("rapido") || merchantLower.contains("namma yatri") ||
                merchantLower.contains("petrol") || merchantLower.contains("diesel") ||
                merchantLower.contains("indian oil") || merchantLower.contains("bharat petroleum") ||
                merchantLower.contains("hindustan petroleum") {
            suggestedCategory = .transportation
        }
        // Shopping
        else if merchantLower.contains("amazon") || merchantLower.contains("store") ||
                merchantLower.contains("shop") || merchantLower.contains("mall") ||
                merchantLower.contains("retail") || merchantLower.contains("flipkart") ||
                merchantLower.contains("myntra") || merchantLower.contains("nykaa") ||
                merchantLower.contains("ajio") || merchantLower.contains("meesho") {
            suggestedCategory = .shopping
        }
        // Entertainment
        else if merchantLower.contains("cinema") || merchantLower.contains("movie") ||
                merchantLower.contains("theater") || merchantLower.contains("game") ||
                merchantLower.contains("entertainment") || merchantLower.contains("bookmyshow") ||
                merchantLower.contains("netflix") || merchantLower.contains("spotify") ||
                merchantLower.contains("hotstar") || merchantLower.contains("prime video") {
            suggestedCategory = .entertainment
        }
        // Health
        else if merchantLower.contains("pharmacy") || merchantLower.contains("doctor") ||
                merchantLower.contains("hospital") || merchantLower.contains("clinic") ||
                merchantLower.contains("health") || merchantLower.contains("medical") ||
                merchantLower.contains("apollo") || merchantLower.contains("practo") ||
                merchantLower.contains("1mg") || merchantLower.contains("netmeds") {
            suggestedCategory = .health
        }
        // Utilities
        else if merchantLower.contains("electric") || merchantLower.contains("utility") ||
                merchantLower.contains("phone") || merchantLower.contains("internet") ||
                merchantLower.contains("water") || merchantLower.contains("gas company") ||
                merchantLower.contains("airtel") || merchantLower.contains("jio") ||
                merchantLower.contains("vodafone") || merchantLower.contains("bsnl") ||
                merchantLower.contains("electricity") || merchantLower.contains("broadband") {
            suggestedCategory = .utilities
        }
        else {
            suggestedCategory = .other
        }
    }
}

// MARK: - UPI SMS Parser
struct UPISMSParser {
    
    // Improved UPI SMS patterns for Indian banks and UPI apps
    static let patterns: [UPISMSPattern] = [
        // PhonePe - Multiple variants
        UPISMSPattern(
            regex: #"(?:Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+(?:paid|debited|sent)\s+to\s+([^,\n\r]+?)(?:\s+via\s+PhonePe)?(?:.*?(?:UPI\s+)?Ref[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "PhonePe",
            accountGroup: nil
        ),
        
        // Google Pay - Multiple variants
        UPISMSPattern(
            regex: #"(?:₹|Rs\.?)\s*(\d+(?:\.\d{2})?)\s+(?:paid|sent|debited)\s+to\s+([^,\n\r]+?)(?:\s+via\s+(?:Google\s*Pay|GPay))?(?:.*?(?:UPI\s+)?(?:ID|Ref)[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "Google Pay",
            accountGroup: nil
        ),
        
        // Paytm - Multiple variants
        UPISMSPattern(
            regex: #"(?:Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+(?:paid|debited|sent)(?:\s+from.*?)?\s+to\s+([^,\n\r]+?)(?:\s+via\s+Paytm)?(?:.*?(?:UPI\s+)?(?:Ref|ID)[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "Paytm",
            accountGroup: nil
        ),
        
        // SBI UPI - Multiple variants
        UPISMSPattern(
            regex: #"(?:Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+debited\s+from\s+SBI\s+(?:A/c|Account)\s+\*+(\d{4})\s+to\s+([^,\n\r]+?)(?:.*?(?:UPI\s+)?Ref[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 3,
            referenceGroup: 4,
            bankName: "SBI",
            accountGroup: 2
        ),
        
        // HDFC UPI - Multiple variants
        UPISMSPattern(
            regex: #"(?:INR|Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+debited\s+from\s+HDFC\s+Bank\s+(?:A/c|Account)\s+\*+(\d{4})\s+to\s+([^,\n\r]+?)(?:.*?(?:UPI\s+)?Ref[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 3,
            referenceGroup: 4,
            bankName: "HDFC Bank",
            accountGroup: 2
        ),
        
        // ICICI UPI - Multiple variants
        UPISMSPattern(
            regex: #"(?:Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+debited\s+from\s+ICICI\s+Bank\s+(?:A/c|Account)\s+\*+(\d{4})\s+to\s+([^,\n\r]+?)(?:.*?(?:UPI\s+)?Ref[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 3,
            referenceGroup: 4,
            bankName: "ICICI Bank",
            accountGroup: 2
        ),
        
        // Axis Bank UPI
        UPISMSPattern(
            regex: #"(?:Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+debited\s+from\s+Axis\s+Bank\s+(?:A/c|Account)\s+\*+(\d{4})\s+to\s+([^,\n\r]+?)(?:.*?(?:UPI\s+)?Ref[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 3,
            referenceGroup: 4,
            bankName: "Axis Bank",
            accountGroup: 2
        ),
        
        // Kotak UPI
        UPISMSPattern(
            regex: #"(?:Rs\.?|₹)\s*(\d+(?:\.\d{2})?)\s+debited\s+from\s+Kotak\s+(?:A/c|Account)\s+\*+(\d{4})\s+to\s+([^,\n\r]+?)(?:.*?(?:UPI\s+)?Ref[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 3,
            referenceGroup: 4,
            bankName: "Kotak Bank",
            accountGroup: 2
        ),
        
        // CRED
        UPISMSPattern(
            regex: #"(?:₹|Rs\.?)\s*(\d+(?:\.\d{2})?)\s+(?:paid|sent)\s+to\s+([^,\n\r]+?)(?:\s+via\s+CRED)?(?:.*?(?:UPI\s+)?(?:ID|Ref)[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "CRED",
            accountGroup: nil
        ),
        
        // Amazon Pay
        UPISMSPattern(
            regex: #"(?:₹|Rs\.?)\s*(\d+(?:\.\d{2})?)\s+(?:paid|sent|debited)\s+to\s+([^,\n\r]+?)(?:\s+via\s+Amazon\s*Pay)?(?:.*?(?:UPI\s+)?(?:ID|Ref)[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "Amazon Pay",
            accountGroup: nil
        ),
        
        // Generic UPI pattern - more flexible
        UPISMSPattern(
            regex: #"(?:Rs\.?|INR|₹)\s*(\d+(?:\.\d{2})?)\s+(?:paid|debited|sent|transferred)(?:\s+from.*?)?\s+(?:to|via)\s+([^,\n\r]+?)(?:.*?(?:UPI\s+)?(?:Ref|ID|Reference)[:\s#]+(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "UPI",
            accountGroup: nil
        ),
        
        // Very generic fallback pattern
        UPISMSPattern(
            regex: #"(?:₹|Rs\.?)\s*(\d+(?:\.\d{2})?)\s+.*?(?:to|via)\s+([A-Za-z][^,\n\r]*?)(?:\s+via|\s+on|\s+at|\.|$)(?:.*?(?:Ref|ID)[:\s#]*(\w+))?"#,
            amountGroup: 1,
            merchantGroup: 2,
            referenceGroup: 3,
            bankName: "UPI",
            accountGroup: nil
        )
    ]
    
    static func parseUPITransaction(from smsText: String) -> AutomatedTransaction? {
        // Clean the SMS text first
        let cleanedText = smsText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 Parsing SMS: \(cleanedText)")
        
        for (index, pattern) in patterns.enumerated() {
            print("🔍 Trying pattern \(index + 1): \(pattern.bankName)")
            if let transaction = pattern.parse(cleanedText) {
                print("✅ Successfully parsed with pattern \(index + 1)")
                return transaction
            }
        }
        
        print("❌ No patterns matched")
        return nil
    }
}

// MARK: - UPI SMS Pattern
struct UPISMSPattern {
    let regex: String
    let amountGroup: Int
    let merchantGroup: Int
    let referenceGroup: Int?
    let bankName: String
    let accountGroup: Int?
    
    func parse(_ text: String) -> AutomatedTransaction? {
        guard let regex = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            print("❌ Invalid regex pattern for \(bankName)")
            return nil
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        
        print("🔍 Found match with \(bankName) pattern")
        
        // Extract amount
        guard match.range(at: amountGroup).location != NSNotFound,
              let amountRange = Range(match.range(at: amountGroup), in: text) else {
            print("❌ Could not extract amount")
            return nil
        }
        
        let amountString = String(text[amountRange]).replacingOccurrences(of: ",", with: "")
        guard let amount = Double(amountString), amount > 0 else {
            print("❌ Invalid amount: \(amountString)")
            return nil
        }
        
        // Extract merchant
        guard match.range(at: merchantGroup).location != NSNotFound,
              let merchantRange = Range(match.range(at: merchantGroup), in: text) else {
            print("❌ Could not extract merchant")
            return nil
        }
        
        let merchant = String(text[merchantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty else {
            print("❌ Empty merchant name")
            return nil
        }
        
        // Extract UPI reference (optional)
        var upiReference: String?
        if let refGroup = referenceGroup,
           match.range(at: refGroup).location != NSNotFound,
           let refRange = Range(match.range(at: refGroup), in: text) {
            upiReference = String(text[refRange])
        }
        
        // Extract account number (optional)
        var accountLastFour: String?
        if let accGroup = accountGroup,
           match.range(at: accGroup).location != NSNotFound,
           let accRange = Range(match.range(at: accGroup), in: text) {
            accountLastFour = String(text[accRange])
        }
        
        let cleanMerchant = cleanMerchantName(merchant)
        print("✅ Parsed: ₹\(amount) to \(cleanMerchant) via \(bankName)")
        
        var transaction = AutomatedTransaction(
            amount: amount,
            merchant: cleanMerchant,
            paymentMethod: bankName,
            date: Date(),
            source: .upi,
            upiReference: upiReference,
            bankName: bankName,
            accountLastFour: accountLastFour
        )
        
        transaction.suggestCategory()
        return transaction
    }
    
    private func cleanMerchantName(_ name: String) -> String {
        // Clean up merchant name
        var cleaned = name
            .replacingOccurrences(of: " UPI", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "UPI ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " via ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: " on ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing dots or commas
        while cleaned.hasSuffix(".") || cleaned.hasSuffix(",") {
            cleaned = String(cleaned.dropLast())
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Transaction Automation Settings
class AutomationSettings: ObservableObject {
    static let shared = AutomationSettings()
    
    @Published var isEnabled: Bool = false {
        didSet { save() }
    }
    @Published var autoApproveTransactions: Bool = false {
        didSet { save() }
    }
    @Published var requireConfirmation: Bool = true {
        didSet { save() }
    }
    @Published var defaultPaymentMethod: String = "Apple Pay" {
        didSet { save() }
    }
    @Published var enableSmartCategorization: Bool = true {
        didSet { save() }
    }
    @Published var notifyOnNewTransaction: Bool = true {
        didSet { save() }
    }
    
    // SMS/UPI specific settings
    @Published var enableSMSAutomation: Bool = false {
        didSet { save() }
    }
    @Published var enableUPIDetection: Bool = true {
        didSet { save() }
    }
    @Published var autoApproveUPITransactions: Bool = false {
        didSet { save() }
    }
    @Published var minimumUPIAmount: Double = 0.0 {
        didSet { save() }
    }
    @Published var maximumUPIAmount: Double = 10000.0 {
        didSet { save() }
    }
    
    private init() {
        load()
    }
    
    private func save() {
        let encoder = JSONEncoder()
        let data = AutomationSettingsData(
            isEnabled: isEnabled,
            autoApproveTransactions: autoApproveTransactions,
            requireConfirmation: requireConfirmation,
            defaultPaymentMethod: defaultPaymentMethod,
            enableSmartCategorization: enableSmartCategorization,
            notifyOnNewTransaction: notifyOnNewTransaction,
            enableSMSAutomation: enableSMSAutomation,
            enableUPIDetection: enableUPIDetection,
            autoApproveUPITransactions: autoApproveUPITransactions,
            minimumUPIAmount: minimumUPIAmount,
            maximumUPIAmount: maximumUPIAmount
        )
        
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: "automationSettings")
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: "automationSettings"),
           let decoded = try? JSONDecoder().decode(AutomationSettingsData.self, from: data) {
            self.isEnabled = decoded.isEnabled
            self.autoApproveTransactions = decoded.autoApproveTransactions
            self.requireConfirmation = decoded.requireConfirmation
            self.defaultPaymentMethod = decoded.defaultPaymentMethod
            self.enableSmartCategorization = decoded.enableSmartCategorization
            self.notifyOnNewTransaction = decoded.notifyOnNewTransaction
            self.enableSMSAutomation = decoded.enableSMSAutomation
            self.enableUPIDetection = decoded.enableUPIDetection
            self.autoApproveUPITransactions = decoded.autoApproveUPITransactions
            self.minimumUPIAmount = decoded.minimumUPIAmount
            self.maximumUPIAmount = decoded.maximumUPIAmount
        }
    }
}

// MARK: - Settings Data Structure
private struct AutomationSettingsData: Codable {
    var isEnabled: Bool
    var autoApproveTransactions: Bool
    var requireConfirmation: Bool
    var defaultPaymentMethod: String
    var enableSmartCategorization: Bool
    var notifyOnNewTransaction: Bool
    var enableSMSAutomation: Bool
    var enableUPIDetection: Bool
    var autoApproveUPITransactions: Bool
    var minimumUPIAmount: Double
    var maximumUPIAmount: Double
} 