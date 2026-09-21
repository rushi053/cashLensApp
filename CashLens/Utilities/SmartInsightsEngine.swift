import Foundation

/// Detects genuinely interesting weekly spending events for the Pro
/// "Smart Insights" notification stream.
///
/// Design constraints (from the product brief):
///   1. **High firing bar.** A boring week must produce no notification —
///      we'd rather miss a soft signal than spam someone.
///   2. **One headline per week, max.** We pick the highest-priority
///      candidate and discard the rest, so every push the user gets feels
///      like a deliberate, thoughtful nudge rather than noise.
///   3. **Don't repeat yourself.** A `fingerprint` per insight powers a
///      cooldown window: the same headline can't repeat for `cooldownDays`
///      after it last fired.
///   4. **Pure, sendable, off-thread.** All math is value-type so the
///      scheduler can call it from a background context without bouncing
///      to the main actor for anything except `UserDefaults` reads.
///
/// Insight types in order of priority (highest first):
///   - `.streakRecord`      — beat your previous best no-spend streak
///   - `.refundWindfall`    — net refunds dominated this week
///   - `.categorySpike`     — one category jumped ≥ `spikeThreshold`× vs. baseline
///   - `.categoryAllTime`   — first time a category exceeded a meaningful absolute amount
///   - `.subscriptionsDue`  — three or more subscriptions are about to renew
///   - `.weekTotalNew`      — this week is the highest-spend week in the lookback window
///
/// We compute candidates lazily and bail out on the first match (priority
/// order matters), so the typical pass is very cheap.
enum SmartInsightsEngine {

    // MARK: - Public types

    /// Distinguishes insight kinds so the scheduler can format/route them.
    enum Kind: String, Codable {
        case streakRecord
        case refundWindfall
        case categorySpike
        case categoryAllTime
        case subscriptionsDue
        case weekTotalNew
    }

    /// A finished insight ready to be dropped into a notification body.
    /// `headline` is the short title, `detail` is the longer line, and
    /// `fingerprint` is the dedupe key — same kind + same dimension (e.g.
    /// "Food" or "best-streak-9") collapses to the same fingerprint so we
    /// don't repeat ourselves in adjacent weeks.
    struct Insight: Equatable {
        let kind: Kind
        let headline: String
        let detail: String
        let fingerprint: String
    }

    /// History payload persisted in `UserDefaults`. Maps fingerprint ->
    /// last-fired ISO date string; we use a Date-keyed encoding deliberately
    /// to keep `UserDefaults` payloads small and human-debuggable.
    struct HistoryRecord: Codable {
        var entries: [String: Date]

        static let empty = HistoryRecord(entries: [:])
    }

    // MARK: - Tuning knobs
    //
    // Centralised here so we can tune without grepping through the engine.
    // Values picked for "feels right on a typical 50-expense-per-week user"
    // — high enough that boring weeks stay quiet but low enough that real
    // changes still land.

    /// Spike has to clear this multiplier vs. the rolling baseline before
    /// we'll mention it. 2.0 was too noisy in dogfood; 2.4 felt clean.
    static let spikeThreshold: Double = 2.4
    /// Minimum absolute dollar change for a spike. Stops us shouting about
    /// $3 → $8 jumps that are technically 2.6× but practically noise.
    static let spikeMinimumDelta: Double = 50
    /// Same fingerprint can't refire within this many days. Two weeks
    /// covers a back-to-back "Food spiked again" pattern.
    static let cooldownDays: Int = 14
    /// Subscriptions-due threshold — a single renewal is just an FYI.
    static let subscriptionsDueThreshold: Int = 3
    /// Look-ahead horizon for "subscriptions due soon".
    static let subscriptionsDueHorizonDays: Int = 7

    // MARK: - Inputs

    /// All inputs the engine needs, gathered once by the scheduler so we
    /// don't have to inject view models or Core Data contexts into pure code.
    struct Inputs {
        let now: Date
        let calendar: Calendar
        let allExpenses: [Expense]
        let activeSubscriptions: [Subscription]
        let formattedAmount: (Double) -> String
        let categoryDisplayName: (Expense) -> String
        let history: HistoryRecord
    }

    // MARK: - Public API

