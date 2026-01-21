import Foundation

// MARK: - Import Error Types
enum ImportError: LocalizedError {
    case invalidFormat(String)
    case missingData(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid file format: \(message)"
        case .missingData(let message):
            return "Missing required data: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

// MARK: - Import Result Model
struct ImportResult {
    var expenses: [Expense] = []
    var subscriptions: [Subscription] = []
    var customCategories: [CustomCategory] = []
    var deletedDefaultCategories: [String] = []
    
    init(from jsonObject: [String: Any]) throws {
        // Parse expenses
        if let expensesData = jsonObject["expenses"] as? [[String: Any]] {
            expenses = try expensesData.compactMap { try Expense(from: $0) }
        }
        
        // Parse subscriptions
        if let subscriptionsData = jsonObject["subscriptions"] as? [[String: Any]] {
            subscriptions = try subscriptionsData.compactMap { try Subscription(from: $0) }
        }
        
        // Parse custom categories
        if let categoriesData = jsonObject["customCategories"] as? [[String: Any]] {
            customCategories = try categoriesData.compactMap { try CustomCategory(from: $0) }
        }
        
        // Parse deleted default categories
        if let deletedCategoriesData = jsonObject["deletedDefaultCategories"] as? [String] {
            deletedDefaultCategories = deletedCategoriesData
        }
    }
    
    init(fromCSV content: String) throws {
        let lines = content.components(separatedBy: .newlines)
        var currentSection = ""
        var sectionLines: [String] = []
        var skipNextLine = false  // Flag to skip header line after section marker
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("===") && trimmedLine.hasSuffix("===") {
                // Process previous section
                if !currentSection.isEmpty {
                    try processCSVSection(currentSection, lines: sectionLines)
                }
                
                // Start new section
                currentSection = trimmedLine.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
                sectionLines = []
                skipNextLine = true  // Skip the header line that follows
            } else if skipNextLine {
                // Skip the header line (like "Date","Title","Amount",...)
                skipNextLine = false
                continue
            } else if !trimmedLine.isEmpty {
                sectionLines.append(trimmedLine)
            }
        }
        
        // Process final section
        if !currentSection.isEmpty {
            try processCSVSection(currentSection, lines: sectionLines)
        }
    }
    
    private mutating func processCSVSection(_ section: String, lines: [String]) throws {
        switch section {
        case "EXPENSES":
            expenses = try lines.compactMap { try Expense(fromCSV: $0) }
        case "SUBSCRIPTIONS":
            subscriptions = try lines.compactMap { try Subscription(fromCSV: $0) }
        case "CUSTOM_CATEGORIES":
            customCategories = try lines.compactMap { try CustomCategory(fromCSV: $0) }
        case "DELETED_DEFAULT_CATEGORIES":
            deletedDefaultCategories = lines.compactMap { parseCSVField($0) }
        default:
            break
        }
    }
}

// MARK: - CSV Parsing Utilities

/// Parse a single CSV field, handling quoted strings and escaped quotes
func parseCSVField(_ field: String) -> String {
    var result = field.trimmingCharacters(in: .whitespaces)
    if result.hasPrefix("\"") && result.hasSuffix("\"") {
        result = String(result.dropFirst().dropLast())
        result = result.replacingOccurrences(of: "\"\"", with: "\"")
    }
    return result
}

/// Parse a CSV line into fields, properly handling quoted strings with commas
func parseCSVFields(_ line: String) -> [String] {
    var fields: [String] = []
    var currentField = ""
    var insideQuotes = false
    var i = line.startIndex
    
    while i < line.endIndex {
        let char = line[i]
        
        if char == "\"" {
            if insideQuotes && i < line.index(before: line.endIndex) && line[line.index(after: i)] == "\"" {
                // Double quote escape
                currentField.append("\"")
                i = line.index(after: i)
            } else {
                insideQuotes.toggle()
            }
        } else if char == "," && !insideQuotes {
            fields.append(currentField)
            currentField = ""
        } else {
            currentField.append(char)
        }
        
        i = line.index(after: i)
    }
    
    fields.append(currentField)
    return fields
} 