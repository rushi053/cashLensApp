import Foundation

/// Persists per-budget, per-period state so threshold alerts fire once when crossing 80% / 100%, not on every launch.
enum BudgetAlertState {
    private static func periodToken(for budget: Budget) -> String {
        String(Int(budget.period.dateRange.start.timeIntervalSince1970))
    }

    /// Last stored utilization (0...∞) for crossing detection after relaunch / foreground.
    static func lastPercentKey(budgetId: UUID, budget: Budget) -> String {
        "budgetAlert_lastPct_\(budgetId.uuidString)_\(periodToken(for: budget))"
    }

    /// UserDefaults flag: alert already delivered this period for this threshold.
    static func firedKey(budgetId: UUID, budget: Budget, threshold: Double) -> String {
        let t = Int((threshold * 100).rounded())
        return "budgetAlert_fired_\(budgetId.uuidString)_\(t)_\(periodToken(for: budget))"
    }

    static func lastPercent(for budget: Budget) -> Double? {
        let key = lastPercentKey(budgetId: budget.id, budget: budget)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }

    static func setLastPercent(_ value: Double, for budget: Budget) {
        let key = lastPercentKey(budgetId: budget.id, budget: budget)
        UserDefaults.standard.set(value, forKey: key)
    }

    static func hasFired(budget: Budget, threshold: Double) -> Bool {
        UserDefaults.standard.bool(forKey: firedKey(budgetId: budget.id, budget: budget, threshold: threshold))
    }

    static func markFired(budget: Budget, threshold: Double) {
        UserDefaults.standard.set(true, forKey: firedKey(budgetId: budget.id, budget: budget, threshold: threshold))
    }

    static func clearTracking(for budget: Budget) {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: lastPercentKey(budgetId: budget.id, budget: budget))
        for t in budget.alertAtPercentages {
            ud.removeObject(forKey: firedKey(budgetId: budget.id, budget: budget, threshold: t))
        }
    }
}