    /// Returns the single highest-priority insight that:
    ///   • Crosses the firing bar for its kind
    ///   • Has not fired (same fingerprint) in the past `cooldownDays`
    /// or `nil` if nothing interesting happened this week.
    static func selectInsight(inputs: Inputs) -> Insight? {
        let cal = inputs.calendar
        let now = inputs.now
        let history = inputs.history

        // Bound the candidate pool; ordered by priority.
        let candidates: [() -> Insight?] = [
            { streakRecordInsight(inputs: inputs, calendar: cal, now: now) },
            { refundWindfallInsight(inputs: inputs, calendar: cal, now: now) },
            { categorySpikeInsight(inputs: inputs, calendar: cal, now: now) },
            { categoryAllTimeInsight(inputs: inputs, calendar: cal, now: now) },
            { subscriptionsDueInsight(inputs: inputs, calendar: cal, now: now) },
            { weekTotalNewInsight(inputs: inputs, calendar: cal, now: now) }
        ]

        for produce in candidates {
            if let candidate = produce(),
               !isOnCooldown(fingerprint: candidate.fingerprint, history: history, now: now) {
                return candidate
            }
        }
        return nil
    }

    /// Records that `insight` was just sent. Returns the updated history;
    /// the caller is responsible for persisting it back to `UserDefaults`.
    static func record(insight: Insight, in history: HistoryRecord, now: Date = Date()) -> HistoryRecord {
        var updated = history
        updated.entries[insight.fingerprint] = now
        // Trim entries older than 60 days so the dictionary doesn't grow
        // forever — fingerprints that haven't fired in two months are
        // effectively un-suppressed anyway.
        let horizon = now.addingTimeInterval(-60 * 24 * 60 * 60)
        updated.entries = updated.entries.filter { $0.value >= horizon }
        return updated
    }

    private static func isOnCooldown(fingerprint: String, history: HistoryRecord, now: Date) -> Bool {
        guard let lastFired = history.entries[fingerprint] else { return false }
        let elapsed = now.timeIntervalSince(lastFired)
        return elapsed < TimeInterval(cooldownDays) * 24 * 60 * 60
    }

    // MARK: - Candidate detectors
    //
    // Each detector is a pure function over the `Inputs` struct. They all
    // return `nil` when their firing bar isn't met. Order matters — the
    // first non-nil one wins.

    /// "You set a personal best — N no-spend days last week."
    /// Fires when the user's longest no-spend run *ending in the last 14
    /// days* matches their best streak in the entire 90-day window AND the
    /// streak is at least 4 days. The 4-day floor avoids celebrating
    /// "you didn't spend Sat/Sun" as a personal best.
    private static func streakRecordInsight(inputs: Inputs, calendar: Calendar, now: Date) -> Insight? {
        let summary = StreakCalculator.summary(from: inputs.allExpenses, now: now, calendar: calendar)
        // Need a meaningful run, and the most recent run must equal the best.
        guard summary.bestStreak >= 4 else { return nil }
        guard summary.currentStreak >= 4 || summary.currentStreak == summary.bestStreak else {
            // currentStreak might be 0 if today had spending — also accept
            // "best streak occurred recently" via a re-scan below.
            if !bestStreakHappenedRecently(expenses: inputs.allExpenses, calendar: calendar, now: now, bestStreak: summary.bestStreak) {
                return nil
            }
            return Insight(
                kind: .streakRecord,
                headline: "Personal best",
                detail: "You set a personal best — \(summary.bestStreak) no-spend days recently. Keep the streak going!",
                fingerprint: "streak:\(summary.bestStreak)"
            )
        }
        return Insight(
            kind: .streakRecord,
            headline: "Personal best",
            detail: "You set a personal best — \(summary.bestStreak) no-spend days. Nice run.",
            fingerprint: "streak:\(summary.bestStreak)"
        )
    }

    /// Confirms the longest streak ended within the last 14 days — without
    /// it, we'd celebrate an old streak from 80 days ago.
    private static func bestStreakHappenedRecently(
        expenses: [Expense],
        calendar: Calendar,
        now: Date,
        bestStreak: Int
    ) -> Bool {
        guard bestStreak > 0 else { return false }
        let today = calendar.startOfDay(for: now)
        guard let lookbackStart = calendar.date(byAdding: .day, value: -90, to: today),
              let recentCutoff = calendar.date(byAdding: .day, value: -14, to: today) else {
            return false
        }

        var spentOn: Set<Date> = []
        for e in expenses where e.date >= lookbackStart && e.date <= now {
            spentOn.insert(calendar.startOfDay(for: e.date))
        }

        var run = 0
        var runEndedOn: Date? = nil
        var bestEndedOn: Date? = nil
        var observedBest = 0
        var scan = lookbackStart
        while scan <= today {
            if spentOn.contains(scan) {
                if run > observedBest {
                    observedBest = run
                    bestEndedOn = runEndedOn
                }
                run = 0
                runEndedOn = nil
            } else {
                run += 1
                runEndedOn = scan
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: scan) else { break }
            scan = next
        }
        if run > observedBest {
            observedBest = run
            bestEndedOn = runEndedOn
        }
        guard observedBest >= bestStreak, let endedOn = bestEndedOn else { return false }
        return endedOn >= recentCutoff
    }

