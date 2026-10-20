import Foundation

/// Pure decision logic for the post-value automatic paywall.
///
/// The paywall auto-shows exactly once, right after the save that
/// pushes the user's expense count across the threshold — the moment
/// they've demonstrably gotten value from the app. All persistence
/// (UserDefaults reads/writes) stays at the call site; this type only
/// answers "given these facts, should we show it?", which keeps the
/// rule testable without touching global state.
struct PaywallTrigger {

    /// The paywall only auto-shows after the user has logged enough
    /// expenses to have seen real value.
    static let expenseThreshold = 10

    /// Minimum days between auto-shows. Defense-in-depth: the trigger
    /// is also once-ever via `hasAutoShownBefore`, but if that rule is
    /// ever relaxed this cap guarantees at most one auto-show a week.
    static let cooldownDays = 7

    /// Expense count when the add-expense flow started.
    let previousCount: Int
    /// Expense count after the save completed.
    let currentCount: Int
    let isPro: Bool
    /// True once the paywall has ever been auto-shown (manual paywall
    /// visits don't count — only the automatic trigger).
    let hasAutoShownBefore: Bool
    let lastAutoShowDate: Date?
    var now: Date = Date()

    var shouldAutoShow: Bool {
        guard !isPro else { return false }
        // Strictly a *crossing*: existing users who already have 10+
        // expenses when this ships never get an out-of-the-blue
        // paywall — the moment has to happen live.
        guard previousCount < Self.expenseThreshold,
              currentCount >= Self.expenseThreshold else { return false }
        // The crossing must be a real single save. A jump of more than
        // one means the count changed for some other reason (launch
        // hydration publishing the full history, an import, a sync) —
        // none of which are the "user just logged their 10th expense"
        // moment this paywall is built around.
        guard currentCount == previousCount + 1 else { return false }
        guard !hasAutoShownBefore else { return false }
        if let last = lastAutoShowDate,
           now.timeIntervalSince(last) < TimeInterval(Self.cooldownDays) * 86_400 {
            return false
        }
        return true
    }
}
