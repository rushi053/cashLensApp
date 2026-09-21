import Foundation

/// Pro-tier statistical insights layered on top of the base `StatisticsCalculator`.
///
/// These functions are pure, synchronous, and side-effect free so they can be
/// invoked from detached tasks alongside the existing aggregation pipeline in
/// `StatisticsView`. They deliberately accept already-filtered expense snapshots
/// so the caller controls which category / date-range subset is being analyzed.
enum AdvancedStatsCalculator {

    // MARK: - Daily Pace

    /// Average amount spent per elapsed day in the selected period.
    /// "Elapsed" caps at today so a 31-day month doesn't dilute the average on day 5.
    struct DailyPace {
        /// Average spend per elapsed day in the current period.
        let dailyAverage: Double
        /// Average spend per day over the prior same-length window.
        let previousDailyAverage: Double
        /// % change vs. the previous daily average. `nil` when there is no prior data.
        let changePercent: Double?
        /// Number of days counted toward `dailyAverage` (>= 1).
        let daysElapsed: Int
    }

    static func dailyPace(
        currentTotal: Double,
        previousTotal: Double,
        rangeStart: Date,
        rangeEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPace {
        let startDay = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: rangeEnd)
        let today = calendar.startOfDay(for: now)

        // Cap the "current" window at today so future days don't deflate the average.
        let cappedEnd = min(endDay, today)
        let elapsedDays = max(1, (calendar.dateComponents([.day], from: startDay, to: cappedEnd).day ?? 0) + 1)

        // Previous window length mirrors the full selected range so comparisons stay fair.
        let rangeDays = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)

        let dailyAvg = currentTotal / Double(elapsedDays)
        let prevDailyAvg = previousTotal / Double(rangeDays)

        let change: Double?
        if prevDailyAvg > 0 {
            change = ((dailyAvg - prevDailyAvg) / prevDailyAvg) * 100
        } else {
            change = nil
        }

        return DailyPace(
            dailyAverage: dailyAvg,
            previousDailyAverage: prevDailyAvg,
            changePercent: change,
            daysElapsed: elapsedDays
        )
    }

    // MARK: - Spending Velocity

    /// Projects end-of-period total based on current pace and compares to previous period.
    struct Velocity {
        enum State {
            /// Range is still in progress — numbers are a projection.
            case projecting
            /// Range has already ended — numbers are final.
            case completed
        }

        let state: State
        /// Amount actually spent so far.
        let currentTotal: Double
        /// Projected total by end of range (equals `currentTotal` when completed).
        let projectedTotal: Double
        /// Actual total for the prior same-length period.
        let previousTotal: Double
        /// Projected vs previous, as a signed percentage. `nil` when previous was zero.
        let changePercent: Double?
        /// 0...1 — how far through the range we are. 1.0 when completed.
        let progress: Double
    }

    static func velocity(
        currentTotal: Double,
        previousTotal: Double,
        rangeStart: Date,
        rangeEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Velocity {
        let startDay = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: rangeEnd)
        let today = calendar.startOfDay(for: now)

        let totalDays = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)

        // Already ended
        if today > endDay {
            let change: Double? = previousTotal > 0 ? ((currentTotal - previousTotal) / previousTotal) * 100 : nil
            return Velocity(
                state: .completed,
                currentTotal: currentTotal,
                projectedTotal: currentTotal,
                previousTotal: previousTotal,
                changePercent: change,
                progress: 1.0
            )
        }

        // Still in progress — project linearly from current pace.
        let cappedEnd = min(endDay, today)
        let elapsedDays = max(1, (calendar.dateComponents([.day], from: startDay, to: cappedEnd).day ?? 0) + 1)
        let progress = min(1.0, Double(elapsedDays) / Double(totalDays))

        let projected: Double
        if progress > 0 {
            projected = currentTotal / progress
        } else {
            projected = currentTotal
        }

        let change: Double? = previousTotal > 0 ? ((projected - previousTotal) / previousTotal) * 100 : nil

        return Velocity(
            state: .projecting,
            currentTotal: currentTotal,
            projectedTotal: projected,
            previousTotal: previousTotal,
            changePercent: change,
            progress: progress
        )
    }

    // MARK: - Year-over-Year

    /// Month-by-month comparison between current year and previous year.
    struct YearOverYearPoint: Identifiable, Equatable {
        let id: Date
        /// First-of-month anchor in the *current* year for this data point.
        let monthAnchor: Date
        /// Total for this month in the current year.
        let currentAmount: Double
        /// Total for the same month one year earlier.
        let previousAmount: Double
    }

    /// Builds a trailing `count`-month window anchored on the month containing `referenceDate`.
    ///
    /// This function walks the full expense set once and buckets by `(year, month)` so it's
    /// O(n) regardless of the window length.
    static func yearOverYear(
        allExpenses: [Expense],
        referenceDate: Date = Date(),
        count: Int = 6,
        calendar: Calendar = .current
    ) -> [YearOverYearPoint] {
        guard count > 0 else { return [] }

        // Build anchors for the trailing `count` months ending on the ref month.
        guard let refMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) else {
            return []
        }

        var anchors: [Date] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            if let d = calendar.date(byAdding: .month, value: -offset, to: refMonthStart) {
                anchors.append(d)
            }
        }
        guard !anchors.isEmpty else { return [] }

        // Window of interest: we want current year months AND same month prior year.
        let windowStart = calendar.date(byAdding: .year, value: -1, to: anchors.first!) ?? anchors.first!
        let lastMonthExclusive = calendar.date(byAdding: .month, value: 1, to: anchors.last!) ?? anchors.last!

        var totalsByMonth: [Date: Double] = [:]
        for expense in allExpenses where expense.date >= windowStart && expense.date < lastMonthExclusive {
            if let key = calendar.date(from: calendar.dateComponents([.year, .month], from: expense.date)) {
                totalsByMonth[key, default: 0] += expense.signedAmount
            }
        }

        return anchors.map { anchor in
            let prevAnchor = calendar.date(byAdding: .year, value: -1, to: anchor) ?? anchor
            return YearOverYearPoint(
                id: anchor,
                monthAnchor: anchor,
                currentAmount: totalsByMonth[anchor] ?? 0,
                previousAmount: totalsByMonth[prevAnchor] ?? 0
            )
        }
    }

    /// True when at least one YoY point has any data on either side — used to decide
    /// whether rendering the chart is meaningful.
    static func hasAnyData(_ points: [YearOverYearPoint]) -> Bool {
        points.contains { $0.currentAmount > 0 || $0.previousAmount > 0 }
    }
}
