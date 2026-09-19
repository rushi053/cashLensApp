import Foundation
import Combine

/// Decides when to ask for an App Store rating (replaces the 2.0.1
/// `FeedbackManager`).
///
/// Policy (2.2):
/// - Ask **once per major.minor version** (2.2 and 2.2.1 share one
///   ask), at a delight moment: the save that brings the user to
///   `expenseThreshold` expenses, or a no-spend streak reaching
///   `streakThreshold` days — whichever happens first.
/// - Never during onboarding, never while a paywall is on screen, and
///   never within `sheetQuietInterval` of a sheet dismissing (the ask
///   should land on a settled screen, not on top of an animation).
/// - Apple's native `requestReview` throttle (3 per 365 days) is the
///   final backstop.
///
/// The ask itself is Apple's one-tap star sheet: `MainTabView` observes
/// `shouldRequestReview`, applies its own "nothing else is presented"
/// check, then calls `markRequested()` + the SwiftUI `requestReview`
/// action — or `deferWhilePresenting()` to try again later. The version
/// key is written by `markRequested()`, so a deferred ask is never
/// spent invisibly.
///
/// Not `@MainActor`-isolated on purpose: triggers arrive from
/// `ExpenseViewModel` (not main-actor bound). All published writes are
/// hopped to the main queue.
final class ReviewPromptManager: ObservableObject {
    static let shared = ReviewPromptManager()

    // Tuning
    static let expenseThreshold = 10
    static let streakThreshold = 7
    /// Minimum settle time after the last sheet dismiss.
    static let sheetQuietInterval: TimeInterval = 2.0

    @Published private(set) var shouldRequestReview = false

    private let defaults = UserDefaults.standard
    /// A trigger fired and the ask is waiting for a quiet moment.
    private var isPending = false
    private var isPaywallVisible = false
    private var lastSheetDismiss: Date?
    private var scheduledFire: DispatchWorkItem?

    private init() {}

    // MARK: - State

    /// `CFBundleShortVersionString` truncated to major.minor — the
    /// "asked for version X" key, so a point update does not re-ask.
    private static var askVersionKey: String {
        let full = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return full.split(separator: ".").prefix(2).joined(separator: ".")
    }

    private var hasAskedForCurrentVersion: Bool {
        defaults.string(forKey: UserDefaultsKeys.reviewPromptAskedVersion) == Self.askVersionKey
    }

    private var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
    }

    private var canAsk: Bool {
        hasCompletedOnboarding && !hasAskedForCurrentVersion
    }

    // MARK: - Triggers

    /// Call after an expense is persisted. `totalExpenseCount` is the
    /// full on-disk count, or `nil` when the caller only has a partial
    /// (launch hot-window) count and the threshold can't be trusted.
    func recordExpenseSaved(totalExpenseCount: Int?) {
        guard let count = totalExpenseCount, count >= Self.expenseThreshold else { return }
        arm()
    }

    /// Call when the current no-spend streak is (re)computed.
    func recordStreak(days: Int) {
        guard days >= Self.streakThreshold else { return }
        arm()
    }

    // MARK: - Presentation context

    /// Call when any sheet the ask could collide with has just closed
    /// (the add-expense sheet is the one that matters in practice).
    func noteSheetDismissed() {
        lastSheetDismiss = Date()
        if isPending { schedule() }
    }

    func paywallDidAppear() {
        isPaywallVisible = true
        scheduledFire?.cancel()
    }

    /// A pending ask stays pending but does *not* re-arm here: asking
    /// for a rating right after the user closed a paywall reads as
    /// pushy. The next trigger (e.g. the next save) reschedules it.
    func paywallDidDisappear() {
        isPaywallVisible = false
    }

    /// Called by the observer once it has acted on the trigger, so the
    /// published flag doesn't re-fire on later view updates.
    func consume() {
        DispatchQueue.main.async { self.shouldRequestReview = false }
    }

    /// The observer is about to call `requestReview()`: spend this
    /// version's ask.
    func markRequested() {
        defaults.set(Self.askVersionKey, forKey: UserDefaultsKeys.reviewPromptAskedVersion)
        isPending = false
    }

    /// The observer found something presented (sheet, picker, cover)
    /// and did not ask. Stay pending but don't spin: the next trigger
    /// or `noteSheetDismissed()` reschedules.
    func deferWhilePresenting() {
        scheduledFire?.cancel()
        isPending = true
    }

    // MARK: - Scheduling

    private func arm() {
        guard canAsk else { return }
        isPending = true
        schedule()
    }

    /// Fires `sheetQuietInterval` after the later of now and the last
    /// sheet dismiss. A save is usually followed by its sheet closing a
    /// beat later; that dismiss calls `noteSheetDismissed()` and pushes
    /// the fire time out again, so the ask always lands on a settled
    /// screen.
    private func schedule() {
        scheduledFire?.cancel()
        let sinceDismiss = lastSheetDismiss.map { Date().timeIntervalSince($0) } ?? Self.sheetQuietInterval
        let delay = max(Self.sheetQuietInterval - sinceDismiss, 0) + Self.sheetQuietInterval

        let work = DispatchWorkItem { [weak self] in
            self?.fireIfStillAllowed()
        }
        scheduledFire = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fireIfStillAllowed() {
        guard isPending, canAsk, !isPaywallVisible else { return }
        if let last = lastSheetDismiss, Date().timeIntervalSince(last) < Self.sheetQuietInterval {
            schedule()
            return
        }
        // Stays pending until the observer calls `markRequested()` (or
        // `deferWhilePresenting()`), so a blocked ask is not spent.
        shouldRequestReview = true
    }

    // MARK: - Debug

    /// Diagnostics-only: forget that this version was asked.
    func resetForDebugging() {
        defaults.removeObject(forKey: UserDefaultsKeys.reviewPromptAskedVersion)
        isPending = false
        scheduledFire?.cancel()
        DispatchQueue.main.async { self.shouldRequestReview = false }
        print("🔄 Review prompt state reset for testing")
    }
}
