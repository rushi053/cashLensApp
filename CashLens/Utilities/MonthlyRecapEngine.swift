import Foundation

/// Computes the "Monthly Recap" — the month-in-review story CashLens
/// surfaces at the start of every new month (a Today card for the
/// first few days, plus a permanent row in Insights). Pure value
/// type, runs off-main, deterministic.
///
/// v2 rebuild of the original engine (deleted with the old paged
/// recap screen, recovered from git history): same headline stats —
/// total vs previous month, top category, biggest expense, no-spend
/// days, busiest day, a derived "award" — plus two cheap additions
/// the new card layout wants: the month's best no-spend *streak* and
/// the month's subscription total (fixed vs variable framing).
///
/// Threading: `Sendable`, does no I/O — call `compute(...)` from
/// `Task.detached`. Callers must gate on
/// `ExpenseViewModel.waitUntilFullyHydrated()` first so the engine
/// sees the complete month, not the windowed launch slice.
struct MonthlyRecap: Sendable, Equatable {
    let month: Date                  // first-of-the-month for the period covered
    let totalSpent: Double
    let previousMonthTotal: Double   // 0 if no prior data
    let expenseCount: Int

    /// Top category (display name + amount + percentage of total).
    let topCategoryName: String?
    let topCategoryAmount: Double
    let topCategoryShare: Double      // 0...1

    /// Single biggest expense of the month — title, amount, day.
    let biggestExpenseTitle: String?
    let biggestExpenseAmount: Double
    let biggestExpenseDay: Int        // 1...31

    /// Number of days during the month with **no** expenses.
    let noSpendDays: Int

    /// Longest run of consecutive no-spend days inside the month.
    let bestNoSpendStreak: Int

    /// Highest single-day spend total (sum across the day).
    let busiestDayAmount: Double
    let busiestDayDate: Date?         // exact date so the view can say "Friday the 14th"

    /// Total of subscription-generated expenses in the month — the
    /// "fixed costs" line on the recap.
    let subscriptionTotal: Double

    /// Derived "award" — a single calm characterisation of the month.
    let award: Award

    enum Award: String, Sendable, Equatable {
        case restraintMaster        // significant decrease vs prior month
        case onTheRise              // moderate increase (10-30%)
        case bigSpender             // significant increase (>30%)
        case steady                 // within ±10% of prior month
        case strongStart            // no prior month data; first full month
        case wellRounded            // most balanced category share
        case oneCategoryMonth       // one category > 60% of total

        var title: String {
            switch self {
            case .restraintMaster:   return "Restraint Master"
            case .onTheRise:         return "Spending Climber"
            case .bigSpender:        return "Big Spender"
            case .steady:            return "Steady Hand"
            case .strongStart:       return "Strong Start"
            case .wellRounded:       return "Well Rounded"
            case .oneCategoryMonth:  return "Single-Lane Spender"
            }
        }

        var subtitle: String {
            switch self {
            case .restraintMaster:   return "You spent meaningfully less than last month."
            case .onTheRise:         return "Spending edged up — a calm increase."
            case .bigSpender:        return "Spending climbed notably vs last month."
            case .steady:            return "You held the line within 10% of last month."
            case .strongStart:       return "Your first full month of tracking is logged."
            case .wellRounded:       return "Your spending spread evenly across categories."
            case .oneCategoryMonth:  return "One category dominated your spend this month."
            }
        }

        var symbol: String {
            switch self {
            case .restraintMaster:   return "leaf.fill"
            case .onTheRise:         return "arrow.up.right"
            case .bigSpender:        return "flame.fill"
            case .steady:            return "scale.3d"
            case .strongStart:       return "sparkles"
            case .wellRounded:       return "circle.hexagongrid.fill"
            case .oneCategoryMonth:  return "target"
            }
        }
    }

    /// The % delta vs prior month, signed. `nil` when there's no
    /// prior data to compare against.
    var monthOverMonthDelta: Double? {
        guard previousMonthTotal > 0 else { return nil }
        return (totalSpent - previousMonthTotal) / previousMonthTotal
    }

    /// True when there's enough substance to show the recap at all.
    var isWorthShowing: Bool { expenseCount > 0 }
}

/// Pure computation. Caller passes already-loaded expense arrays so
/// the engine never touches Core Data directly — keeps it Sendable
/// and trivially unit-testable.
enum MonthlyRecapEngine {

    /// Number of days at the start of a month during which the Today
    /// recap card is offered. Shared by TodayView (card visibility)
    /// so the window lives in exactly one place.
    static let todayCardWindowDays = 5

