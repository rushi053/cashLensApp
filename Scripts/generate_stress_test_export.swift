import Foundation

// Generates a CashLens-compatible JSON export file for stress testing imports/performance.
//
// Usage:
//   swift Scripts/generate_stress_test_export.swift --count 5000 --out ./stress-test-exports/CashLens_StressTest_5000.json
//
// Optional:
//   --currency INR
//   --seed 12345
//   --subscriptions 20
//
// Dev-only: this is NOT used by the app target.

struct Args {
    var count: Int = 5000
    var outPath: String = "./CashLens_StressTest_5000.json"
    var currency: String = "INR"
    var seed: UInt64 = 42
    var subscriptionCount: Int = 20
}

struct LCRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1
        return state
    }
    mutating func nextInt(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
    mutating func nextDouble01() -> Double {
        let v = next() >> 11
        return Double(v) / Double(1 << 53)
    }
}

func parseArgs() -> Args {
    var a = Args()
    let argv = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < argv.count {
        switch argv[i] {
        case "--count":
            if i + 1 < argv.count, let v = Int(argv[i + 1]), v > 0 {
                a.count = v
                i += 2
            } else { i += 1 }
        case "--out":
            if i + 1 < argv.count {
                a.outPath = argv[i + 1]
                i += 2
            } else { i += 1 }
        case "--currency":
            if i + 1 < argv.count {
                a.currency = argv[i + 1].uppercased()
                i += 2
            } else { i += 1 }
        case "--seed":
            if i + 1 < argv.count, let v = UInt64(argv[i + 1]) {
                a.seed = v
                i += 2
            } else { i += 1 }
        case "--subscriptions":
            if i + 1 < argv.count, let v = Int(argv[i + 1]), v >= 0 {
                a.subscriptionCount = v
                i += 2
            } else { i += 1 }
        default:
            i += 1
        }
    }
    return a
}

let args = parseArgs()
var rng = LCRNG(seed: args.seed)

// Match CashLens export format (no fractional seconds).
let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]

let now = Date()
let calendar = Calendar.current

let defaultCategories: [String] = [
    "Groceries", "Food", "Transportation", "Entertainment", "Shopping",
    "Utilities", "Health", "Education", "Travel", "Other"
]

let customCategoryColors = ["mauve", "jordyBlue", "teaRose", "electricBlue", "celadon", "pinkLavender"]
let customCategoryIcons = ["cup.and.saucer.fill", "gamecontroller.fill", "pawprint.fill", "desktopcomputer", "leaf.fill", "ticket.fill"]

let customCategories: [[String: Any]] = (0..<min(6, customCategoryColors.count)).map { idx in
    let id = UUID()
    return [
        "id": id.uuidString,
        "name": ["Coffee", "Games", "Pets", "Tech", "Self Care", "Events"][idx],
        "icon": customCategoryIcons[idx],
        "colorName": customCategoryColors[idx]
    ]
}

let customCategoryIds: [UUID] = customCategories.compactMap { dict in
    (dict["id"] as? String).flatMap(UUID.init(uuidString:))
}

let subscriptionNames = ["Netflix", "Spotify", "iCloud", "Gym", "Prime", "YouTube Premium", "Notion", "Disney+"]
let frequencies = ["Monthly", "Yearly", "Weekly", "Quarterly"]

