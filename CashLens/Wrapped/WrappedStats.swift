import Foundation

// MARK: - Story model

enum WrappedPageKind: String, CaseIterable, Identifiable, Hashable {
    case total
    case topCategory
    case topMerchant
    case biggestDay
    case funFact
    case paymentSplit
    case closing

    var id: String { rawValue }
}

enum WrappedScript {
    /// About 4.5 seconds. The player ticks 45 times at 100ms.
    static let cardDuration: TimeInterval = 4.5
    static let ticksPerCard = 45

    static func pages(for stats: WrappedStats) -> [WrappedPageKind] {
        var pages: [WrappedPageKind] = [.total]
        if stats.transactionCount > 0 {
            if stats.topCategory != nil { pages.append(.topCategory) }
            if stats.topMerchant != nil { pages.append(.topMerchant) }
            if stats.biggestDay != nil, stats.activeDays >= 2 {
                pages.append(.biggestDay)
            }
            pages.append(.funFact)
            if stats.paymentSplit != nil { pages.append(.paymentSplit) }
        } else {
            pages.append(.funFact)
        }
        pages.append(.closing)
        return pages
    }
}

struct WrappedRank: Equatable {
    var name: String
    var amount: Double
    var count: Int
    var share: Double
    var icon: String
    var builtinCategory: Expense.Category?
}

struct WrappedDay: Equatable {
    var date: Date
    var amount: Double
    var share: Double
    var label: String
}

struct WrappedPaymentSplit: Equatable {
    var upiAmount: Double
    var otherAmount: Double
    var upiCount: Int
    var otherCount: Int
    var taggedCount: Int
    /// UPI amount divided by tagged amount. 0 when nothing was tagged as UPI.
    var upiShareOfTagged: Double
}

struct WrappedComparison: Equatable {
    var previousTotal: Double
    var previousTitle: String
    /// `(current - previous) / previous`. Nil when the previous total is 0.
    var changeFraction: Double?
}

enum WrappedFunFact: Equatable {
    case upcoming(label: String)
    case empty
    case thin(count: Int)
    case noSpendStreak(days: Int)
    case spendStreak(days: Int)
    case weekendHeavy(share: Double)
    case singleBill(title: String, amount: Double, share: Double)
    case subscriptions(share: Double)
    case spread(activeDays: Int, observedDays: Int)
}

struct WrappedStats: Equatable {
    var period: WrappedPeriod
    var title: String
    var windowStart: Date
    var windowEnd: Date
    var currency: Expense.Currency
    var transactionCount: Int
    var total: Double
    var topCategory: WrappedRank?
    var topMerchant: WrappedRank?
    var biggestDay: WrappedDay?
    var activeDays: Int
    var funFact: WrappedFunFact
    var paymentSplit: WrappedPaymentSplit?
    var comparison: WrappedComparison?
    /// False when a festive recap was asked for a year we don't have a Diwali date for.
    var festiveDatesKnown: Bool
}

// MARK: - Payment hints

enum TaggedPayment: String, Equatable {
    case upi
    case cash
    case card
    case bank
}

/// CashLens has no payment-method field. UPI vs other is inferred only from
/// words the user typed in the title or notes. Untagged expenses are left out.
enum PaymentChannelHint {
    static func classify(title: String, notes: String?) -> TaggedPayment? {
        let combined = (title + " " + (notes ?? "")).lowercased()
        let tokens = Set(combined.split { !$0.isLetter && !$0.isNumber }.map(String.init))

        func has(_ word: String) -> Bool { tokens.contains(word) }
        func hasPhrase(_ phrase: String) -> Bool { combined.contains(phrase) }

        if has("upi") || has("gpay") || has("phonepe") || has("paytm")
            || hasPhrase("google pay") || hasPhrase("phone pe")
            || hasPhrase("amazon pay") || hasPhrase("bhim upi") {
            return .upi
        }
        if has("cash") {
            return .cash
        }
        if has("rupay") || has("mastercard")
            || hasPhrase("credit card") || hasPhrase("debit card") || hasPhrase("master card") {
            return .card
        }
        if has("neft") || has("imps") || has("rtgs") || has("netbanking") || hasPhrase("net banking") {
            return .bank
        }
        return nil
    }
}