    /// Build a recap for the month containing `targetMonth`.
    /// `customCategoryNames` maps custom-category ids to display names
    /// (a plain dictionary, not a closure, so the call site can hand
    /// it across the `Task.detached` boundary safely).
    static func compute(
        targetMonth: Date,
        thisMonthExpenses: [Expense],
        previousMonthExpenses: [Expense],
        customCategoryNames: [UUID: String],
        calendar: Calendar = .current
    ) -> MonthlyRecap {
        let total = thisMonthExpenses.netTotal()
        let previousTotal = previousMonthExpenses.netTotal()

        func displayName(for e: Expense) -> String {
            if e.category == .custom, let id = e.customCategoryId, let name = customCategoryNames[id] {
                return name
            }
            return e.category.displayName
        }

        // --- Category breakdown ---
        var byCategory: [String: Double] = [:]
        for e in thisMonthExpenses where !e.isRefund {
            byCategory[displayName(for: e), default: 0] += e.amount
        }
        let topPair = byCategory.max { $0.value < $1.value }
        let topName = topPair?.key
        let topAmount = topPair?.value ?? 0
        let topShare = total > 0 ? (topAmount / total) : 0

        // --- Biggest single expense ---
        let biggest = thisMonthExpenses
            .filter { !$0.isRefund }
            .max { $0.amount < $1.amount }
        let biggestDay = biggest.map {
            calendar.component(.day, from: $0.date)
        } ?? 0

        // --- No-spend days + best in-month streak ---
        let monthInterval = calendar.dateInterval(of: .month, for: targetMonth)
        let totalDays: Int = {
            guard let monthInterval else { return 30 }
            return calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
        }()
        var daysWithSpend: Set<Int> = []
        for e in thisMonthExpenses where !e.isRefund {
            daysWithSpend.insert(calendar.component(.day, from: e.date))
        }
        let noSpend = max(0, totalDays - daysWithSpend.count)

        var bestStreak = 0
        var run = 0
        for day in 1...max(totalDays, 1) {
            if daysWithSpend.contains(day) {
                bestStreak = max(bestStreak, run)
                run = 0
            } else {
                run += 1
            }
        }
        bestStreak = max(bestStreak, run)

        // --- Busiest day ---
        var dayTotals: [Date: Double] = [:]
        for e in thisMonthExpenses where !e.isRefund {
            dayTotals[calendar.startOfDay(for: e.date), default: 0] += e.amount
        }
        let busiest = dayTotals.max { $0.value < $1.value }

        // --- Subscription total (fixed costs) ---
        let subscriptionTotal = thisMonthExpenses
            .filter { $0.isFromSubscription && !$0.isRefund }
            .reduce(0) { $0 + $1.amount }

        let award = deriveAward(
            previousTotal: previousTotal,
            currentTotal: total,
            topShare: topShare,
            categoryCount: byCategory.keys.count
        )

        return MonthlyRecap(
            month: monthInterval?.start ?? targetMonth,
            totalSpent: total,
            previousMonthTotal: previousTotal,
            expenseCount: thisMonthExpenses.count,
            topCategoryName: topName,
            topCategoryAmount: topAmount,
            topCategoryShare: topShare,
            biggestExpenseTitle: biggest?.title,
            biggestExpenseAmount: biggest?.amount ?? 0,
            biggestExpenseDay: biggestDay,
            noSpendDays: noSpend,
            bestNoSpendStreak: bestStreak,
            busiestDayAmount: busiest?.value ?? 0,
            busiestDayDate: busiest?.key,
            subscriptionTotal: subscriptionTotal,
            award: award
        )
    }

    /// Convenience: slice a full expense array into (target month,
    /// previous month) and compute. `month` can be any date inside the
    /// target month.
    static func compute(
        month: Date,
        allExpenses: [Expense],
        customCategoryNames: [UUID: String],
        calendar: Calendar = .current
    ) -> MonthlyRecap? {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let prevAnchor = calendar.date(byAdding: .month, value: -1, to: interval.start),
              let prevInterval = calendar.dateInterval(of: .month, for: prevAnchor) else { return nil }

        let thisMonth = allExpenses.filter { $0.date >= interval.start && $0.date < interval.end }
        let prevMonth = allExpenses.filter { $0.date >= prevInterval.start && $0.date < prevInterval.end }

        return compute(
            targetMonth: interval.start,
            thisMonthExpenses: thisMonth,
            previousMonthExpenses: prevMonth,
            customCategoryNames: customCategoryNames,
            calendar: calendar
        )
    }

    /// Stable "yyyy-MM" key for a month — used to persist "recap seen"
    /// state in UserDefaults.
    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    private static func deriveAward(
        previousTotal: Double,
        currentTotal: Double,
        topShare: Double,
        categoryCount: Int
    ) -> MonthlyRecap.Award {
        // No prior data → "Strong Start" (welcoming, not a verdict).
        guard previousTotal > 0 else { return .strongStart }

        let delta = (currentTotal - previousTotal) / previousTotal

        // Significant decrease ≥ 15% — celebrate restraint.
        if delta <= -0.15 { return .restraintMaster }

        // Significant increase ≥ 30% — call it out as "Big Spender".
        if delta >= 0.30 { return .bigSpender }

        // Moderate increase 10-30% — "On The Rise" (calm framing).
        if delta >= 0.10 { return .onTheRise }

        // Within ±10% and a single category > 60% → "Single-Lane".
        if topShare > 0.60 { return .oneCategoryMonth }

        // Within ±10% and at least 4 distinct categories → "Well Rounded".
        if categoryCount >= 4 { return .wellRounded }

        // Default fallback — held the line.
        return .steady
    }
}
