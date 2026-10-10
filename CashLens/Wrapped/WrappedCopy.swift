import Foundation

struct WrappedCardCopy: Equatable {
    var kicker: String
    var hero: String
    var line: String
    var footnote: String
    var icon: String?
}

/// Roast lines for the story cards. Amounts are included only when `showAmounts` is true,
/// which is how shared images stay amount-free unless the user opts in.
enum WrappedCopy {
    static func content(page: WrappedPageKind, stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        switch page {
        case .total:
            return total(stats, showAmounts: showAmounts)
        case .topCategory:
            return category(stats, showAmounts: showAmounts)
        case .topMerchant:
            return merchant(stats, showAmounts: showAmounts)
        case .biggestDay:
            return biggestDay(stats, showAmounts: showAmounts)
        case .funFact:
            return funFact(stats, showAmounts: showAmounts)
        case .paymentSplit:
            return payment(stats, showAmounts: showAmounts)
        case .closing:
            return closing(stats, showAmounts: showAmounts)
        }
    }

    static func percent(_ share: Double) -> String {
        let value = Int((share * 100).rounded())
        let clamped = min(100, max(0, value))
        return "\(clamped)%"
    }

    // MARK: Total

    private static func total(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        if !stats.festiveDatesKnown {
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "No date yet",
                line: "Diwali for this year isn't in CashLens yet, so there's no festive window to recap.",
                footnote: "This month still works.",
                icon: "calendar"
            )
        }

