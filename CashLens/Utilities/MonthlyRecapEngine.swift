import Foundation

/// Computes the "Monthly Recap" — the Spotify-Wrapped-style story
/// that summarizes the user's previous month in a handful of
/// glanceable cards. Pure value type, runs off-main, deterministic.
///
/// The output is a `MonthlyRecap` containing both the headline
/// numbers and a derived "award" — a single playful badge that
/// characterizes the month ("Restraint Master", "Big Splurger", etc).
/// The view layer renders pages in a fixed order; the engine only
/// returns nil pages when there genuinely isn't enough data (e.g.
/// no streak to report), and the view skips them.
///
/// Threading: this struct is `Sendable` and `compute(...)` does no
/// I/O — call it from `Task.detached` so the main actor isn't
/// blocked while the data flows through.
struct MonthlyRecap: Sendable, Equatable {
    let month: Date                  // first-of-the-month for the period covered
    let totalSpent: Double
    let previousMonthTotal: Double   // 0 if no prior data
    let expenseCount: Int

    /// Top category (display name + amount + percentage of total).
    /// `categoryName` falls back to "Other" if the user only logged uncategorised entries.
    let topCategoryName: String?
    let topCategoryAmount: Double
    let topCategoryShare: Double      // 0...1

    /// Single biggest expense of the month — title, amount, day.
    let biggestExpenseTitle: String?
    let biggestExpenseAmount: Double
    let biggestExpenseDay: Int        // 1...31

    /// Number of days during the month with **no** expenses.
    /// `nil` for the (vanishingly rare) case where every day had spend.
    let noSpendDays: Int

    /// Highest single-day spend total (sum across the day).
    let busiestDayAmount: Double
    let busiestDayDate: Date?         // exact date so the view can say "Friday the 14th"

    /// Derived "award" — a single playful characterisation of the
    /// month. Computed by `compute(...)` from the other fields.
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

    /// Convenience: the % delta vs prior month, signed.
    /// Returns nil when there's no prior data to compare against.
    var monthOverMonthDelta: Double? {
        guard previousMonthTotal > 0 else { return nil }
        return (totalSpent - previousMonthTotal) / previousMonthTotal
    }
}

/// Pure computation. Caller passes already-loaded expense arrays so
/// the engine never touches Core Data directly — keeps it Sendable
/// and trivially unit-testable.
enum MonthlyRecapEngine {
    /// `categoryDisplayName` lets the engine resolve custom category
    /// names without holding a Core Data reference — pass a closure
    /// that maps an `Expense` to its human label (same pattern the
    /// notification scheduler uses).
    static func compute(
        targetMonth: Date,
        thisMonthExpenses: [Expense],
        previousMonthExpenses: [Expense],
        categoryDisplayName: (Expense) -> String,
        calendar: Calendar = .current
    ) -> MonthlyRecap {
        let total = thisMonthExpenses.netTotal()
        let previousTotal = previousMonthExpenses.netTotal()

        // --- Category breakdown ---
        var byCategory: [String: Double] = [:]
        for e in thisMonthExpenses {
            guard !e.isRefund else { continue }
            let name = categoryDisplayName(e)
            byCategory[name, default: 0] += e.amount
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

        // --- No-spend days ---
        let monthInterval = calendar.dateInterval(of: .month, for: targetMonth)
        let totalDays: Int = {
            guard let monthInterval else { return 30 }
            // Days in the month (intervals are half-open, so we round)
            let days = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
            return days
        }()
        var daysWithSpend: Set<Int> = []
        for e in thisMonthExpenses where !e.isRefund {
            daysWithSpend.insert(calendar.component(.day, from: e.date))
        }
        let noSpend = max(0, totalDays - daysWithSpend.count)

        // --- Busiest day ---
        var dayTotals: [Date: Double] = [:]
        for e in thisMonthExpenses where !e.isRefund {
            let day = calendar.startOfDay(for: e.date)
            dayTotals[day, default: 0] += e.amount
        }
        let busiest = dayTotals.max { $0.value < $1.value }

        // --- Award derivation ---
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
            busiestDayAmount: busiest?.value ?? 0,
            busiestDayDate: busiest?.key,
            award: award
        )
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