    /// "Refunds outpaced spending this week." Fires only when the *net*
    /// refund exceeds a meaningful absolute floor — small returns aren't
    /// newsworthy.
    private static func refundWindfallInsight(inputs: Inputs, calendar: Calendar, now: Date) -> Insight? {
        let weekStart = startOfLastCompletedWeek(now: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let inWeek = inputs.allExpenses.filter { $0.date >= weekStart && $0.date < weekEnd }
        let net = inWeek.netTotal()
        let totalRefundAmount = inWeek.filter { $0.isRefund }.reduce(0) { $0 + $1.amount }

        guard totalRefundAmount >= 50, net < 0, net <= -50 else { return nil }

        return Insight(
            kind: .refundWindfall,
            headline: "Refund week",
            detail: "Refunds outpaced spending — your net last week was \(inputs.formattedAmount(abs(net))) in your favor.",
            fingerprint: "refund:\(weekStartFingerprint(weekStart, calendar: calendar))"
        )
    }

    /// "Your Food spend is 2.4× higher this week than usual."
    /// Compares the most recent completed week's per-category total against
    /// the rolling 4-week baseline (excluding the in-question week).
    private static func categorySpikeInsight(inputs: Inputs, calendar: Calendar, now: Date) -> Insight? {
        let weekStart = startOfLastCompletedWeek(now: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        guard let baselineStart = calendar.date(byAdding: .day, value: -28, to: weekStart) else { return nil }

        let inWeek = inputs.allExpenses.filter { $0.date >= weekStart && $0.date < weekEnd }
        let inBaseline = inputs.allExpenses.filter { $0.date >= baselineStart && $0.date < weekStart }

        // Aggregate by display-name so a custom-category and a default
        // category with identical names don't produce two ghost rows.
        var weekByName: [String: (amount: Double, sample: Expense)] = [:]
        for e in inWeek {
            let name = inputs.categoryDisplayName(e)
            let prior = weekByName[name]?.amount ?? 0
            weekByName[name] = (prior + e.signedAmount, e)
        }

        var baselineByName: [String: Double] = [:]
        for e in inBaseline {
            let name = inputs.categoryDisplayName(e)
            baselineByName[name, default: 0] += e.signedAmount
        }

        // Convert baseline to weekly average over 4 weeks.
        let baselineWeeks: Double = 4

        var bestRatio: Double = 0
        var bestName: String?
        var bestWeekAmount: Double = 0
        var bestBaselineAmount: Double = 0

        for (name, entry) in weekByName where entry.amount > 0 {
            let baselineWeekly = (baselineByName[name] ?? 0) / baselineWeeks
            // Skip categories with no baseline — could trigger a divide-by-zero
            // explosion the very first time someone uses a category.
            guard baselineWeekly > 0 else { continue }
            let delta = entry.amount - baselineWeekly
            guard delta >= spikeMinimumDelta else { continue }
            let ratio = entry.amount / baselineWeekly
            if ratio >= spikeThreshold && ratio > bestRatio {
                bestRatio = ratio
                bestName = name
                bestWeekAmount = entry.amount
                bestBaselineAmount = baselineWeekly
            }
        }

        guard let bestName, bestRatio > 0 else { return nil }
        let multiplier = String(format: "%.1f", bestRatio)
        let headline = "\(bestName) spike"
        let detail = "Your \(bestName) spend is \(multiplier)× higher than your 4-week average (\(inputs.formattedAmount(bestWeekAmount)) vs \(inputs.formattedAmount(bestBaselineAmount))). Worth a look?"

        return Insight(
            kind: .categorySpike,
            headline: headline,
            detail: detail,
            fingerprint: "spike:\(bestName.lowercased()):\(weekStartFingerprint(weekStart, calendar: calendar))"
        )
    }

    /// "Highest-ever week for Travel." Fires once per category when the
    /// most recent completed week beats every other week in the user's
    /// 12-week history. Floors out tiny categories so we don't shout about
    /// "your highest-ever Coffee week — $14".
    private static func categoryAllTimeInsight(inputs: Inputs, calendar: Calendar, now: Date) -> Insight? {
        let weekStart = startOfLastCompletedWeek(now: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        guard let lookbackStart = calendar.date(byAdding: .day, value: -84, to: weekStart) else { return nil }

        // Bucket every expense from lookback start → end-of-current-week into
        // (week-bucket, category-name) -> amount.
        var byWeek: [Date: [String: Double]] = [:]
        for e in inputs.allExpenses where e.date >= lookbackStart && e.date < weekEnd {
            let weekStartForExpense = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.date)
            ) ?? e.date
            let bucket = calendar.startOfDay(for: weekStartForExpense)
            let name = inputs.categoryDisplayName(e)
            byWeek[bucket, default: [:]][name, default: 0] += e.signedAmount
        }

        let currentBucket = calendar.startOfDay(
            for: calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)) ?? weekStart
        )
        guard let currentWeek = byWeek[currentBucket] else { return nil }

