import Foundation

/// `GenericCSVAdapter` makes Pro users feel like CashLens "just works" with
/// CSV files exported from other money apps and bank statements.
///
/// Given an arbitrary CSV (with a header row), it tries to map each column
/// onto an `Expense` field by matching the header text against a curated
/// dictionary of synonyms — case-insensitive, whitespace-insensitive.
///
/// Supported out of the box:
/// - **CashLens v2** native flat CSV (perfect mapping)
/// - **Mint**: `Date, Description, Original Description, Amount, Transaction Type, Category, Account Name, Labels, Notes`
/// - **YNAB (You Need a Budget)**: `Account, Flag, Date, Payee, Category Group/Category, Memo, Outflow, Inflow`
/// - **Apple Card / Apple Wallet** statements: `Transaction Date, Clearing Date, Description, Merchant, Category, Type, Amount (USD)`
/// - **Generic bank** statements: `Date, Description, Amount, Balance, Category`
/// - Any custom CSV with at least `Date` + `Amount` (+ optional `Description`/`Title`).
///
/// The adapter is intentionally forgiving: rows missing a category default to
/// `.other`, dates are parsed against several common formats, and amounts
/// tolerate currency symbols, thousands separators, and `(parentheses)` for
/// negatives. Any unparseable row is recorded as a `RowError` and skipped —
/// the import as a whole continues so users always get *something* back.
enum GenericCSVAdapter {

    // MARK: - Public

    struct Result {
        var expenses: [Expense]
        var errors: [RowError]
        var detectedFormat: String
        var mappedColumns: [String: ColumnRole]
    }

    struct RowError {
        var line: Int
        var reason: String
    }

    enum ColumnRole: String {
        case date = "Date"
        case title = "Title"
        case amount = "Amount"
        case currency = "Currency"
        case category = "Category"
        case notes = "Notes"
        case tags = "Tags"
        case outflow = "Outflow"
        case inflow = "Inflow"
        case paymentMethod = "Payment Method"
        case ignore = "Ignore"
    }

    // MARK: - Header synonyms

    private static let headerSynonyms: [(role: ColumnRole, names: [String])] = [
        (.date,     ["date", "transaction date", "posted date", "clearing date", "trans date", "posting date", "value date"]),
        (.title,    ["title", "description", "payee", "merchant", "name", "memo", "details", "narrative", "transaction", "description / payee"]),
        (.amount,   ["amount", "amount (usd)", "amount(usd)", "value", "transaction amount", "debit/credit"]),
        (.outflow,  ["outflow", "debit", "withdrawal", "payment", "spent", "money out", "expense"]),
        (.inflow,   ["inflow", "credit", "deposit", "income", "money in", "received"]),
        (.currency, ["currency", "ccy", "currency code"]),
        (.category, ["category", "category group/category", "type", "transaction type", "tag"]),
        (.notes,    ["notes", "memo", "comment", "remarks", "description (extra)", "original description"]),
        (.tags,     ["tags", "labels", "label"]),
        // Both raw (`payment method`) and the column header CashLens v2.2
        // CSV writes (`Payment Method`). Bank/wallet statements often use
        // "method" or "channel"; we accept those too.
        (.paymentMethod, ["payment method", "payment_method", "paymentmethod", "method", "channel", "payment type", "pay type"])
    ]

    /// Parse an arbitrary CSV `String` into a `Result`. The first non-empty
    /// row is treated as the header.
    static func parse(_ content: String, fallbackCurrency: Expense.Currency) -> Result {
        let rows = CSVParser.parseRows(content)
        guard let headers = rows.first(where: { !$0.isEmpty && $0.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) }) else {
            return Result(expenses: [], errors: [], detectedFormat: "Unknown", mappedColumns: [:])
        }
        let mapping = autoMap(headers: headers)
        let detected = detectVendor(headers: headers)

        var expenses: [Expense] = []
        var errors: [RowError] = []

        let bodyStart = (rows.firstIndex(where: { $0 == headers }) ?? 0) + 1
        for (offset, row) in rows[bodyStart...].enumerated() {
            let line = bodyStart + offset + 1 // 1-based for humans
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            do {
                let expense = try buildExpense(
                    row: row,
                    headers: headers,
                    mapping: mapping,
                    fallbackCurrency: fallbackCurrency
                )
                if let expense {
                    expenses.append(expense)
                }
            } catch {
                errors.append(RowError(line: line, reason: error.localizedDescription))
            }
        }

