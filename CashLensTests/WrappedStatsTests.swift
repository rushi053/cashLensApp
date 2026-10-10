import Foundation
import Testing
@testable import CashLens

struct WrappedStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_IN")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    private func expense(
        _ title: String,
        _ amount: Double,
        _ month: Int,
        _ day: Int,
        _ category: Expense.Category = .food,
        notes: String? = nil,
        currency: Expense.Currency = .inr,
        customCategoryId: UUID? = nil,
        subscription: Bool = false,
        year: Int = 2026
    ) -> Expense {
        Expense(
            title: title,
            amount: amount,
            currency: currency,
            date: date(year, month, day),
            category: category,
            notes: notes,
            customCategoryId: customCategoryId,
            isFromSubscription: subscription
        )
    }

    // MARK: - Indian currency

    @Test func indianGrouping() {
        #expect(IndianCurrencyFormat.formatINR(0, includePaise: false) == "₹0")
        #expect(IndianCurrencyFormat.formatINR(0, includePaise: true) == "₹0.00")
        #expect(IndianCurrencyFormat.formatINR(999, includePaise: false) == "₹999")
        #expect(IndianCurrencyFormat.formatINR(1000, includePaise: false) == "₹1,000")
        #expect(IndianCurrencyFormat.formatINR(10000, includePaise: false) == "₹10,000")
        #expect(IndianCurrencyFormat.formatINR(100000, includePaise: false) == "₹1,00,000")
        #expect(IndianCurrencyFormat.formatINR(123456, includePaise: false) == "₹1,23,456")
        #expect(IndianCurrencyFormat.formatINR(1234567, includePaise: false) == "₹12,34,567")
        #expect(IndianCurrencyFormat.formatINR(10000000, includePaise: false) == "₹1,00,00,000")
        #expect(IndianCurrencyFormat.formatINR(123456.5, includePaise: true) == "₹1,23,456.50")
        #expect(IndianCurrencyFormat.formatINR(1234.5, includePaise: true) == "₹1,234.50")
        #expect(IndianCurrencyFormat.formatINR(999.5, includePaise: false) == "₹1,000")
        #expect(IndianCurrencyFormat.formatINR(-1234.5, includePaise: true) == "-₹1,234.50")
        #expect(IndianCurrencyFormat.formatINR(Double.nan) == "₹0")
        #expect(IndianCurrencyFormat.formatINR(Double.infinity) == "₹0")
    }

    @Test func storyAmountsDropZeroPaiseAndKeepWesternGrouping() {
        #expect(WrappedMoney.format(amount: 123456, currency: .inr) == "₹1,23,456")
        #expect(WrappedMoney.format(amount: 1234.5, currency: .inr) == "₹1,234.50")
        #expect(WrappedMoney.format(amount: 123456, currency: .usd) == "$123,456")
        #expect(WrappedMoney.format(amount: 1234567.25, currency: .usd) == "$1,234,567.25")
    }

    @Test func digitGroupingHelper() {
        #expect(IndianCurrencyFormat.groupIndianDigits("123456") == "1,23,456")
        #expect(IndianCurrencyFormat.groupIndianDigits("10000000") == "1,00,00,000")
        #expect(IndianCurrencyFormat.groupIndianDigits("1000") == "1,000")
        #expect(IndianCurrencyFormat.groupIndianDigits("42") == "42")
    }

    // MARK: - Periods

    @Test func october2026WindowAndDiwaliWindow() {
        let now = date(2026, 10, 10)
        let month = WrappedCalendar.monthWindow(containing: now, calendar: calendar)
        expectDay(month.start, 2026, 10, 1)
        expectDay(month.end, 2026, 11, 1)

        let festive = WrappedCalendar.festiveWindow(relevantTo: now, calendar: calendar)
        expectDay(festive?.start, 2026, 10, 18)
        expectDay(festive?.end, 2026, 11, 13)
        expectDay(festive?.anchor, 2026, 11, 8)
        #expect(festive?.title == "Diwali 2026")
    }

    @Test func festiveSeasonPicksTheRelevantYear() {
        let earlyOctober = WrappedCalendar.festiveWindow(relevantTo: date(2026, 10, 10), calendar: calendar)
        expectDay(earlyOctober?.anchor, 2026, 11, 8)

        let september = WrappedCalendar.festiveWindow(relevantTo: date(2026, 9, 1), calendar: calendar)
        expectDay(september?.anchor, 2025, 10, 20)

        let nextJanuary = WrappedCalendar.festiveWindow(relevantTo: date(2027, 1, 15), calendar: calendar)
        expectDay(nextJanuary?.anchor, 2026, 11, 8)

        let duringDiwali = WrappedCalendar.festiveWindow(relevantTo: date(2026, 11, 8, 21), calendar: calendar)
        expectDay(duringDiwali?.anchor, 2026, 11, 8)

        let unknown = WrappedCalendar.festiveWindow(relevantTo: date(2032, 6, 1), calendar: calendar)
        #expect(unknown == nil)
    }

    // MARK: - Stats

    @Test func monthStatsFromExpenses() throws {
        let stats = octoberStats()

        #expect(stats.transactionCount == 7)
        #expect(stats.total == 6800.0)
        #expect(stats.topCategory?.name == "Groceries")
        #expect(stats.topCategory?.amount == 2600.0)
        #expect(stats.topMerchant?.name == "Swiggy")
        #expect(stats.topMerchant?.count == 3)
        #expect(stats.topMerchant?.amount == 2400.0)
        #expect(stats.activeDays == 7)
        expectDay(stats.biggestDay?.date, 2026, 10, 5)
        #expect(stats.biggestDay?.amount == 2000.0)

        let split = try #require(stats.paymentSplit)
        #expect(split.upiCount == 4)
        #expect(split.otherCount == 2)
        #expect(split.upiAmount == 2700.0)
        #expect(split.otherAmount == 3500.0)
        #expect(abs(split.upiShareOfTagged - (2700.0 / 6200.0)) < 0.0001)

        #expect(stats.comparison?.previousTotal == 3400.0)
        #expect(stats.comparison?.previousTitle == "September 2026")
        #expect(stats.comparison?.changeFraction == 1.0)

        if case .spendStreak(let days) = stats.funFact {
            #expect(days == 5)
        } else {
            Issue.record("Expected a 5-day spend streak, got \(stats.funFact)")
        }

        let pages = WrappedScript.pages(for: stats)
        #expect(pages == [.total, .topCategory, .topMerchant, .biggestDay, .funFact, .paymentSplit, .closing])
        #expect((5...8).contains(pages.count))
    }

    @Test func paymentCardIsOmittedWithoutMethodWords() {
        let expenses = [
            expense("Swiggy", 800, 10, 2),
            expense("Swiggy", 900, 10, 3),
            expense("Milk", 200, 10, 4, .groceries),
            expense("Uber", 300, 10, 6, .transportation)
        ]
        let stats = WrappedEngine.build(
            expenses: expenses,
            period: .thisMonth,
            now: date(2026, 10, 28),
            calendar: calendar,
            currency: .inr
        )
        #expect(stats.paymentSplit == nil)
        #expect(!WrappedScript.pages(for: stats).contains(.paymentSplit))
        #expect((5...8).contains(WrappedScript.pages(for: stats).count))
    }

    @Test func festiveWindowBoundaries() {
        let expenses = [
            expense("Diyas", 500, 10, 17),
            expense("Sweets", 800, 10, 18, notes: "UPI"),
            expense("Gifts", 2000, 11, 8, .shopping, notes: "PhonePe"),
            expense("Travel home", 1500, 11, 12, .travel, notes: "UPI"),
            expense("After", 900, 11, 13)
        ]
        let stats = WrappedEngine.build(
            expenses: expenses,
            period: .festiveSeason,
            now: date(2026, 11, 9),
            calendar: calendar,
            currency: .inr
        )
        #expect(stats.title == "Diwali 2026")
        #expect(stats.transactionCount == 3)
        #expect(stats.total == 4300.0)
        #expect(stats.festiveDatesKnown)
    }

    @Test func upcomingFestiveCopyHasNoAmount() {
        let stats = WrappedEngine.build(
            expenses: [],
            period: .festiveSeason,
            now: date(2026, 10, 10),
            calendar: calendar,
            currency: .inr
        )
        #expect(stats.transactionCount == 0)
        if case .upcoming(let label) = stats.funFact {
            #expect(label.contains("18"))
            #expect(label.contains("Oct"))
        } else {
            Issue.record("Expected an upcoming festive window")
        }
        let copy = WrappedCopy.content(page: .total, stats: stats, showAmounts: true)
        #expect(!copy.hero.contains("₹"))
        #expect(!copy.line.contains("₹"))
    }

    @Test func hiddenShareCopyOmitsRupees() {
        let stats = octoberStats()
        let pages = WrappedScript.pages(for: stats)
        for page in pages {
            let copy = WrappedCopy.content(page: page, stats: stats, showAmounts: false)
            let text = [copy.kicker, copy.hero, copy.line, copy.footnote].joined(separator: " ")
            #expect(!text.contains("₹"))
            #expect(!text.contains("6,800"))
            #expect(!text.contains("2,400"))
            #expect(!text.contains("2,600"))
            #expect(!text.contains("2,000"))
        }

        let shown = WrappedCopy.content(page: .total, stats: stats, showAmounts: true)
        #expect(shown.hero == "₹6,800")
        let merchant = WrappedCopy.content(page: .topMerchant, stats: stats, showAmounts: true)
        #expect(merchant.hero == "₹2,400")
        #expect(merchant.line.contains("kitchen misses you"))
    }

    @Test func customCategoryAndIgnoredRows() {
        let pets = UUID()
        let expenses = [
            expense("Vet", 5000, 10, 3, .custom, customCategoryId: pets),
            expense("Tea", 100, 10, 4),
            expense("Dollars", 9999, 10, 5, currency: .usd),
            expense("Refund", -50, 10, 6),
            expense("Zero", 0, 10, 6)
        ]
        let stats = WrappedEngine.build(
            expenses: expenses,
            period: .thisMonth,
            now: date(2026, 10, 10),
            calendar: calendar,
            currency: .inr,
            customCategoryNames: [pets: "Pets"],
            customCategoryIcons: [pets: "pawprint.fill"]
        )
        #expect(stats.transactionCount == 2)
        #expect(stats.total == 5100.0)
        #expect(stats.topCategory?.name == "Pets")
        #expect(stats.topCategory?.icon == "pawprint.fill")
        #expect(stats.topCategory?.builtinCategory == nil)
    }

    @Test func quietStreakAndThinData() {
        let quiet = WrappedEngine.build(
            expenses: [
                expense("A", 100, 10, 1),
                expense("B", 100, 10, 1),
                expense("C", 100, 10, 1)
            ],
            period: .thisMonth,
            now: date(2026, 10, 12),
            calendar: calendar,
            currency: .inr
        )
        if case .noSpendStreak(let days) = quiet.funFact {
            #expect(days >= 5)
        } else {
            Issue.record("Expected a quiet streak, got \(quiet.funFact)")
        }

        let one = WrappedEngine.build(
            expenses: [expense("Coffee", 80, 10, 2)],
            period: .thisMonth,
            now: date(2026, 10, 10),
            calendar: calendar,
            currency: .inr
        )
        if case .thin(let count) = one.funFact {
            #expect(count == 1)
        } else {
            Issue.record("Expected thin data")
        }
        let pages = WrappedScript.pages(for: one)
        #expect(pages.contains(.total))
        #expect(pages.contains(.closing))
        #expect(pages.count <= 8)
    }

    @Test func unknownDiwaliYearDoesNotInventAWindow() {
        let stats = WrappedEngine.build(
            expenses: [expense("Gift", 100, 6, 2, year: 2032)],
            period: .festiveSeason,
            now: date(2032, 6, 2),
            calendar: calendar,
            currency: .inr
        )
        #expect(!stats.festiveDatesKnown)
        #expect(stats.transactionCount == 0)
        let copy = WrappedCopy.content(page: .total, stats: stats, showAmounts: true)
        #expect(copy.line.contains("isn't in CashLens yet"))
    }

    @Test func paymentHintTokens() {
        #expect(PaymentChannelHint.classify(title: "Swiggy", notes: "paid by UPI") == .upi)
        #expect(PaymentChannelHint.classify(title: "PhonePe recharge", notes: nil) == .upi)
        #expect(PaymentChannelHint.classify(title: "Groceries", notes: "cash") == .cash)
        #expect(PaymentChannelHint.classify(title: "Laptop", notes: "debit card") == .card)
        #expect(PaymentChannelHint.classify(title: "Rent", notes: "NEFT") == .bank)
        #expect(PaymentChannelHint.classify(title: "Cola", notes: nil) == nil)
        #expect(PaymentChannelHint.classify(title: "Cashback", notes: nil) == nil)
        #expect(PaymentChannelHint.classify(title: "Occupation", notes: nil) == nil)
    }

    private func octoberStats() -> WrappedStats {
        let expenses = [
            expense("Swiggy", 800, 10, 2, notes: "UPI"),
            expense("Swiggy", 900, 10, 3, notes: "gpay"),
            expense("swiggy", 700, 10, 4, notes: "PhonePe"),
            expense("Big Bazaar", 2000, 10, 5, .groceries, notes: "cash"),
            expense("Uber", 300, 10, 6, .transportation, notes: "UPI"),
            expense("Amazon", 1500, 10, 10, .shopping, notes: "debit card"),
            expense("DMart", 600, 10, 20, .groceries),
            expense("Rent", 3400, 9, 4, .utilities),
            expense("USD noise", 5000, 10, 8, currency: .usd)
        ]
        return WrappedEngine.build(
            expenses: expenses,
            period: .thisMonth,
            now: date(2026, 10, 28),
            calendar: calendar,
            currency: .inr
        )
    }

    private func expectDay(_ date: Date?, _ year: Int, _ month: Int, _ day: Int) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date ?? Date(timeIntervalSince1970: 0))
        #expect(parts.year == year)
        #expect(parts.month == month)
        #expect(parts.day == day)
    }
}
