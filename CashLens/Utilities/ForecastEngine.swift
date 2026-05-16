import Foundation

/// `ForecastEngine` projects future spending from past behaviour using a small,
/// honest set of techniques chosen to avoid the two failure modes that destroy
/// trust in financial forecasting: false confidence and double-counting.
///
/// The algorithm:
///
/// 1. **Discretionary baseline** — past `Expense`s flagged `isFromSubscription`
///    are excluded from the daily-pattern model so the recurring bills they
///    represent are not double-counted when we add them back as known
///    cashflows in step 4.
/// 2. **Weekday seasonality** — daily totals are bucketed by weekday and the
///    mean is used as the per-day baseline. Saturdays usually look nothing
///    like Tuesdays, so a single global average would be misleading.
/// 3. **Recency weighting** — each day in history gets a weight of
///    `exp(-daysAgo / decayHalfLifeDays)` so a habit change shows up quickly
///    rather than being averaged out by ancient data.
/// 4. **Subscription overlay** — known `Subscription.nextDueDate`s within the
///    horizon are walked forward by their cadence and added as one-time
///    spikes on the day they actually fall on. Inactive subs are ignored.
/// 5. **Confidence band** — ±1 standard deviation of daily residuals from the
///    weekday mean. Wider when history is short or volatile, narrower when
///    patterns are stable. We clamp the low end at 0 (you can't spend negative
///    money in a forecast).
/// 6. **Outlier resilience** — a single $1,200 flight shouldn't poison the
///    weekday mean. Per-weekday daily totals beyond ~3σ from the median are
///    capped before being averaged.
///
/// All functions are pure and Sendable-safe so this can run from any
/// `Task.detached` alongside the existing aggregation pipeline in
/// `StatisticsView`.
enum ForecastEngine {

    // MARK: - Public types

    /// One day in the projection. Either historical (with `actual`) or future
    /// (with `projected`, `confidenceLow`, `confidenceHigh`).
    struct DayPoint: Identifiable {
        let date: Date
        /// Actual amount on this day. `nil` for future days.
        let actual: Double?
        /// Projected amount on this day (baseline + subscription overlay).
        /// Equals `actual` for historical points so a single chart series
        /// reads continuously.
        let projected: Double
        /// Lower bound (–1σ, clamped at 0). Equals `projected` historically.
        let confidenceLow: Double
        /// Upper bound (+1σ). Equals `projected` historically.
        let confidenceHigh: Double
        /// How much of `projected` came from a known subscription cashflow.
        let subscriptionAmount: Double

        var id: Date { date }
    }

    /// Quality of the underlying history. The UI uses this to widen messaging
    /// when we don't have enough data to be confident.
    enum DataQuality: String {
        /// < 14 days of history with any spend — forecast is suppressed.
        case insufficient
        /// 14–29 days — usable but explicitly labelled as approximate.
        case limited
        /// 30+ days — full quality.
        case good
    }

    /// Result of a forecast run. Sums and per-day points, both ready to
    /// hand straight to a chart.
    struct Forecast {
        let horizonDays: Int
        let points: [DayPoint]

        // Headline numbers
        let projectedTotal: Double
        let projectedDiscretionary: Double
        let projectedSubscriptionTotal: Double

        // Range over the forecast horizon
        let confidenceLow: Double
        let confidenceHigh: Double

        // Diagnostics
        let baselineDailyAverage: Double
        let dataQuality: DataQuality
        let usableHistoryDays: Int

        // Top contributing category to the *discretionary* projection (helps
        // users see what's driving their forecast). `nil` when no data.
        let topDriverCategory: TopDriver?

        struct TopDriver {
            let category: Expense.Category
            let customCategoryId: UUID?
            let projectedShare: Double
        }

        /// First future day in the forecast — useful for chart labels.
        var horizonStart: Date? { points.first(where: { $0.actual == nil })?.date }
        /// Last day in the forecast (today + horizonDays - 1).
        var horizonEnd: Date? { points.last?.date }