        if stats.transactionCount == 0 {
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "Nothing logged",
                line: emptyLine(stats),
                footnote: "",
                icon: "moon.stars.fill"
            )
        }

        let money = WrappedMoney.format(amount: stats.total, currency: stats.currency)
        let noun = stats.transactionCount == 1 ? "expense" : "expenses"
        return WrappedCardCopy(
            kicker: kicker(stats),
            hero: showAmounts ? money : "\(stats.transactionCount) \(noun)",
            line: totalLine(stats),
            footnote: comparisonLine(stats.comparison),
            icon: "sparkles"
        )
    }

    private static func emptyLine(_ stats: WrappedStats) -> String {
        if case .upcoming(let label) = stats.funFact {
            return "The window opens \(label). A recap needs a few expenses first."
        }
        if stats.period == .festiveSeason {
            return "The season is open and the list is empty. Either the wallet behaved, or the gifts are still in the cart."
        }
        return "Nothing logged this month. A blank page is still a result."
    }

    private static func totalLine(_ stats: WrappedStats) -> String {
        let noun = stats.transactionCount == 1 ? "expense" : "expenses"
        if stats.transactionCount < 3 {
            return "\(stats.transactionCount) \(noun). A short story, honestly told."
        }
        if stats.period == .festiveSeason {
            return "\(stats.transactionCount) \(noun) in the festive window. Diyas, deliveries, and the odd extra."
        }
        return "\(stats.transactionCount) \(noun). The month had opinions."
    }

    // MARK: Category

    private static func category(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        guard let category = stats.topCategory else {
            return missing(stats, icon: "square.grid.2x2")
        }
        let roast = categoryRoast(category.builtinCategory)
        let money = WrappedMoney.format(amount: category.amount, currency: stats.currency)
        if showAmounts {
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: money,
                line: "\(category.name). \(roast)",
                footnote: "\(percent(category.share)) of \(periodWord(stats.period)).",
                icon: category.icon
            )
        }
        return WrappedCardCopy(
            kicker: kicker(stats),
            hero: category.name,
            line: "\(percent(category.share)) of this \(periodWord(stats.period)). \(roast)",
            footnote: "",
            icon: category.icon
        )
    }

    private static func categoryRoast(_ category: Expense.Category?) -> String {
        switch category {
        case .food:
            return "Someone else did a lot of the cooking."
        case .groceries:
            return "The sabzi wala would recognize this list."
        case .transportation:
            return "Autos, cabs, and metro. Your step count is concerned."
        case .entertainment:
            return "The sofa has your shape now."
        case .shopping:
            return "Add to cart was a personality trait."
        case .utilities:
            return "Bills don't do festive discounts."
        case .health:
            return "This one was actually for you."
        case .education:
            return "Future-you can argue with the bill."
        case .travel:
            return "Bags packed. The group chat said let's go."
        case .other:
            return "A mysterious pile. Even you might need a minute."
        case .custom, nil:
            return "A category you named yourself, and it still won."
        }
    }

    // MARK: Merchant

    private static func merchant(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        guard let merchant = stats.topMerchant else {
            return missing(stats, icon: "storefront")
        }
        let roast = merchantRoast(merchant.name, count: merchant.count)
        let money = WrappedMoney.format(amount: merchant.amount, currency: stats.currency)
        if showAmounts {
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: money,
                line: "\(merchant.name). \(roast)",
                footnote: "\(percent(merchant.share)) of \(periodWord(stats.period)), \(times(merchant.count)).",
                icon: merchant.icon
            )
        }
        return WrappedCardCopy(
            kicker: kicker(stats),
            hero: merchant.name,
            line: "\(percent(merchant.share)) of this \(periodWord(stats.period)). \(roast)",
            footnote: merchant.count == 1 ? "Once." : "\(merchant.count) times.",
            icon: merchant.icon
        )
    }

    private static func merchantRoast(_ name: String, count: Int) -> String {
        let lowered = name.lowercased()
        let tokens = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func has(_ word: String) -> Bool { tokens.contains(word) }
        func hasPhrase(_ phrase: String) -> Bool { lowered.contains(phrase) }

        if has("swiggy") { return "Your kitchen misses you." }
        if has("zomato") { return "The tiffin box is decorative now." }
        if has("blinkit") || has("zepto") || has("instamart") {
            return "Ten-minute delivery, and a month-long pattern."
        }
        if has("ola") || has("uber") || has("rapido") {
            return "Your step count is taking this personally."
        }
        if has("amazon") || has("flipkart") || has("myntra") || has("ajio") || has("meesho") {
            return "The delivery person knows your floor."
        }
        if has("bigbasket") || has("jiomart") || has("dmart") || hasPhrase("big bazaar") {
            return "Doorstep groceries. Cooking remains optional."
        }
        if has("irctc") || has("indigo") || hasPhrase("make my trip") || has("makemytrip") {
            return "Tickets booked. The group chat said let's go."
        }
        return "It showed up \(times(count))."
    }

    // MARK: Day

    private static func biggestDay(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        guard let day = stats.biggestDay else {
            return missing(stats, icon: "calendar")
        }
        let money = WrappedMoney.format(amount: day.amount, currency: stats.currency)
        if showAmounts {
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: money,
                line: "\(day.label) carried \(percent(day.share)) of this \(periodWord(stats.period)).",
                footnote: "The busiest day.",
                icon: "calendar.badge.exclamationmark"
            )
        }
        return WrappedCardCopy(
            kicker: kicker(stats),
            hero: day.label,
            line: "The busiest day. \(percent(day.share)) of this \(periodWord(stats.period)) landed here.",
            footnote: "",
            icon: "calendar.badge.exclamationmark"
        )
    }

    // MARK: Fun fact

    private static func funFact(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        switch stats.funFact {
        case .upcoming(let label):
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "Not yet",
                line: "The window opens \(label). Check back when a few expenses land.",
                footnote: "",
                icon: "hourglass"
            )
        case .empty:
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "A blank page",
                line: emptyLine(stats),
                footnote: "",
                icon: "leaf.fill"
            )
        case .thin(let count):
            let noun = count == 1 ? "expense" : "expenses"
            let money = WrappedMoney.format(amount: stats.total, currency: stats.currency)
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: showAmounts ? money : "\(count) \(noun)",
                line: "Too few to make a fuss. The story stays honest.",
                footnote: "",
                icon: "text.alignleft"
            )
        case .noSpendStreak(let days):
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "\(days) quiet days",
                line: "In a row, with nothing logged. The wallet got a holiday.",
                footnote: "",
                icon: "pause.circle.fill"
            )
        case .spendStreak(let days):
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "\(days)-day streak",
                line: "Spending, every one of them. Consistency, of a kind.",
                footnote: "",
                icon: "flame.fill"
            )
        case .weekendHeavy(let share):
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: percent(share),
                line: "Weekends did the heavy lifting. Friday makes plans. Monday meets them.",
                footnote: "Share of spend, Saturday and Sunday.",
                icon: "sun.max.fill"
            )
        case .singleBill(let title, let amount, let share):
            let money = WrappedMoney.format(amount: amount, currency: stats.currency)
            if showAmounts {
                return WrappedCardCopy(
                    kicker: kicker(stats),
                    hero: money,
                    line: "\(title) was \(percent(share)) of everything. It didn't whisper.",
                    footnote: "The single biggest expense.",
                    icon: "exclamationmark.circle.fill"
                )
            }
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: title,
                line: "\(percent(share)) of everything was one bill. It didn't whisper.",
                footnote: "",
                icon: "exclamationmark.circle.fill"
            )
        case .subscriptions(let share):
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: percent(share),
                line: "Subscriptions. They renew even when the month gets away from you.",
                footnote: "",
                icon: "repeat"
            )
        case .spread(let activeDays, let observedDays):
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "\(activeDays) of \(observedDays)",
                line: "Days with something logged. Not a spree. A habit.",
                footnote: "",
                icon: "calendar"
            )
        }
    }

    // MARK: UPI

    private static func payment(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        guard let split = stats.paymentSplit else {
            return missing(stats, icon: "indianrupeesign")
        }
        let share = percent(split.upiShareOfTagged)
        let line: String
        if split.upiCount == 0 {
            line = "UPI never showed up in the title or notes. Whatever you tagged was something else."
        } else if split.upiShareOfTagged >= 0.6 {
            line = "UPI did the talking, at least on the payments you tagged."
        } else if split.upiShareOfTagged <= 0.25 {
            line = "UPI was the side character. Cards, cash, or transfers did more of the tagged spend."
        } else {
            line = "A split. UPI and everything else both showed up."
        }

        let footnote: String
        if showAmounts {
            let upi = WrappedMoney.format(amount: split.upiAmount, currency: stats.currency)
            let other = WrappedMoney.format(amount: split.otherAmount, currency: stats.currency)
            footnote = "UPI \(upi) · other tagged \(other). Untagged spend stays out."
        } else {
            footnote = "Only titles and notes that name a method are counted."
        }

        return WrappedCardCopy(
            kicker: kicker(stats),
            hero: "\(share) UPI",
            line: line,
            footnote: footnote,
            icon: "iphone"
        )
    }

    // MARK: Closing

    private static func closing(_ stats: WrappedStats, showAmounts: Bool) -> WrappedCardCopy {
        if stats.transactionCount == 0 {
            return WrappedCardCopy(
                kicker: kicker(stats),
                hero: "That's a wrap",
                line: "A quiet \(periodWord(stats.period)). Share it if you like. There's nothing sensitive on it.",
                footnote: "",
                icon: "checkmark.seal.fill"
            )
        }

        var pieces: [String] = []
        if showAmounts {
            let money = WrappedMoney.format(amount: stats.total, currency: stats.currency)
            pieces.append("\(money) in \(stats.title).")
        } else {
            pieces.append("\(stats.title), summed up.")
        }
        if let category = stats.topCategory {
            pieces.append("\(category.name) led.")
        }
        if let merchant = stats.topMerchant {
            pieces.append("\(merchant.name) kept showing up.")
        }
        if stats.period == .festiveSeason {
            pieces.append("The lights can stay.")
        }

        return WrappedCardCopy(
            kicker: kicker(stats),
            hero: "That's a wrap",
            line: pieces.joined(separator: " "),
            footnote: showAmounts ? "You chose to show amounts on this card." : "Amounts stay off this card.",
            icon: "checkmark.seal.fill"
        )
    }

    // MARK: Helpers

    private static func missing(_ stats: WrappedStats, icon: String) -> WrappedCardCopy {
        WrappedCardCopy(
            kicker: kicker(stats),
            hero: "Nothing here",
            line: "Not enough logged for this card.",
            footnote: "",
            icon: icon
        )
    }

    private static func kicker(_ stats: WrappedStats) -> String {
        "CASHLENS  ·  " + stats.title.uppercased(with: Locale(identifier: "en_IN"))
    }

    private static func periodWord(_ period: WrappedPeriod) -> String {
        period == .festiveSeason ? "season" : "month"
    }

    private static func times(_ count: Int) -> String {
        count == 1 ? "once" : "\(count) times"
    }

    private static func comparisonLine(_ comparison: WrappedComparison?) -> String {
        guard let comparison else { return "" }
        guard let change = comparison.changeFraction else {
            return "Nothing in \(comparison.previousTitle) to compare."
        }
        let pct = Int((abs(change) * 100).rounded())
        if abs(change) < 0.05 {
            return "About level with \(comparison.previousTitle)."
        }
        if change > 0 {
            return "Up \(pct)% from \(comparison.previousTitle)."
        }
        return "Down \(pct)% from \(comparison.previousTitle)."
    }
}