let subscriptions: [[String: Any]] = (0..<args.subscriptionCount).map { idx in
    let id = UUID()
    let name = subscriptionNames[idx % subscriptionNames.count]
    let amount = Double(99 + rng.nextInt(1500)) + (rng.nextDouble01() * 0.99)
    let startDate = calendar.date(byAdding: .month, value: -(1 + rng.nextInt(18)), to: now) ?? now
    let freq = frequencies[rng.nextInt(frequencies.count)]
    let nextDue = calendar.date(byAdding: .day, value: 1 + rng.nextInt(30), to: now) ?? now
    let category = defaultCategories[rng.nextInt(defaultCategories.count)]
    let useCustom = rng.nextDouble01() < 0.15
    
    return [
        "id": id.uuidString,
        "name": name,
        "amount": amount,
        "currency": args.currency,
        "startDate": iso.string(from: startDate),
        "frequency": freq,
        "nextDueDate": iso.string(from: nextDue),
        "category": useCustom ? "Custom" : category,
        "customCategoryId": useCustom ? (customCategoryIds.randomElement()?.uuidString ?? NSNull()) : NSNull(),
        "notes": NSNull(),
        "isActive": true,
        "reminderEnabled": true,
        "reminderDaysBefore": 1
    ]
}

let subscriptionIds: [UUID] = subscriptions.compactMap { dict in
    (dict["id"] as? String).flatMap(UUID.init(uuidString:))
}

let titles = [
    "Coffee", "Lunch", "Groceries", "Uber", "Snacks", "Movie", "Fuel", "Pharmacy",
    "Online Order", "Dinner", "Bus Ticket", "Gym Day Pass", "Gift", "Hotel", "Flight",
    "Book", "Subscription", "Electricity Bill", "Water Bill", "Phone Recharge"
]

func randomDateWithinLast(days: Int) -> Date {
    let offsetDays = rng.nextInt(max(1, days))
    let offsetSeconds = Int(rng.nextInt(24 * 60 * 60))
    let d = calendar.date(byAdding: .day, value: -offsetDays, to: now) ?? now
    return calendar.date(byAdding: .second, value: -offsetSeconds, to: d) ?? d
}

var expenses: [[String: Any]] = []
expenses.reserveCapacity(args.count)

for i in 0..<args.count {
    let id = UUID()
    let title = titles[rng.nextInt(titles.count)]
    
    let p = rng.nextDouble01()
    let amount: Double
    if p < 0.80 {
        amount = Double(20 + rng.nextInt(800)) + (rng.nextDouble01() * 0.99)
    } else if p < 0.97 {
        amount = Double(800 + rng.nextInt(5000)) + (rng.nextDouble01() * 0.99)
    } else {
        amount = Double(5000 + rng.nextInt(20000)) + (rng.nextDouble01() * 0.99)
    }
    
    let date = randomDateWithinLast(days: 730)
    
    let useCustom = rng.nextDouble01() < 0.18
    let category = useCustom ? "Custom" : defaultCategories[rng.nextInt(defaultCategories.count)]
    let customId = useCustom ? customCategoryIds[rng.nextInt(customCategoryIds.count)] : nil
    
    let fromSub = !subscriptionIds.isEmpty && (rng.nextDouble01() < 0.08)
    let subId = fromSub ? subscriptionIds[rng.nextInt(subscriptionIds.count)] : nil
    
    let notes: Any = (rng.nextDouble01() < 0.12) ? "Note \(i % 17)" : NSNull()
    
    expenses.append([
        "id": id.uuidString,
        "title": title,
        "amount": amount,
        "currency": args.currency,
        "date": iso.string(from: date),
        "category": category,
        "customCategoryId": customId != nil ? customId!.uuidString : NSNull(),
        "notes": notes,
        "isFromSubscription": fromSub,
        "subscriptionId": subId != nil ? subId!.uuidString : NSNull()
    ])
}

let export: [String: Any] = [
    "exportVersion": "1.0",
    "exportDate": iso.string(from: now),
    "expenses": expenses,
    "subscriptions": subscriptions,
    "customCategories": customCategories,
    "deletedDefaultCategories": []
]

do {
    let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
    let url = URL(fileURLWithPath: args.outPath)
    try data.write(to: url)
    print("✅ Wrote stress-test export: \(url.path)")
    print("   expenses=\(expenses.count), subscriptions=\(subscriptions.count), customCategories=\(customCategories.count)")
} catch {
    fputs("❌ Failed to write JSON: \(error)\n", stderr)
    exit(1)
}