// MARK: - Engine

/// Pure, on-device aggregation. Callers pass the expenses CashLens already has.
/// Nothing here reads the network or writes spending data anywhere.
enum WrappedEngine {
    static func build(
        expenses: [Expense],
        period: WrappedPeriod,
        now: Date,
        calendar: Calendar,
        currency: Expense.Currency,
        customCategoryNames: [UUID: String] = [:],
        customCategoryIcons: [UUID: String] = [:]
    ) -> WrappedStats {
        guard let window = WrappedCalendar.window(for: period, now: now, calendar: calendar) else {
            return unknownFestiveStats(now: now, currency: currency)
        }

        let filtered = expensesIn(window, expenses: expenses, currency: currency)
        let total = filtered.reduce(0) { $0 + $1.amount }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        let topCategory = rankCategories(
            filtered,
            total: total,
            customCategoryNames: customCategoryNames,
            customCategoryIcons: customCategoryIcons
        )
        let topMerchant = rankMerchants(filtered, total: total)
        let day = rankDays(filtered, total: total, calendar: calendar)
        let activeDays = Set(filtered.map { calendar.startOfDay(for: $0.date) }).count

        let fact = funFact(
            filtered: filtered,
            total: total,
            window: window,
            now: now,
            tomorrow: tomorrow,
            calendar: calendar,
            activeDays: activeDays
        )

        let split = paymentSplit(filtered, total: total)

        let comparison: WrappedComparison?
        if let previous = WrappedCalendar.previousWindow(for: window, calendar: calendar) {
            let previousTotal = expensesIn(previous, expenses: expenses, currency: currency)
                .reduce(0) { $0 + $1.amount }
            if previousTotal > 0 {
                comparison = WrappedComparison(
                    previousTotal: previousTotal,
                    previousTitle: previous.title,
                    changeFraction: (total - previousTotal) / previousTotal
                )
            } else if total > 0 {
                comparison = WrappedComparison(
                    previousTotal: 0,
                    previousTitle: previous.title,
                    changeFraction: nil
                )
            } else {
                comparison = nil
            }
        } else {
            comparison = nil
        }

        return WrappedStats(
            period: period,
            title: window.title,
            windowStart: window.start,
            windowEnd: window.end,
            currency: currency,
            transactionCount: filtered.count,
            total: total,
            topCategory: topCategory,
            topMerchant: topMerchant,
            biggestDay: day,
            activeDays: activeDays,
            funFact: fact,
            paymentSplit: split,
            comparison: comparison,
            festiveDatesKnown: true
        )
    }

    private static func unknownFestiveStats(now: Date, currency: Expense.Currency) -> WrappedStats {
        WrappedStats(
            period: .festiveSeason,
            title: "Diwali",
            windowStart: now,
            windowEnd: now,
            currency: currency,
            transactionCount: 0,
            total: 0,
            topCategory: nil,
            topMerchant: nil,
            biggestDay: nil,
            activeDays: 0,
            funFact: .empty,
            paymentSplit: nil,
            comparison: nil,
            festiveDatesKnown: false
        )
    }

    private static func expensesIn(_ window: WrappedWindow, expenses: [Expense], currency: Expense.Currency) -> [Expense] {
        expenses.filter { expense in
            expense.currency == currency
                && expense.amount.isFinite
                && expense.amount > 0
                && expense.date >= window.start
                && expense.date < window.end
        }
    }