        return Result(
            expenses: expenses,
            errors: errors,
            detectedFormat: detected,
            mappedColumns: mappingToReadable(headers: headers, mapping: mapping)
        )
    }

    // MARK: - Mapping

    private static func autoMap(headers: [String]) -> [Int: ColumnRole] {
        var mapping: [Int: ColumnRole] = [:]
        for (index, raw) in headers.enumerated() {
            let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let role = headerSynonyms.first(where: { $0.names.contains(normalized) })?.role {
                mapping[index] = role
            }
        }
        return mapping
    }

    private static func mappingToReadable(headers: [String], mapping: [Int: ColumnRole]) -> [String: ColumnRole] {
        var readable: [String: ColumnRole] = [:]
        for (i, header) in headers.enumerated() {
            if let role = mapping[i] {
                readable[header] = role
            }
        }
        return readable
    }

    private static func detectVendor(headers: [String]) -> String {
        let lowered = headers.map { $0.lowercased() }
        if lowered.contains("category group/category") && lowered.contains("payee") && (lowered.contains("outflow") || lowered.contains("inflow")) {
            return "YNAB"
        }
        if lowered.contains("original description") && lowered.contains("transaction type") {
            return "Mint"
        }
        if lowered.contains("clearing date") || lowered.contains("amount (usd)") {
            return "Apple Card"
        }
        if lowered.contains("title") && lowered.contains("amount") && lowered.contains("currency") && lowered.contains("id") {
            return "CashLens (flat CSV)"
        }
        return "Generic CSV"
    }

    // MARK: - Row → Expense

    private static func buildExpense(
        row: [String],
        headers: [String],
        mapping: [Int: ColumnRole],
        fallbackCurrency: Expense.Currency
    ) throws -> Expense? {
        func value(_ role: ColumnRole) -> String? {
            for (i, mapped) in mapping where mapped == role {
                if i < row.count {
                    let cell = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cell.isEmpty { return cell }
                }
            }
            return nil
        }

        guard let dateString = value(.date) else {
            throw AdapterError.missingDate
        }
        guard let date = parseDate(dateString) else {
            throw AdapterError.invalidDate(dateString)
        }

        // Amount can come from a single column OR from outflow/inflow pair (YNAB).
        let amount: Double
        let isExpense: Bool
        if let outflowString = value(.outflow), let outflow = parseAmount(outflowString), outflow > 0 {
            amount = outflow
            isExpense = true
        } else if let inflowString = value(.inflow), let inflow = parseAmount(inflowString), inflow > 0 {
            // Inflow alone (e.g. salary) — skip; CashLens is expense-tracking.
            _ = inflow
            return nil
        } else if let amountString = value(.amount), let parsed = parseAmount(amountString) {
            // In Mint/bank CSVs negative or parenthesized amounts mean outflow.
            // We always store positive amounts; an inflow row is skipped.
            if parsed < 0 || amountString.contains("(") {
                amount = abs(parsed)
                isExpense = true
            } else {
                // Positive — could be income (Mint marks via Transaction Type) or
                // an expense (most banks). Default to expense unless explicitly
                // marked as a credit transaction.
                if let type = value(.category), type.lowercased() == "credit" {
                    return nil
                }
                amount = abs(parsed)
                isExpense = true
            }
        } else {
            throw AdapterError.missingAmount
        }

        guard isExpense, amount.isFinite, amount >= 0 else { return nil }

        let title = (value(.title) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.isEmpty ? "Imported expense" : title

        let category = mapCategory(value(.category))

        let currency: Expense.Currency
        if let raw = value(.currency), let parsed = Expense.Currency(rawValue: raw.uppercased()) {
            currency = parsed
        } else {
            currency = fallbackCurrency
        }

        let notes: String? = value(.notes)
        let tags: [String]?
        if let raw = value(.tags) {
            // Accept ; , or | as tag separators.
            let parts = raw
                .components(separatedBy: CharacterSet(charactersIn: ";,|"))
                .compactMap { Tag.normalize($0) }
            tags = parts.isEmpty ? nil : parts
        } else {
            tags = nil
        }

        var expense = Expense(
            title: cleanTitle,
            amount: amount,
            currency: currency,
            date: date,
            category: category,
            notes: notes
        )
        expense.tags = tags
        // Best-effort payment method from a column header like "Method" or
        // "Payment Type". Tolerant decoder maps unknown strings to `.other`
        // and absent values to `nil`.
        expense.paymentMethod = PaymentMethod.tolerant(from: value(.paymentMethod))
        return expense
    }

    // MARK: - Parsers

    private static let dateFormats: [String] = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX", // ISO 8601 (CashLens v2)
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "MM/dd/yy",
        "dd/MM/yyyy",
        "dd/MM/yy",
        "MMM d, yyyy",
        "d MMM yyyy",
        "yyyy/MM/dd"
    ]

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        // Fall back to user locale's medium / short style.
        let mediumStyle = DateFormatter()
        mediumStyle.dateStyle = .medium
        if let date = mediumStyle.date(from: trimmed) { return date }
        let shortStyle = DateFormatter()
        shortStyle.dateStyle = .short
        if let date = shortStyle.date(from: trimmed) { return date }
        return nil
    }

    /// Parse amount strings tolerating currency symbols, thousands separators,
    /// `(parentheses)` for negatives, and `1,234.56` vs `1.234,56` numbers.
    private static func parseAmount(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var working = trimmed
        var isNegative = false
        if working.hasPrefix("(") && working.hasSuffix(")") {
            isNegative = true
            working = String(working.dropFirst().dropLast())
        }
        if working.hasPrefix("-") {
            isNegative = true
            working.removeFirst()
        }

        // Strip currency symbols + spaces.
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        working = String(working.unicodeScalars.filter { allowed.contains($0) })

        // Determine decimal separator: assume the *last* `.` or `,` is decimal.
        let lastDot = working.lastIndex(of: ".")
        let lastComma = working.lastIndex(of: ",")
        let decimalIndex: String.Index? = {
            switch (lastDot, lastComma) {
            case let (d?, c?): return d > c ? d : c
            case let (d?, nil): return d
            case let (nil, c?): return c
            case (nil, nil): return nil
            }
        }()

        if let decimalIndex {
            let integerPart = String(working[..<decimalIndex])
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")
            let decimalPart = String(working[working.index(after: decimalIndex)...])
            working = integerPart + "." + decimalPart
        } else {
            working = working
                .replacingOccurrences(of: ",", with: "")
        }

        guard let value = Double(working) else { return nil }
        return isNegative ? -value : value
    }

    /// Map an inbound category label onto our default category set when there's
    /// an obvious match, otherwise fall back to `.other`. We deliberately don't
    /// auto-create custom categories during import — that's a separate UX flow
    /// to keep import previews predictable.
    private static func mapCategory(_ raw: String?) -> Expense.Category {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return .other
        }
        // Direct rawValue match (case-insensitive).
        if let direct = Expense.Category.allCases.first(where: { $0.rawValue.lowercased() == raw }) {
            return direct
        }
        // Heuristic substring buckets.
        let buckets: [(Expense.Category, [String])] = [
            (.groceries,      ["grocery", "supermarket", "produce"]),
            (.food,           ["restaurant", "dining", "coffee", "fast food", "food", "drink", "bar"]),
            (.transportation, ["uber", "lyft", "taxi", "transit", "transport", "fuel", "gas", "parking", "auto", "bus", "train"]),
            (.entertainment,  ["movie", "music", "stream", "netflix", "spotify", "game", "fun", "hobby"]),
            (.shopping,       ["shop", "amazon", "store", "retail", "clothes", "apparel"]),
            (.utilities,      ["utility", "electric", "water", "internet", "phone", "wifi", "gas bill"]),
            (.health,         ["health", "doctor", "pharmacy", "medical", "fitness", "gym"]),
            (.education,      ["education", "school", "tuition", "book", "course"]),
            (.travel,         ["travel", "hotel", "flight", "airbnb", "vacation"])
        ]
        for (category, keywords) in buckets {
            if keywords.contains(where: { raw.contains($0) }) {
                return category
            }
        }
        return .other
    }

    enum AdapterError: LocalizedError {
        case missingDate
        case invalidDate(String)
        case missingAmount

        var errorDescription: String? {
            switch self {
            case .missingDate: return "missing date"
            case .invalidDate(let s): return "couldn't parse date '\(s)'"
            case .missingAmount: return "missing amount"
            }
        }
    }
}

// MARK: - CSV Parser

/// Minimal RFC 4180 CSV row splitter. Handles quoted fields, escaped quotes,
/// embedded commas, and CRLF line endings.
enum CSVParser {
    static func parseRows(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var index = content.startIndex

        while index < content.endIndex {
            let char = content[index]
            if char == "\"" {
                let next = content.index(after: index)
                if insideQuotes, next < content.endIndex, content[next] == "\"" {
                    currentField.append("\"")
                    index = next
                } else {
                    insideQuotes.toggle()
                }
            } else if char == "," && !insideQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if (char == "\n" || char == "\r") && !insideQuotes {
                currentRow.append(currentField)
                currentField = ""
                if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                    rows.append(currentRow)
                }
                currentRow = []
                // Skip the LF in a CRLF pair.
                if char == "\r" {
                    let next = content.index(after: index)
                    if next < content.endIndex, content[next] == "\n" {
                        index = next
                    }
                }
            } else {
                currentField.append(char)
            }
            index = content.index(after: index)
        }
        // Flush trailing field/row.
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                rows.append(currentRow)
            }
        }
        return rows
    }
}