        static let empty = Forecast(
            horizonDays: 0,
            points: [],
            projectedTotal: 0,
            projectedDiscretionary: 0,
            projectedSubscriptionTotal: 0,
            confidenceLow: 0,
            confidenceHigh: 0,
            baselineDailyAverage: 0,
            dataQuality: .insufficient,
            usableHistoryDays: 0,
            topDriverCategory: nil
        )
    }

    // MARK: - Tunables

    /// History window read into the model. ~3 months balances "enough signal
    /// to capture monthly cycles" with "recent enough to reflect current habits".
    static let historyWindowDays: Int = 90

    /// Recency decay half-life. A day's weight halves every this-many days.
    static let decayHalfLifeDays: Double = 30

    /// Cap residual outliers at this many σ above the weekday median when
    /// computing the seasonal mean.
    static let outlierSigmaCap: Double = 3.0

    /// Floor on the confidence width (as a fraction of the projected total)
    /// so the band never collapses to a misleading zero on uniform data.
    static let minConfidenceFraction: Double = 0.08

    // MARK: - Entry point

    /// Build a forecast for `horizonDays` days starting tomorrow, using the
    /// last `historyWindowDays` of `history` as the model and overlaying
    /// known subscription cashflows.
    static func compute(
        history: [Expense],
        upcomingSubscriptions: [Subscription],
        horizonDays: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Forecast {
        guard horizonDays > 0 else { return .empty }

        let today = calendar.startOfDay(for: now)
        let historyStart = calendar.date(byAdding: .day, value: -historyWindowDays, to: today) ?? today

        // Split: discretionary (model input) vs subscription (overlay only).
        let discretionaryHistory = history.filter {
            !$0.isFromSubscription && $0.date >= historyStart && $0.date < today
        }

        // Bucket discretionary history into per-day totals, keeping zeros.
        // Uses `signedAmount` so refunds reduce a day's total and the
        // forecast learns from your actual net spending, not gross movement.
        // Days that net out to a negative are clamped to 0 because the
        // model can't meaningfully extrapolate "negative future spending".
        var dailyTotals: [Date: Double] = [:]
        for e in discretionaryHistory {
            let day = calendar.startOfDay(for: e.date)
            dailyTotals[day, default: 0] += e.signedAmount
        }
        for (k, v) in dailyTotals where v < 0 {
            dailyTotals[k] = 0
        }

        // Walk every day from historyStart up to (but not including) today so
        // zero-spend days are explicitly counted — otherwise the mean is
        // inflated to the average of *spending* days only.
        var orderedDays: [(date: Date, total: Double, weight: Double)] = []
        var cursor = historyStart
        var dayIndex = 0
        while cursor < today {
            let total = dailyTotals[cursor] ?? 0
            // Recency weight: half-life decay.
            let daysAgo = Double(historyWindowDays - dayIndex)
            let weight = pow(0.5, daysAgo / decayHalfLifeDays)
            orderedDays.append((cursor, total, weight))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
            dayIndex += 1
        }

        let usableDays = orderedDays.count
        let activeDays = orderedDays.filter { $0.total > 0 }.count

        // Suppress the forecast when there's basically no history.
        let quality: DataQuality
        if activeDays < 5 || usableDays < 14 {
            quality = .insufficient
        } else if usableDays < 30 || activeDays < 10 {
            quality = .limited
        } else {
            quality = .good
        }

        guard quality != .insufficient else {
            return Forecast(
                horizonDays: horizonDays,
                points: historicalPointsOnly(orderedDays: orderedDays, today: today, horizonDays: horizonDays, calendar: calendar),
                projectedTotal: 0,
                projectedDiscretionary: 0,
                projectedSubscriptionTotal: 0,
                confidenceLow: 0,
                confidenceHigh: 0,
                baselineDailyAverage: 0,
                dataQuality: .insufficient,
                usableHistoryDays: usableDays,
                topDriverCategory: nil
            )
        }

        // Per-weekday weighted mean + outlier-capped variance.
        let weekdayStats = computeWeekdayStats(orderedDays: orderedDays, calendar: calendar)

        // Average baseline (used for headline diagnostics).
        let totalWeightedSpend = orderedDays.reduce(0.0) { $0 + $1.total * $1.weight }
        let totalWeight = orderedDays.reduce(0.0) { $0 + $1.weight }
        let baselineAvg = totalWeight > 0 ? totalWeightedSpend / totalWeight : 0

        // Top driver category (over the discretionary history, weighted by recency).
        let topDriver = computeTopDriver(history: discretionaryHistory, today: today, calendar: calendar)

        // Subscription overlay: walk each active sub forward through the horizon.
        let horizonStart = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let horizonEndExclusive = calendar.date(byAdding: .day, value: horizonDays + 1, to: today) ?? today
        var subscriptionByDay: [Date: Double] = [:]
        var subscriptionTotal: Double = 0
        for sub in upcomingSubscriptions where sub.isActive {
            var due = sub.nextDueDate
            // Hard iteration cap so a malformed (non-advancing) cadence
            // can never spin the loop forever. 400 covers daily subs that
            // are months in the past plus a 90-day horizon comfortably.
            var safety = 0
            while due < horizonStart && safety < 400 {
                let next = Subscription.calculateNextDueDate(from: due, frequency: sub.frequency)
                guard next > due else { break }
                due = next
                safety += 1
            }
            safety = 0
            while due < horizonEndExclusive && safety < 400 {
                let day = calendar.startOfDay(for: due)
                subscriptionByDay[day, default: 0] += sub.amount
                subscriptionTotal += sub.amount
                let next = Subscription.calculateNextDueDate(from: due, frequency: sub.frequency)
                guard next > due else { break }
                due = next
                safety += 1
            }
        }

        // Build the points array: history (actual) + horizon (projected).
        var points: [DayPoint] = []
        points.reserveCapacity(orderedDays.count + horizonDays)

        for day in orderedDays {
            points.append(DayPoint(
                date: day.date,
                actual: day.total,
                projected: day.total,
                confidenceLow: day.total,
                confidenceHigh: day.total,
                subscriptionAmount: 0
            ))
        }

        var projectedDiscretionary: Double = 0
        var confLowSum: Double = 0
        var confHighSum: Double = 0

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset + 1, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let stats = weekdayStats[weekday] ?? .zero
            let baseline = stats.mean
            let sigma = stats.stddev

            // Confidence band: ±1σ, with a soft floor so it never collapses
            // to a deceptive zero on uniform data.
            let widthFloor = baselineAvg * minConfidenceFraction
            let halfWidth = max(sigma, widthFloor)
            let low = max(0, baseline - halfWidth)
            let high = baseline + halfWidth

            let subAmount = subscriptionByDay[day] ?? 0
            let projected = baseline + subAmount

            projectedDiscretionary += baseline
            confLowSum += low + subAmount
            confHighSum += high + subAmount

            points.append(DayPoint(
                date: day,
                actual: nil,
                projected: projected,
                confidenceLow: low + subAmount,
                confidenceHigh: high + subAmount,
                subscriptionAmount: subAmount
            ))
        }

        return Forecast(
            horizonDays: horizonDays,
            points: points,
            projectedTotal: projectedDiscretionary + subscriptionTotal,
            projectedDiscretionary: projectedDiscretionary,
            projectedSubscriptionTotal: subscriptionTotal,
            confidenceLow: confLowSum,
            confidenceHigh: confHighSum,
            baselineDailyAverage: baselineAvg,
            dataQuality: quality,
            usableHistoryDays: usableDays,
            topDriverCategory: topDriver
        )
    }