    private static func rankCategories(
        _ expenses: [Expense],
        total: Double,
        customCategoryNames: [UUID: String],
        customCategoryIcons: [UUID: String]
    ) -> WrappedRank? {
        guard total > 0 else { return nil }

        struct Bucket {
            var amount: Double = 0
            var count: Int = 0
            var name: String
            var icon: String
            var builtin: Expense.Category?
        }

        var buckets: [String: Bucket] = [:]
        for expense in expenses {
            let key: String
            let name: String
            let icon: String
            let builtin: Expense.Category?
            if expense.category == .custom {
                if let id = expense.customCategoryId {
                    key = "custom:" + id.uuidString
                    let customName = customCategoryNames[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    name = customName.isEmpty ? "Custom" : customName
                    icon = customCategoryIcons[id] ?? "tag.fill"
                } else {
                    key = "custom"
                    name = "Custom"
                    icon = "tag.fill"
                }
                builtin = nil
            } else {
                key = expense.category.rawValue
                name = expense.category.displayName
                icon = expense.category.icon
                builtin = expense.category
            }

            var bucket = buckets[key] ?? Bucket(name: name, icon: icon, builtin: builtin)
            bucket.amount += expense.amount
            bucket.count += 1
            buckets[key] = bucket
        }

        guard let best = buckets.values.max(by: { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
            return lhs.name > rhs.name
        }) else { return nil }

        return WrappedRank(
            name: best.name,
            amount: best.amount,
            count: best.count,
            share: best.amount / total,
            icon: best.icon,
            builtinCategory: best.builtin
        )
    }

    private static func rankMerchants(_ expenses: [Expense], total: Double) -> WrappedRank? {
        guard total > 0 else { return nil }

        struct Bucket {
            var amount: Double = 0
            var count: Int = 0
            var display: String
        }

        var buckets: [String: Bucket] = [:]
        for expense in expenses {
            guard let key = merchantKey(expense.title) else { continue }
            let trimmed = expense.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            var bucket = buckets[key] ?? Bucket(display: trimmed)
            bucket.amount += expense.amount
            bucket.count += 1
            if bucket.display == bucket.display.lowercased(), trimmed != trimmed.lowercased() {
                bucket.display = trimmed
            }
            buckets[key] = bucket
        }

        guard let best = buckets.values.max(by: { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs.display > rhs.display
        }) else { return nil }

        return WrappedRank(
            name: best.display,
            amount: best.amount,
            count: best.count,
            share: best.amount / total,
            icon: merchantIcon(best.display),
            builtinCategory: nil
        )
    }

    private static func merchantKey(_ title: String) -> String? {
        let collapsed = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func merchantIcon(_ name: String) -> String {
        let tokens = Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if tokens.contains("swiggy") || tokens.contains("zomato") || tokens.contains("blinkit")
            || tokens.contains("zepto") || tokens.contains("instamart") {
            return "fork.knife"
        }
        if tokens.contains("ola") || tokens.contains("uber") || tokens.contains("rapido") {
            return "car.fill"
        }
        if tokens.contains("amazon") || tokens.contains("flipkart") || tokens.contains("myntra") {
            return "shippingbox.fill"
        }
        return "storefront.fill"
    }

    private static func rankDays(_ expenses: [Expense], total: Double, calendar: Calendar) -> WrappedDay? {
        guard total > 0, !expenses.isEmpty else { return nil }
        var totals: [Date: Double] = [:]
        for expense in expenses {
            let day = calendar.startOfDay(for: expense.date)
            totals[day, default: 0] += expense.amount
        }
        guard let best = totals.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }) else { return nil }

        return WrappedDay(
            date: best.key,
            amount: best.value,
            share: best.value / total,
            label: WrappedCalendar.dayLabel(for: best.key, calendar: calendar)
        )
    }

