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