        var bestName: String?
        var bestAmount: Double = 0

        for (name, amount) in currentWeek where amount >= 100 {
            // It must beat every other observed week for the same name.
            var isAllTime = true
            var recordPriorAmount: Double = 0
            for (bucket, perCat) in byWeek where bucket != currentBucket {
                let prior = perCat[name] ?? 0
                if prior >= amount {
                    isAllTime = false
                    break
                }
                if prior > recordPriorAmount { recordPriorAmount = prior }
            }
            // Need at least one prior week with non-zero spend so it's
            // actually a "record" rather than a first-ever entry.
            guard isAllTime, recordPriorAmount > 0 else { continue }
            if amount > bestAmount {
                bestAmount = amount
                bestName = name
            }
        }

        guard let bestName, bestAmount > 0 else { return nil }
        return Insight(
            kind: .categoryAllTime,
            headline: "\(bestName) record",
            detail: "Highest week ever for \(bestName) — \(inputs.formattedAmount(bestAmount)) over 12-week history.",
            fingerprint: "alltime:\(bestName.lowercased()):\(weekStartFingerprint(weekStart, calendar: calendar))"
        )
    }

    /// "3 subscriptions renew in the next week." A heads-up so the user
    /// isn't surprised by a stack of charges. Skips over inactive subs.
    private static func subscriptionsDueInsight(inputs: Inputs, calendar: Calendar, now: Date) -> Insight? {
        let horizon = calendar.date(byAdding: .day, value: subscriptionsDueHorizonDays, to: now) ?? now
        let due = inputs.activeSubscriptions.filter { sub in
            guard sub.isActive else { return false }
            return sub.nextDueDate >= now && sub.nextDueDate <= horizon
        }
        guard due.count >= subscriptionsDueThreshold else { return nil }

        let totalAmount = due.reduce(0.0) { $0 + $1.amount }
        let weekStart = startOfLastCompletedWeek(now: now, calendar: calendar)
        return Insight(
            kind: .subscriptionsDue,
            headline: "Subscriptions due",
            detail: "\(due.count) subscriptions renew in the next 7 days (\(inputs.formattedAmount(totalAmount))). Heads-up before they hit.",
            fingerprint: "subs-due:\(due.count):\(weekStartFingerprint(weekStart, calendar: calendar))"
        )
    }

    /// "Highest-spend week in the last 12." Catches "this week was the
    /// most expensive in 3 months" without being category-specific.
    private static func weekTotalNewInsight(inputs: Inputs, calendar: Calendar, now: Date) -> Insight? {
        let weekStart = startOfLastCompletedWeek(now: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        guard let lookbackStart = calendar.date(byAdding: .day, value: -84, to: weekStart) else { return nil }

        var byWeek: [Date: Double] = [:]
        for e in inputs.allExpenses where e.date >= lookbackStart && e.date < weekEnd {
            let weekStartForExpense = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.date)
            ) ?? e.date
            let bucket = calendar.startOfDay(for: weekStartForExpense)
            byWeek[bucket, default: 0] += e.signedAmount
        }

        let currentBucket = calendar.startOfDay(
            for: calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)) ?? weekStart
        )
        let currentTotal = byWeek[currentBucket] ?? 0

        // Need at least 4 weeks of history so we don't shout "highest ever"
        // on day 8 of a fresh install.
        let priorBuckets = byWeek.filter { $0.key != currentBucket }
        guard priorBuckets.count >= 4 else { return nil }
        guard currentTotal >= 200 else { return nil }
        guard let priorMax = priorBuckets.values.max(), currentTotal > priorMax else { return nil }

        return Insight(
            kind: .weekTotalNew,
            headline: "Top spend week",
            detail: "Last week was your highest-spend week in 12 — \(inputs.formattedAmount(currentTotal)). Worth a quick look?",
            fingerprint: "topweek:\(weekStartFingerprint(weekStart, calendar: calendar))"
        )
    }

    // MARK: - Helpers

    /// Start of the most recent *completed* week — i.e. the Monday of the
    /// week before this one in a Mon-anchored calendar (using the user's
    /// own calendar so global locales don't fight us).
    private static func startOfLastCompletedWeek(now: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = calendar.firstWeekday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let thisWeekStart = cal.date(from: comps) ?? now
        return cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
    }

    /// Stable fingerprint shard for a given week-start. Year + ISO week
    /// number ensures two adjacent weeks never collapse.
    private static func weekStartFingerprint(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(comps.yearForWeekOfYear ?? 0)-w\(comps.weekOfYear ?? 0)"
    }
}
