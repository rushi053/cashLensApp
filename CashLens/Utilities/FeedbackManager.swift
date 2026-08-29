import Foundation
import Combine

/// Decides when to ask for an App Store rating.
///
/// Policy (reworked in 2.0.1):
/// - Ask only after real engagement: `actionThreshold` logged items across
///   `usageDayThreshold` distinct days — not on the first session.
/// - Delight moments (e.g. a successful backup export) can ask with a
///   lighter action bar, since the user just experienced clear value.
/// - Asks are spaced `cooldownDays` apart and capped at `maxPrompts`
///   lifetime. Apple's native `requestReview` throttle (3 per 365 days)
///   is the final backstop.
///
/// The ask itself is Apple's native one-tap star sheet: `MainTabView`
/// observes `shouldShowFeedbackRequest` and calls the SwiftUI
/// `requestReview` environment action directly — no custom modal.
class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()

    // Tuning
    /// 12, not 10: `PaywallTrigger.expenseThreshold` owns the 10th-expense
    /// moment (auto-paywall). Keeping these apart guarantees the rating
    /// prompt and the paywall can never fire off the same save.
    private let actionThreshold = 12        // logged expenses/subscriptions before a routine ask
    private let delightActionThreshold = 5  // lighter bar right after a delight moment
    private let usageDayThreshold = 3       // distinct active days before any ask
    private let cooldownDays: Double = 30   // spacing between asks
    private let maxPrompts = 3              // lifetime cap on asks

    @Published var shouldShowFeedbackRequest = false

    private let defaults = UserDefaults.standard

    private init() {
        migrateLegacyStateIfNeeded()
    }

    // MARK: State

    private var promptCount: Int {
        defaults.integer(forKey: UserDefaultsKeys.feedbackPromptCount)
    }

    private var actionCount: Int {
        defaults.integer(forKey: UserDefaultsKeys.successfulActionsCount)
    }

    private var usageDayCount: Int {
        defaults.integer(forKey: UserDefaultsKeys.feedbackUsageDayCount)
    }

    private var lastPromptDate: Date? {
        let timestamp = defaults.double(forKey: UserDefaultsKeys.lastFeedbackAttempt)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    /// Base eligibility shared by routine and delight-moment asks.
    private var isEligible: Bool {
        guard promptCount < maxPrompts else { return false }
        guard usageDayCount >= usageDayThreshold else { return false }
        if let last = lastPromptDate {
            let daysSince = Date().timeIntervalSince(last) / 86_400
            guard daysSince >= cooldownDays else { return false }
        }
        return true
    }

    // MARK: Triggers

    /// Called whenever the user logs an expense or subscription.
    func incrementSuccessfulAction() {
        recordUsageDay()
        defaults.set(actionCount + 1, forKey: UserDefaultsKeys.successfulActionsCount)
        maybePrompt(minActions: actionThreshold)
    }

    /// Called right after a moment of clear value (e.g. successful export),
    /// where a lighter engagement bar is acceptable.
    func registerDelightMoment() {
        recordUsageDay()
        maybePrompt(minActions: delightActionThreshold)
    }

    private func maybePrompt(minActions: Int) {
        guard isEligible, actionCount >= minActions else { return }

        // Record the attempt up front so a re-entrant trigger can't double-fire.
        defaults.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastFeedbackAttempt)
        defaults.set(promptCount + 1, forKey: UserDefaultsKeys.feedbackPromptCount)

        // Small delay so the save toast / sheet dismissal lands first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.shouldShowFeedbackRequest = true
        }
    }

    /// Called by the observer once it has acted on the trigger, so the
    /// published flag doesn't re-fire on later view updates.
    func consumePromptTrigger() {
        shouldShowFeedbackRequest = false
    }

    /// Tracks distinct calendar days with at least one meaningful action.
    private func recordUsageDay() {
        let today = Self.dayKey(for: Date())
        guard defaults.string(forKey: UserDefaultsKeys.feedbackLastUsageDay) != today else { return }
        defaults.set(today, forKey: UserDefaultsKeys.feedbackLastUsageDay)
        defaults.set(usageDayCount + 1, forKey: UserDefaultsKeys.feedbackUsageDayCount)
    }

    private static func dayKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    // MARK: Migration

    /// Pre-2.0.1 versions set a permanent `hasRequestedFeedback` flag on any
    /// interaction with the old custom prompt (including "Not Now"). We can't
    /// tell who actually rated, so treat legacy users as having been prompted
    /// once: they become re-eligible after the normal cooldown and fresh
    /// usage-day threshold, protected by Apple's native rate limit.
    private func migrateLegacyStateIfNeeded() {
        guard !defaults.bool(forKey: UserDefaultsKeys.feedbackLegacyMigrated) else { return }
        defaults.set(true, forKey: UserDefaultsKeys.feedbackLegacyMigrated)

        if defaults.bool(forKey: UserDefaultsKeys.hasRequestedFeedback) {
            defaults.set(max(1, promptCount), forKey: UserDefaultsKeys.feedbackPromptCount)
            // Start the cooldown now rather than from the (possibly ancient)
            // legacy timestamp, so nobody is re-asked immediately on update.
            defaults.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastFeedbackAttempt)
        }
    }

    // For testing purposes only
    func resetFeedbackState() {
        defaults.removeObject(forKey: UserDefaultsKeys.hasRequestedFeedback)
        defaults.removeObject(forKey: UserDefaultsKeys.successfulActionsCount)
        defaults.removeObject(forKey: UserDefaultsKeys.lastFeedbackAttempt)
        defaults.removeObject(forKey: UserDefaultsKeys.feedbackPromptCount)
        defaults.removeObject(forKey: UserDefaultsKeys.feedbackUsageDayCount)
        defaults.removeObject(forKey: UserDefaultsKeys.feedbackLastUsageDay)
        defaults.removeObject(forKey: UserDefaultsKeys.feedbackLegacyMigrated)
        shouldShowFeedbackRequest = false
        print("🔄 Feedback state reset for testing")
    }
}
