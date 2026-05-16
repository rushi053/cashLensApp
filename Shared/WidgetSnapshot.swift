//
//  WidgetSnapshot.swift
//  CashLens + CashLensWidgets (shared)
//
//  Versioned data contract that the main app projects into the App
//  Group container, and the widget extension reads from. This is the
//  ENTIRE surface area the widgets see — they don't touch Core Data,
//  ProManager, ThemeStore, or any other live runtime state. Everything
//  they need to render is baked into this single value type.
//
//  Design notes:
//
//  - Small (~few KB) so atomic JSON read/write stays cheap even on
//    older devices and Lock Screen accessories where the widget budget
//    is brutal.
//  - All values are pre-aggregated; the widget never iterates raw
//    expenses. This keeps render time well under WidgetKit's budget.
//  - All collections have hard caps so a user with a giant history
//    can't accidentally produce a huge snapshot.
//  - Entirely value-type and Sendable-safe: produced on a background
//    queue in the main app, decoded on whatever thread WidgetKit
//    schedules in the extension.
//

import Foundation

// MARK: - Top-level snapshot

struct WidgetSnapshot: Codable, Hashable, Sendable {

    /// Bumped when the on-disk schema changes in a backward-incompatible
    /// way. The widget extension must check this and fall back to a
    /// "tap to update CashLens" placeholder if it's higher than the
    /// version it knows how to decode.
    var schemaVersion: Int = 1

    /// Wall-clock time the snapshot was generated. Powers the "Updated
    /// just now / Updated 2m ago" footer.
    var generatedAt: Date

    /// User-facing currency code (e.g. "USD", "INR"). Widgets format
    /// money against this — they don't read `Locale.current` because
    /// the user may have explicitly overridden the app currency in
    /// Settings, and the widget should respect that override.
    var currencyCode: String

    /// Pro entitlement status snapshot. Widgets gate premium variants
    /// against this — free users get the upsell variant.
    var isPro: Bool

    /// Active accent theme id (matches `AppTheme.id`). The widget uses
    /// `WidgetTheme.resolve(...)` to map this back to a renderable
    /// color pair. Defaults to "mauve" when missing.
    var activeThemeId: String

    /// User's display name (or empty string if not set). Used by some
    /// widget variants to personalize the greeting.
    var userName: String

    /// Pre-aggregated spending block (used by Spending Snapshot widget).
    var spending: SpendingBlock

    /// Pre-aggregated budget rows (used by Budget Progress widget).
    var budgets: [BudgetRow]

    /// Pre-aggregated upcoming subscriptions (used by Subscriptions Due widget).
    var upcomingSubscriptions: [SubscriptionRow]

    /// Pre-computed no-spend streak metrics (used by No-Spend Streak widget).
    var streak: StreakBlock
}

// MARK: - Spending block

extension WidgetSnapshot {

    struct SpendingBlock: Codable, Hashable, Sendable {
        /// Pre-aggregated rows for the timeframe shown in the Spending
        /// Snapshot widget. Keyed by `Timeframe` so a configurable
        /// widget can pick the timeframe at render time without the
        /// app having to predict the user's choice.
        var byTimeframe: [Timeframe: TimeframeAggregate]
    }

    /// Timeframes the Spending Snapshot widget supports. String-coded
    /// so the JSON file stays readable and stable across rebuilds.
    enum Timeframe: String, Codable, Hashable, Sendable, CaseIterable {
        case today
        case week
        case month
        case year
    }

    struct TimeframeAggregate: Codable, Hashable, Sendable {
        /// Net total for the timeframe (refunds already subtracted).
        var net: Double
        /// Net total for the *previous* equivalent timeframe (last week,
        /// last month, etc.). Used to render the "+12% vs last month"
        /// delta chip without the widget re-computing anything.
        var previousNet: Double
        /// Top categories (≤ 6) by net spend in the timeframe. Sorted
        /// descending by `total`.
        var topCategories: [CategorySlice]
        /// Number of expense rows in the timeframe (for the "47 expenses"
        /// label on Medium / Large variants).
        var expenseCount: Int
    }