    // MARK: - Internals

    /// When data is insufficient we still emit historical points so the chart
    /// can render the "we have history but can't project yet" empty state
    /// without an awkward jump.
    private static func historicalPointsOnly(
        orderedDays: [(date: Date, total: Double, weight: Double)],
        today: Date,
        horizonDays: Int,
        calendar: Calendar
    ) -> [DayPoint] {
        var points = orderedDays.map { DayPoint(date: $0.date, actual: $0.total, projected: $0.total, confidenceLow: $0.total, confidenceHigh: $0.total, subscriptionAmount: 0) }
        for offset in 0..<horizonDays {
            if let day = calendar.date(byAdding: .day, value: offset + 1, to: today) {
                points.append(DayPoint(date: day, actual: nil, projected: 0, confidenceLow: 0, confidenceHigh: 0, subscriptionAmount: 0))
            }
        }
        return points
    }

    /// Per-weekday recency-weighted mean and standard deviation, with a 3σ
    /// outlier cap on residuals so a single huge day doesn't poison the
    /// model. Indexed by `Calendar.component(.weekday, …)` (1 = Sunday).
    private static func computeWeekdayStats(
        orderedDays: [(date: Date, total: Double, weight: Double)],
        calendar: Calendar
    ) -> [Int: WeekdayStats] {
        var bucket: [Int: [(value: Double, weight: Double)]] = [:]
        for day in orderedDays {
            let weekday = calendar.component(.weekday, from: day.date)
            bucket[weekday, default: []].append((day.total, day.weight))
        }

        var result: [Int: WeekdayStats] = [:]
        for (weekday, samples) in bucket {
            // Provisional mean to get residuals for outlier capping.
            let totalWeight = samples.reduce(0.0) { $0 + $1.weight }
            guard totalWeight > 0 else {
                result[weekday] = .zero
                continue
            }
            let provisionalMean = samples.reduce(0.0) { $0 + $1.value * $1.weight } / totalWeight
            // Provisional variance.
            let varSum = samples.reduce(0.0) { $0 + ($1.value - provisionalMean) * ($1.value - provisionalMean) * $1.weight }
            let provisionalStd = sqrt(varSum / totalWeight)
            let cap = provisionalMean + outlierSigmaCap * provisionalStd

            // Re-mean with capped values.
            let cappedSamples = samples.map { (min($0.value, cap), $0.weight) }
            let mean = cappedSamples.reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight
            let variance = cappedSamples.reduce(0.0) { $0 + ($1.0 - mean) * ($1.0 - mean) * $1.1 } / totalWeight
            result[weekday] = WeekdayStats(mean: mean, stddev: sqrt(variance))
        }
        return result
    }