    private static func funFact(
        filtered: [Expense],
        total: Double,
        window: WrappedWindow,
        now: Date,
        tomorrow: Date,
        calendar: Calendar,
        activeDays: Int
    ) -> WrappedFunFact {
        if filtered.isEmpty {
            if window.start > now {
                return .upcoming(label: WrappedCalendar.shortDayLabel(for: window.start, calendar: calendar))
            }
            return .empty
        }
        if filtered.count < 3 {
            return .thin(count: filtered.count)
        }

        let streaks = streaks(
            expenses: filtered,
            window: window,
            tomorrow: tomorrow,
            calendar: calendar
        )
        let observedDays = max(streaks.observedDays, 1)

        let weekendAmount = filtered.reduce(0.0) { partial, expense in
            let weekday = calendar.component(.weekday, from: expense.date)
            return partial + ((weekday == 1 || weekday == 7) ? expense.amount : 0)
        }
        let weekendShare = total > 0 ? weekendAmount / total : 0

        let subscriptionAmount = filtered.reduce(0.0) { partial, expense in
            partial + (expense.isFromSubscription ? expense.amount : 0)
        }
        let subscriptionShare = total > 0 ? subscriptionAmount / total : 0

        let biggest = filtered.max { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
            return lhs.date > rhs.date
        }
        let singleShare = (biggest != nil && total > 0) ? biggest!.amount / total : 0

        if streaks.spend >= 5 {
            return .spendStreak(days: streaks.spend)
        }
        // A quiet run only leads when it covers at least half the days we could observe.
        // Ordinary gaps between expenses should not crowd out the other facts.
        if streaks.quiet >= 5, observedDays >= 8, streaks.quiet * 2 >= observedDays {
            return .noSpendStreak(days: streaks.quiet)
        }
        if weekendShare >= 0.6 {
            return .weekendHeavy(share: weekendShare)
        }
        if let biggest, singleShare >= 0.45 {
            let title = biggest.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return .singleBill(
                title: title.isEmpty ? "One bill" : title,
                amount: biggest.amount,
                share: singleShare
            )
        }
        if subscriptionShare >= 0.35 {
            return .subscriptions(share: subscriptionShare)
        }
        return .spread(activeDays: activeDays, observedDays: observedDays)
    }

    private static func streaks(
        expenses: [Expense],
        window: WrappedWindow,
        tomorrow: Date,
        calendar: Calendar
    ) -> (spend: Int, quiet: Int, observedDays: Int) {
        let spendDays = Set(expenses.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: window.start)
        let end = calendar.startOfDay(for: window.end)
        var spendRun = 0
        var quietRun = 0
        var bestSpend = 0
        var bestQuiet = 0
        var observed = 0

        while day < end {
            let spent = spendDays.contains(day)
            let inFuture = day >= tomorrow
            if inFuture && !spent {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                continue
            }
            observed += 1
            if spent {
                spendRun += 1
                quietRun = 0
            } else {
                quietRun += 1
                spendRun = 0
            }
            bestSpend = max(bestSpend, spendRun)
            bestQuiet = max(bestQuiet, quietRun)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (bestSpend, bestQuiet, observed)
    }

    /// Shown only when at least three expenses name a method and those cover
    /// at least 20% of the period. Otherwise the card would be a guess.
    private static func paymentSplit(_ expenses: [Expense], total: Double) -> WrappedPaymentSplit? {
        guard total > 0 else { return nil }
        var upiAmount = 0.0
        var otherAmount = 0.0
        var upiCount = 0
        var otherCount = 0

        for expense in expenses {
            switch PaymentChannelHint.classify(title: expense.title, notes: expense.notes) {
            case .upi:
                upiAmount += expense.amount
                upiCount += 1
            case .cash, .card, .bank:
                otherAmount += expense.amount
                otherCount += 1
            case nil:
                break
            }
        }

        let taggedCount = upiCount + otherCount
        let taggedAmount = upiAmount + otherAmount
        guard taggedCount >= 3, taggedAmount / total >= 0.2 else { return nil }

        return WrappedPaymentSplit(
            upiAmount: upiAmount,
            otherAmount: otherAmount,
            upiCount: upiCount,
            otherCount: otherCount,
            taggedCount: taggedCount,
            upiShareOfTagged: taggedAmount > 0 ? upiAmount / taggedAmount : 0
        )
    }
}
