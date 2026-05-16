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
    var isFromSubscription: Bool = false
    var subscriptionId: UUID?
    var tags: [String]?

    /// `true` when this row represents a refund / money returned. Storage stays
    /// always-positive in `amount`; the semantic flag tells aggregators to
    /// subtract instead of add. See `signedAmount` and the
    /// `Sequence<Expense>.netTotal()` helper.
    ///
    /// Default `false` keeps every existing call-site, every existing backup
    /// file, and every Core Data row safe — they all behave exactly as
    /// before until somebody flips this on.
    var isRefund: Bool = false

    /// Optional payment instrument used for this expense (Cash, Credit,
    /// Debit, UPI, …). `nil` means the user didn't pick one — that's the
    /// default for every legacy row, every imported foreign CSV, and any
    /// new entry where the picker is left untouched.
    ///
    /// Aggregations on the Statistics screen quietly skip rows where this
    /// is `nil`, so missing values never poison the breakdown.
    var paymentMethod: PaymentMethod?

    /// Filename (not the full path) of an attached receipt image stored in
    /// the app's Documents/Receipts directory. We persist only the filename
    /// — never an absolute path — so iCloud restores, sandbox UUID changes
    /// across iOS upgrades, and Documents migrations don't break the
    /// reference. `ReceiptStorage` resolves the full URL on demand.
    ///
    /// `nil` means "no receipt attached" — the default for every legacy
    /// row, every imported backup, and any new expense where the user
    /// didn't attach one. The Pro gate lives in `AddExpenseView`'s receipt
    /// section, not in this model — capturing the field is free so a
    /// downgraded Pro user keeps viewing receipts they already attached.
    var receiptImagePath: String?

    /// Refund-aware amount: positive for normal expenses, negative for
    /// refunds. Always use this when summing or averaging anything that
    /// the user thinks of as "spent". `amount` itself stays positive in
    /// storage so it's still safe to display as `$25.00` with a minus
    /// glyph supplied by the UI when needed.
    var signedAmount: Double {
        isRefund ? -amount : amount
    }

    // MARK: - Codable (backward-compatible)
    //
    // We override `init(from:)` so JSON backups created before the
    // `isRefund` field existed still decode cleanly. The auto-synthesized
    // decoder would refuse to decode any `Bool` field that's missing from
    // the JSON; using `decodeIfPresent` with a `false` default keeps every
    // pre-existing file readable. `encode(to:)` is still auto-synthesized
    // and will write the new key going forward.

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, currency, date, category, notes
        case customCategoryId, isFromSubscription, subscriptionId, tags, isRefund
        case paymentMethod, receiptImagePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try c.decode(String.self, forKey: .title)
        self.amount = try c.decode(Double.self, forKey: .amount)
        self.currency = try c.decode(Currency.self, forKey: .currency)
        self.date = try c.decode(Date.self, forKey: .date)
        self.category = try c.decode(Category.self, forKey: .category)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.customCategoryId = try c.decodeIfPresent(UUID.self, forKey: .customCategoryId)
        self.isFromSubscription = try c.decodeIfPresent(Bool.self, forKey: .isFromSubscription) ?? false
        self.subscriptionId = try c.decodeIfPresent(UUID.self, forKey: .subscriptionId)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags)
        self.isRefund = try c.decodeIfPresent(Bool.self, forKey: .isRefund) ?? false
        // `paymentMethod` was added after the original schema. Use
        // `tolerant(from:)` so an unknown raw value (older app version that
        // wrote a now-removed case, or a human-edited backup) decodes as
        // `.other` instead of failing the whole row.
        let pmRaw = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
        self.paymentMethod = PaymentMethod.tolerant(from: pmRaw)
        // `receiptImagePath` was added in v2.0 alongside the Receipt
        // Scanner. `decodeIfPresent` keeps every pre-existing JSON backup
        // valid; a missing key resolves to `nil` (no attached receipt).
        self.receiptImagePath = try c.decodeIfPresent(String.self, forKey: .receiptImagePath)
    }

    /// Memberwise initialiser kept explicit because we now own a custom
    /// Codable `init(from:)` (which suppresses the auto one).
    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        currency: Currency,
        date: Date,
        category: Category,
        notes: String? = nil,
        customCategoryId: UUID? = nil,
        isFromSubscription: Bool = false,
        subscriptionId: UUID? = nil,
        tags: [String]? = nil,
        isRefund: Bool = false,
        paymentMethod: PaymentMethod? = nil,
        receiptImagePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currency = currency
        self.date = date
        self.category = category
        self.notes = notes
        self.customCategoryId = customCategoryId
        self.isFromSubscription = isFromSubscription
        self.subscriptionId = subscriptionId
        self.tags = tags
        self.isRefund = isRefund
        self.paymentMethod = paymentMethod
        self.receiptImagePath = receiptImagePath
    }
    
    enum Currency: String, CaseIterable, Codable {
        case usd = "USD"
        case eur = "EUR"
        case gbp = "GBP"
        case jpy = "JPY"
        case cad = "CAD"
        case aud = "AUD"
        case inr = "INR"
        case cny = "CNY"
        case chf = "CHF"
        case nzd = "NZD"
        case sgd = "SGD"
        case hkd = "HKD"
        case sek = "SEK"
        case nok = "NOK"
        case dkk = "DKK"
        case pln = "PLN"
        case rub = "RUB"
        case try_ = "TRY"
        case brl = "BRL"
        case mxn = "MXN"
        case zar = "ZAR"
        case krw = "KRW"
        case twd = "TWD"
        case thb = "THB"
        case myr = "MYR"
        case idr = "IDR"
        case php = "PHP"
        case vnd = "VND"
        case aed = "AED"
        case sar = "SAR"
        case ils = "ILS"
        case egp = "EGP"
        case pkr = "PKR"
        case bdt = "BDT"
        case ngn = "NGN"
        case kes = "KES"
        case ghs = "GHS"
        case clp = "CLP"
        case cop = "COP"
        case pen = "PEN"
        case ars = "ARS"
        case uah = "UAH"
        case ron = "RON"
        case czk = "CZK"
        case huf = "HUF"
        case bgn = "BGN"
        case hrk = "HRK"
        case rsd = "RSD"
        case isk = "ISK"
        case kzt = "KZT"
        case qar = "QAR"
        case kwd = "KWD"
        case bhd = "BHD"
        case omr = "OMR"
        case jod = "JOD"
        case lbp = "LBP"
        case mad = "MAD"
        case dzd = "DZD"
        case tnd = "TND"
        case lyd = "LYD"
        case sdg = "SDG"
        case etb = "ETB"
        case ugx = "UGX"
        case tzs = "TZS"
        case mur = "MUR"
        case mop = "MOP"
        case mmk = "MMK"
        case khr = "KHR"
        case lak = "LAK"
        case mnt = "MNT"
        case npr = "NPR"
        case lkr = "LKR"
        case mvr = "MVR"
        case bnd = "BND"
        case fjd = "FJD"
        case pgk = "PGK"
        case sbd = "SBD"
        case top = "TOP"
        case vuv = "VUV"
        case wst = "WST"
        case xpf = "XPF"
        case xaf = "XAF"
        case xof = "XOF"
        case xcd = "XCD"
        case bbd = "BBD"
        case jmd = "JMD"
        case ttd = "TTD"
        case bzd = "BZD"
        case gyd = "GYD"
        case srd = "SRD"
        case bmd = "BMD"
        case kyd = "KYD"
        case ang = "ANG"
        case awg = "AWG"
        case bsd = "BSD"
        case cup = "CUP"
        case dop = "DOP"
        case htg = "HTG"
        case pab = "PAB"
        case pyg = "PYG"
        case uyu = "UYU"
        case ves = "VES"
        case bob = "BOB"
        case crc = "CRC"
        case gtq = "GTQ"
        case hnl = "HNL"
        case nio = "NIO"
        case svc = "SVC"
        case bam = "BAM"
        case all = "ALL"
        case mkd = "MKD"
        case mdl = "MDL"
        case gel = "GEL"
        case amd = "AMD"
        case azn = "AZN"
        case byn = "BYN"
        case tjs = "TJS"
        case tmt = "TMT"
        case uzs = "UZS"
        case kgs = "KGS"
        case afn = "AFN"
        case irr = "IRR"
        case iqd = "IQD"
        case syp = "SYP"
        case yer = "YER"
        case bif = "BIF"
        case cdf = "CDF"
        case djf = "DJF"
        case eri = "ERI"
        case rwf = "RWF"
        case sos = "SOS"
        case ssp = "SSP"
        case szl = "SZL"
        case zmw = "ZMW"
        case zwl = "ZWL"
        case nad = "NAD"
        case mwk = "MWK"
        case mga = "MGA"
        case scr = "SCR"
        case kmf = "KMF"
        case stn = "STN"
        case cve = "CVE"
        case gmd = "GMD"
        case gnf = "GNF"
        case lrd = "LRD"
        case sll = "SLL"
        case mro = "MRO"
        case mru = "MRU"
        case shp = "SHP"
        case fkp = "FKP"
        case gip = "GIP"
        case imp = "IMP"
        case jep = "JEP"
        case ggp = "GGP"
        case aoa = "AOA"
        
        var symbol: String {
            return CurrencyData.getCurrencyData(for: rawValue)?.symbol ?? "$"
        }
        
        var name: String {
            return CurrencyData.getCurrencyData(for: rawValue)?.name ?? rawValue
        }

        /// Country/region flag emoji for this currency, derived from the
        /// ISO 4217 code's 2-letter prefix (which is almost always the
        /// ISO 3166 country code: USD→US, INR→IN, EUR→EU, JPY→JP, …).
        ///
        /// A handful of supranational codes (XAF/XOF/XPF/XCD) and any code
        /// that doesn't follow the convention fall back to a globe so we
        /// never render a broken flag glyph.
        var flag: String {
            switch rawValue {
            case "XAF", "XOF", "XPF", "XCD": return "🌐"
            default: break
            }
            let prefix = rawValue.prefix(2).uppercased()
            guard prefix.count == 2 else { return "🌐" }
            // Regional Indicator Symbol Letter A starts at U+1F1E6 (= 65 + 127397).
            let base: UInt32 = 127_397
            var s = ""
            for v in prefix.unicodeScalars {
                guard (65...90).contains(v.value),
                      let scalar = UnicodeScalar(base + v.value) else { return "🌐" }
                s.append(Character(scalar))
            }
            return s.isEmpty ? "🌐" : s
        }

        /// ISO 4217 minor unit count — how many decimal places this currency
        /// natively uses. Drives the formatter so Japanese/Korean/Indonesian
        /// users don't see the awkward "¥1,234.00" and Bahraini/Kuwaiti
        /// users see the proper 3-decimal representation.
        var fractionDigits: Int {
            switch rawValue {
            // Zero-decimal currencies
            case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
                 "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
                 "HUF", "IDR":
                return 0
            // Three-decimal currencies (mostly Gulf)
            case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
                return 3
            // Mauritanian ouguiya & Malagasy ariary use 1 decimal officially
            case "MGA", "MRU":
                return 1
            default:
                return 2
            }
        }
        
        static var allCases: [Currency] {
            return CurrencyData.allCurrencies.compactMap { currencyData in
                Currency(rawValue: currencyData.code)
            }
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
        
        var displayName: String {
            switch self {
            case .groceries: return "Groceries"
            case .food: return "Food & Drinks"
            case .transportation: return "Transportation"
            case .entertainment: return "Entertainment"
            case .shopping: return "Shopping"
            case .utilities: return "Utilities"
            case .health: return "Health"
            case .education: return "Education"
            case .travel: return "Travel"
            case .custom: return "Custom"
            case .other: return "Other"
            }
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

// MARK: - Import Extensions
extension Expense {
    init(from json: [String: Any]) throws {
        guard let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = json["title"] as? String,
              let amount = json["amount"] as? Double,
              let currencyRaw = json["currency"] as? String,
              let currency = Currency(rawValue: currencyRaw),
              let dateString = json["date"] as? String,
              let date = ISO8601DateFormatter().date(from: dateString),
              let categoryRaw = json["category"] as? String,
              let category = Category(rawValue: categoryRaw) else {
            throw ImportError.parseError("Invalid expense data")
        }
        
        self.id = id
        self.title = title
        self.amount = amount
        self.currency = currency
        self.date = date
        self.category = category
        self.notes = json["notes"] as? String
        
        // Safety check for NaN or invalid amounts
        guard amount.isFinite && amount >= 0 else {
            throw ImportError.parseError("Invalid expense amount in JSON: \(amount). Amount must be a positive finite number.")
        }
        
        if let customCategoryIdString = json["customCategoryId"] as? String {
            self.customCategoryId = UUID(uuidString: customCategoryIdString)
        }
        
        self.isFromSubscription = json["isFromSubscription"] as? Bool ?? false
        
        if let subscriptionIdString = json["subscriptionId"] as? String {
            self.subscriptionId = UUID(uuidString: subscriptionIdString)
        }

        if let rawTags = json["tags"] as? [String] {
            let cleaned = rawTags.compactMap { Tag.normalize($0) }
            self.tags = cleaned.isEmpty ? nil : cleaned
        }

        // Optional and additive — pre-2.x backups don't have this key, which
        // safely falls through to `false`.
        self.isRefund = (json["isRefund"] as? Bool) ?? false

        // Optional and additive — older backups simply omit this key and the
        // expense restores with no payment method, exactly as before.
        if let pm = json["paymentMethod"] as? String {
            self.paymentMethod = PaymentMethod.tolerant(from: pm)
        }
    }
    
    init(fromCSV line: String) throws {
        let fields = parseCSVFields(line)
        guard fields.count >= 8 else {
            throw ImportError.parseError("Invalid CSV expense format: expected 8 fields, got \(fields.count)")
        }
        
        // Try multiple date formats for better compatibility
        let dateString = parseCSVField(fields[1]) // Date is now field 1 (after ID)
        var date: Date?
        
        // Try medium style first (matches export format)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        date = dateFormatter.date(from: dateString)
        
        // If that fails, try other common formats
        if date == nil {
            dateFormatter.dateFormat = "MMM d, yyyy"
            date = dateFormatter.date(from: dateString)
        }
        
        if date == nil {
            dateFormatter.dateFormat = "yyyy-MM-dd"
            date = dateFormatter.date(from: dateString)
        }
        
        if date == nil {
            dateFormatter.dateFormat = "MM/dd/yyyy"
            date = dateFormatter.date(from: dateString)
        }
        
        // Parse ID from CSV or generate new one as fallback
        var expenseId: UUID
        let idString = parseCSVField(fields[0])
        if let parsedId = UUID(uuidString: idString) {
            expenseId = parsedId
        } else {
            // Fallback: generate new ID if parsing fails
            expenseId = UUID()
        }
        
        guard let finalDate = date,
              let amount = Double(parseCSVField(fields[3])), // Amount is now field 3
              let currency = Currency(rawValue: parseCSVField(fields[4])), // Currency is now field 4
              let category = Category(rawValue: parseCSVField(fields[5])) else { // Category is now field 5
            throw ImportError.parseError("Invalid CSV expense data: id='\(idString)', date='\(dateString)', title='\(parseCSVField(fields[2]))', amount='\(parseCSVField(fields[3]))', currency='\(parseCSVField(fields[4]))', category='\(parseCSVField(fields[5]))'")
        }
        
        // Safety check for NaN or invalid amounts
        guard amount.isFinite && amount >= 0 else {
            throw ImportError.parseError("Invalid expense amount: \(amount). Amount must be a positive finite number.")
        }
        
        self.id = expenseId
        self.title = parseCSVField(fields[2]) // Title is now field 2
        self.amount = amount
        self.currency = currency
        self.date = finalDate
        self.category = category
        
        let customCategoryIdString = parseCSVField(fields[6]) // CustomCategoryId is now field 6
        if !customCategoryIdString.isEmpty {
            self.customCategoryId = UUID(uuidString: customCategoryIdString)
        }
        
        let notes = parseCSVField(fields[7]) // Notes is now field 7
        self.notes = notes.isEmpty ? nil : notes

        // Tags are an optional 9th field (semicolon-separated). Backward-compatible
        // with older exports that only have 8 fields.
        if fields.count >= 9 {
            let raw = parseCSVField(fields[8])
            if !raw.isEmpty {
                let parsed = raw
                    .split(separator: ";", omittingEmptySubsequences: true)
                    .compactMap { Tag.normalize(String($0)) }
                self.tags = parsed.isEmpty ? nil : parsed
            }
        }

        // Refund flag — optional 10th field (`true` / `false` / `1` / `0`).
        // Backward compatible: older CSVs simply skip it and the row stays
        // a normal expense.
        if fields.count >= 10 {
            let raw = parseCSVField(fields[9]).lowercased()
            self.isRefund = (raw == "true" || raw == "1" || raw == "yes")
        }

        // Payment method — optional 11th field. Backward compatible: older
        // exports stop at field 10 and the expense restores with no
        // payment method.
        if fields.count >= 11 {
            let raw = parseCSVField(fields[10])
            self.paymentMethod = PaymentMethod.tolerant(from: raw)
        }

        self.isFromSubscription = false
        self.subscriptionId = nil
    }
}

// MARK: - Refund-aware aggregation
extension Sequence where Element == Expense {
    /// Sum that respects refunds — refunds are subtracted. Use this anywhere
    /// the user thinks of the result as "how much I spent". For raw "how
    /// much money moved" totals (rare) sum `.amount` directly.
    func netTotal() -> Double {
        reduce(0) { $0 + $1.signedAmount }
    }
}