    struct CategorySlice: Codable, Hashable, Sendable {
        /// Display name as it appears in the app (custom or default).
        var name: String
        /// SF Symbol name for the category. Always present — for
        /// "Other" / fallback we use `tag`.
        var symbol: String
        /// Hex color (no #, RRGGBB). Resolved against the snapshot's
        /// theme by the widget renderer.
        var hex: String
        /// Net total spent in this category for the timeframe.
        var total: Double
    }
}

// MARK: - Budget block

extension WidgetSnapshot {

    struct BudgetRow: Codable, Hashable, Sendable {
        /// Stable identifier for App Intent configuration (which budget
        /// the user picked in the widget configuration sheet).
        var id: String
        /// Budget name (category name or custom label).
        var name: String
        /// Budget cap.
        var cap: Double
        /// Net spend so far this period (refunds subtracted).
        var spent: Double
        /// Period bucket the budget renews on.
        var period: BudgetPeriod
        /// Days remaining in the current budget period (≥ 0).
        var daysRemaining: Int
        /// SF Symbol for the budget category, mirrors the in-app row.
        var symbol: String
        /// Hex color (no #, RRGGBB).
        var hex: String

        /// Convenience: usage ratio clamped to [0, 1] for the ring view.
        var usageRatio: Double {
            guard cap > 0 else { return 0 }
            return min(max(spent / cap, 0), 1)
        }

        /// Convenience: true when the user is over budget — used by the
        /// widget to flip the ring to a warning tint.
        var isOverBudget: Bool { cap > 0 && spent > cap }
    }

    enum BudgetPeriod: String, Codable, Hashable, Sendable {
        case weekly, monthly, yearly
    }
}

// MARK: - Subscription block

extension WidgetSnapshot {

    struct SubscriptionRow: Codable, Hashable, Sendable {
        /// Stable id for diffing.
        var id: String
        /// Display name.
        var name: String
        /// Recurring amount in the user's primary currency.
        var amount: Double
        /// Next due date.
        var nextDueDate: Date
        /// SF Symbol for the subscription's category.
        var symbol: String
        /// Hex color (no #, RRGGBB).
        var hex: String
    }
}

// MARK: - Streak block

extension WidgetSnapshot {

    struct StreakBlock: Codable, Hashable, Sendable {
        /// Days in the current month with zero spending so far.
        var noSpendDaysThisMonth: Int
        /// Days elapsed in the current month so far (≥ 1).
        var daysElapsedThisMonth: Int
        /// Current consecutive no-spend run ending today (0 if today
        /// has spending).
        var currentStreak: Int
        /// Longest no-spend run found in the rolling 90-day window.
        var bestStreak: Int
    }
}

// MARK: - Defaults

extension WidgetSnapshot {

    /// Empty placeholder snapshot used by the widget extension when:
    ///
    /// - the snapshot file doesn't exist yet (fresh install),
    /// - the App Group container is unreachable,
    /// - or the JSON fails to decode.
    ///
    /// The widget always renders SOMETHING — we never crash or show a
    /// blank tile to the user.
    static let placeholder: WidgetSnapshot = WidgetSnapshot(
        schemaVersion: 1,
        generatedAt: Date(),
        currencyCode: "USD",
        isPro: false,
        activeThemeId: "mauve",
        userName: "",
        spending: SpendingBlock(byTimeframe: [
            .today: TimeframeAggregate(net: 0, previousNet: 0, topCategories: [], expenseCount: 0),
            .week:  TimeframeAggregate(net: 0, previousNet: 0, topCategories: [], expenseCount: 0),
            .month: TimeframeAggregate(net: 0, previousNet: 0, topCategories: [], expenseCount: 0),
            .year:  TimeframeAggregate(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)
        ]),
        budgets: [],
        upcomingSubscriptions: [],
        streak: StreakBlock(
            noSpendDaysThisMonth: 0,
            daysElapsedThisMonth: 1,
            currentStreak: 0,
            bestStreak: 0
        )
    )
}
