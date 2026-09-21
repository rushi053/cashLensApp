import Foundation

/// Computes "no-spend" streak metrics from a list of expenses.
///
/// A no-spend day is a calendar day with **zero** logged spending — i.e. no
/// expense rows on that day. Days dated in the future are ignored.
///
/// All functions are pure value-type math so they're safe to call from any
/// context. Computation is `O(N)` over the in-window expense set.
enum StreakCalculator {

    /// Snapshot of the user's no-spend streak metrics for the current month.
    struct StreakSummary: Equatable {
        /// Days in the current month with zero spending so far.
        let noSpendDaysThisMonth: Int
        /// Days elapsed in the current month so far (>= 1). Useful for
        /// "5 of 26 days" framing without leaking partial-month math.
        let daysElapsedThisMonth: Int
        /// The current run of consecutive no-spend days ending today (or
        /// yesterday if today has spending). 0 if today has spending.
        let currentStreak: Int
        /// The longest no-spend streak found in the lookback window.
        let bestStreak: Int

        /// True when there's enough signal to display the chip. We hide it
        /// for the first couple of days of any new install so it doesn't
        /// celebrate a "10-day streak" on day 2 because the user has no
        /// history yet.
        var isMeaningful: Bool {
            // Show once we have at least 3 days of "history" (elapsed) AND
            // either a non-trivial monthly count or a notable current streak.
            daysElapsedThisMonth >= 3 && (noSpendDaysThisMonth >= 1 || currentStreak >= 1)
        }
    }

    /// Build a streak summary from `expenses`. Pass the full live array; this
    /// function does its own date filtering.
    static func summary(
        from expenses: [Expense],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakSummary {
        let today = calendar.startOfDay(for: now)
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else {
            return StreakSummary(noSpendDaysThisMonth: 0, daysElapsedThisMonth: 1, currentStreak: 0, bestStreak: 0)
        }

        // Days elapsed *up to and including* today within the current month.
        let daysElapsed = max(1, (calendar.dateComponents([.day], from: monthStart, to: today).day ?? 0) + 1)

        // Build a "spent on this day?" set for the current month plus a small
        // buffer behind it (so the current streak can extend backwards past
        // the month boundary if applicable).
        guard let lookbackStart = calendar.date(byAdding: .day, value: -90, to: today) else {
            return StreakSummary(noSpendDaysThisMonth: 0, daysElapsedThisMonth: daysElapsed, currentStreak: 0, bestStreak: 0)
        }

        var spentOn: Set<Date> = []
        for e in expenses where e.date >= lookbackStart && e.date <= now {
            spentOn.insert(calendar.startOfDay(for: e.date))
        }

        // Count no-spend days in the current month (only past + today).
        var monthCount = 0
        var cursor = monthStart
        while cursor <= today {
            if !spentOn.contains(cursor) {
                monthCount += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // Current streak: walk backwards from today as long as the day has
        // no spending. If today has spending, the current streak is zero —
        // but we still surface the longest run found in the lookback window
        // as `bestStreak`.
        var current = 0
        var walk = today
        while !spentOn.contains(walk) && walk >= lookbackStart {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: walk) else { break }
            walk = prev
        }

        // Best streak in the lookback window (single linear scan).
        var best = 0
        var run = 0
        var scan = lookbackStart
        while scan <= today {
            if spentOn.contains(scan) {
                if run > best { best = run }
                run = 0
            } else {
                run += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: scan) else { break }
            scan = next
        }
        if run > best { best = run }

        return StreakSummary(
            noSpendDaysThisMonth: monthCount,
            daysElapsedThisMonth: daysElapsed,
            currentStreak: current,
            bestStreak: best
        )
    }
}