    private struct WeekdayStats {
        let mean: Double
        let stddev: Double
        static let zero = WeekdayStats(mean: 0, stddev: 0)
    }

    /// Top-spending category in the discretionary history, weighted by
    /// recency the same way the daily model is. Returns `nil` if no data.
    private static func computeTopDriver(
        history: [Expense],
        today: Date,
        calendar: Calendar
    ) -> Forecast.TopDriver? {
        guard !history.isEmpty else { return nil }

        struct Key: Hashable {
            let category: Expense.Category
            let customId: UUID?
        }
        var totals: [Key: Double] = [:]
        var grandTotal: Double = 0

        for e in history {
            let daysAgo = max(0.0, Double(calendar.dateComponents([.day], from: e.date, to: today).day ?? 0))
            let weight = pow(0.5, daysAgo / decayHalfLifeDays)
            let weighted = e.amount * weight
            let key = Key(category: e.category, customId: e.customCategoryId)
            totals[key, default: 0] += weighted
            grandTotal += weighted
        }

        guard grandTotal > 0, let top = totals.max(by: { $0.value < $1.value }) else { return nil }

        let share = grandTotal > 0 ? top.value / grandTotal : 0
        return Forecast.TopDriver(
            category: top.key.category,
            customCategoryId: top.key.customId,
            projectedShare: share
        )
    }
}
