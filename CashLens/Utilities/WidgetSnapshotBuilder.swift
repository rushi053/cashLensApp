//
//  WidgetSnapshotBuilder.swift
//  CashLens (main app only)
//
//  Pure value-type builder that turns live in-app state into the
//  `WidgetSnapshot` value the widget extension consumes from disk.
//
//  Design notes:
//
//  - **Pure & sendable.** No `@MainActor`, no dependency injection, no
//    Combine. Inputs are immutable snapshots passed in at the call site,
//    outputs are a value-type struct. This lets the coordinator hand
//    inputs to a `Task.detached` and never block the main thread.
//
//  - **Refund-aware.** All money math goes through `Expense.signedAmount`
//    and `Expense.netTotal()` so refunds correctly subtract from totals
//    — the widget surface matches the in-app surface to the cent.
//
//  - **Hard caps.** Top-categories and subscription lists are clipped
//    so a giant history can't bloat the snapshot file.
//

import Foundation

enum WidgetSnapshotBuilder {

    // MARK: - Caps

    /// Hard cap on `topCategories` per timeframe — Large widget shows ≤ 6
    /// rows, never more, so anything past that is wasted bytes.
    private static let maxTopCategories = 6

    /// Hard cap on `upcomingSubscriptions` — Medium widget shows up to 4
    /// rows, but we keep a couple extra in the snapshot for forward
    /// compatibility with a hypothetical Large variant.
    private static let maxUpcomingSubscriptions = 6

    /// Hard cap on `budgets` — Small widget shows 1, Medium shows 3.
    /// We keep a few more so the App Intent picker has options.
    private static let maxBudgets = 8

    /// Lookback window for "upcoming subscriptions" — anything due
    /// further out than this is not interesting on a glance widget.
    private static let upcomingWindowDays = 14

    // MARK: - Inputs container

    /// Lightweight value-type bundle of everything the builder needs.
    /// Letting the coordinator marshal one of these and pass it to a
    /// `Task.detached` keeps the builder fully thread-safe.
    struct Inputs: Sendable {
        let expenses: [Expense]
        let budgets: [Budget]
        let subscriptions: [Subscription]
        let customCategories: [CustomCategory]
        let currencyCode: String
        let userName: String
        let activeThemeId: String
        let isPro: Bool
        let now: Date
    }

    // MARK: - Build

    /// Build a fresh `WidgetSnapshot` from the supplied inputs. Pure
    /// value-type math; safe to call from any thread.
    static func build(_ inputs: Inputs) -> WidgetSnapshot {
        let cal = Calendar.current

        // Pre-build a custom-category lookup so we don't repeat a
        // linear search per expense row when resolving display name +
        // icon + color hex.
        let customByID: [UUID: CustomCategory] = Dictionary(
            uniqueKeysWithValues: inputs.customCategories.map { ($0.id, $0) }
        )

        return WidgetSnapshot(
            schemaVersion: 1,
            generatedAt: inputs.now,
            currencyCode: inputs.currencyCode,
            isPro: inputs.isPro,
            activeThemeId: inputs.activeThemeId,
            userName: inputs.userName,
            spending: buildSpending(
                expenses: inputs.expenses,
                customByID: customByID,
                now: inputs.now,
                calendar: cal
            ),
            budgets: buildBudgets(
                budgets: inputs.budgets,
                expenses: inputs.expenses,
                customByID: customByID
            ),
            upcomingSubscriptions: buildSubscriptions(
                subscriptions: inputs.subscriptions,
                customByID: customByID,
                now: inputs.now,
                calendar: cal
            ),
            streak: buildStreak(
                expenses: inputs.expenses,
                now: inputs.now,
                calendar: cal
            )
        )
    }

    // MARK: - Spending block

    private static func buildSpending(
        expenses: [Expense],
        customByID: [UUID: CustomCategory],
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot.SpendingBlock {
        var byTimeframe: [WidgetSnapshot.Timeframe: WidgetSnapshot.TimeframeAggregate] = [:]
        for tf in WidgetSnapshot.Timeframe.allCases {
            byTimeframe[tf] = aggregate(
                expenses: expenses,
                timeframe: tf,
                customByID: customByID,
                now: now,
                calendar: calendar
            )
        }
        return WidgetSnapshot.SpendingBlock(byTimeframe: byTimeframe)
    }

    private static func aggregate(
        expenses: [Expense],
        timeframe: WidgetSnapshot.Timeframe,
        customByID: [UUID: CustomCategory],
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot.TimeframeAggregate {
        let (currentRange, previousRange) = timeframeRanges(for: timeframe, now: now, calendar: calendar)

        var net: Double = 0
        var prevNet: Double = 0
        // Aggregate by a stable identity key — default categories use
        // their rawValue, custom categories use "custom:<uuid>".
        var totalsByKey: [String: Double] = [:]
        var nameByKey: [String: String] = [:]
        var symbolByKey: [String: String] = [:]
        var hexByKey: [String: String] = [:]
        var count = 0

        for e in expenses {
            guard e.amount.isFinite else { continue }
            let signed = e.signedAmount
            if e.date >= currentRange.start && e.date < currentRange.end {
                net += signed
                count += 1
                let key = identityKey(for: e)
                totalsByKey[key, default: 0] += signed
                if nameByKey[key] == nil {
                    nameByKey[key] = displayName(for: e, customByID: customByID)
                    symbolByKey[key] = symbol(for: e, customByID: customByID)
                    hexByKey[key] = hex(for: e, customByID: customByID)
                }
            } else if e.date >= previousRange.start && e.date < previousRange.end {
                prevNet += signed
            }
        }

        // Top-N categories by absolute spend (refunds in net stay
        // visible — a category with -$120 net is still informative for
        // the user and we want it on the chart).
        let sorted = totalsByKey
            .map { (key: $0.key, total: $0.value) }
            .sorted { abs($0.total) > abs($1.total) }
            .prefix(maxTopCategories)

        let topCategories: [WidgetSnapshot.CategorySlice] = sorted.map { entry in
            WidgetSnapshot.CategorySlice(
                name: nameByKey[entry.key] ?? "Other",
                symbol: symbolByKey[entry.key] ?? "tag",
                hex: hexByKey[entry.key] ?? CategoryHex.fallback,
                total: entry.total
            )
        }

        return WidgetSnapshot.TimeframeAggregate(
            net: net,
            previousNet: prevNet,
            topCategories: topCategories,
            expenseCount: count
        )
    }

    /// Half-open `[start, end)` range for the timeframe, plus the
    /// equivalent prior period (used for delta math).
    private static func timeframeRanges(
        for timeframe: WidgetSnapshot.Timeframe,
        now: Date,
        calendar: Calendar
    ) -> (current: (start: Date, end: Date), previous: (start: Date, end: Date)) {
        let today = calendar.startOfDay(for: now)
        switch timeframe {
        case .today:
            let start = today
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            let prevStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            return ((start, end), (prevStart, start))
        case .week:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            let prevStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
            return ((start, end), (prevStart, start))
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            let prevStart = calendar.date(byAdding: .month, value: -1, to: start) ?? start
            return ((start, end), (prevStart, start))
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
            let prevStart = calendar.date(byAdding: .year, value: -1, to: start) ?? start
            return ((start, end), (prevStart, start))
        }
    }

    private static func identityKey(for e: Expense) -> String {
        if e.category == .custom, let id = e.customCategoryId {
            return "custom:\(id.uuidString)"
        }
        return e.category.rawValue
    }

    private static func displayName(for e: Expense, customByID: [UUID: CustomCategory]) -> String {
        if e.category == .custom, let id = e.customCategoryId, let cc = customByID[id] {
            return cc.name
        }
        return e.category.displayName
    }

    private static func symbol(for e: Expense, customByID: [UUID: CustomCategory]) -> String {
        if e.category == .custom, let id = e.customCategoryId, let cc = customByID[id] {
            return cc.icon
        }
        return e.category.icon
    }

    private static func hex(for e: Expense, customByID: [UUID: CustomCategory]) -> String {
        if e.category == .custom, let id = e.customCategoryId, let cc = customByID[id] {
            return CategoryHex.resolve(cc.colorName)
        }
        return CategoryHex.resolve(e.category.color)
    }

    // MARK: - Budgets block

    private static func buildBudgets(
        budgets: [Budget],
        expenses: [Expense],
        customByID: [UUID: CustomCategory]
    ) -> [WidgetSnapshot.BudgetRow] {
        let active = budgets.filter(\.isActive).prefix(maxBudgets)
        return active.map { budget in
            let range = budget.period.dateRange
            let matching = expenses.filter { e in
                guard e.date >= range.start && e.date < range.end else { return false }
                switch budget.categoryFilter {
                case .overall:
                    return true
                case .defaultCategory(let raw):
                    return e.category.rawValue == raw
                case .customCategory(let id):
                    return e.category == .custom && e.customCategoryId == id
                }
            }
            let raw = matching.reduce(0.0) { partial, e in
                partial + (e.amount.isFinite ? e.signedAmount : 0)
            }
            let spent = max(0, raw)

            let (symbol, hex): (String, String) = {
                switch budget.categoryFilter {
                case .overall:
                    return ("creditcard.fill", CategoryHex.fallback)
                case .defaultCategory(let raw):
                    let cat = Expense.Category(rawValue: raw) ?? .other
                    return (cat.icon, CategoryHex.resolve(cat.color))
                case .customCategory(let id):
                    if let cc = customByID[id] {
                        return (cc.icon, CategoryHex.resolve(cc.colorName))
                    }
                    return ("tag.fill", CategoryHex.fallback)
                }
            }()

            return WidgetSnapshot.BudgetRow(
                id: budget.id.uuidString,
                name: budget.name,
                cap: budget.amount,
                spent: spent,
                period: budget.period == .weekly ? .weekly : .monthly,
                daysRemaining: budget.period.daysRemaining,
                symbol: symbol,
                hex: hex
            )
        }
    }

    // MARK: - Subscriptions block

    private static func buildSubscriptions(
        subscriptions: [Subscription],
        customByID: [UUID: CustomCategory],
        now: Date,
        calendar: Calendar
    ) -> [WidgetSnapshot.SubscriptionRow] {
        let cutoff = calendar.date(byAdding: .day, value: upcomingWindowDays, to: now) ?? now
        let upcoming = subscriptions
            .filter { $0.isActive && $0.nextDueDate <= cutoff }
            .sorted { $0.nextDueDate < $1.nextDueDate }
            .prefix(maxUpcomingSubscriptions)

        return upcoming.map { sub in
            let (symbol, hex): (String, String)
            if sub.category == .custom, let id = sub.customCategoryId, let cc = customByID[id] {
                symbol = cc.icon
                hex = CategoryHex.resolve(cc.colorName)
            } else {
                symbol = sub.category.icon
                hex = CategoryHex.resolve(sub.category.color)
            }
            return WidgetSnapshot.SubscriptionRow(
                id: sub.id.uuidString,
                name: sub.name,
                amount: sub.amount,
                nextDueDate: sub.nextDueDate,
                symbol: symbol,
                hex: hex
            )
        }
    }

    // MARK: - Streak block

    private static func buildStreak(
        expenses: [Expense],
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot.StreakBlock {
        // Reuses the existing in-app `StreakCalculator` so the widget's
        // streak math is bit-for-bit identical to the Home screen's.
        let summary = StreakCalculator.summary(from: expenses, now: now, calendar: calendar)
        return WidgetSnapshot.StreakBlock(
            noSpendDaysThisMonth: summary.noSpendDaysThisMonth,
            daysElapsedThisMonth: summary.daysElapsedThisMonth,
            currentStreak: summary.currentStreak,
            bestStreak: summary.bestStreak
        )
    }
}

// MARK: - CategoryHex palette

/// Pure-data hex palette. Mirrors the light-mode values in
/// `ColorExtension.LightColors` so what the widget renders matches what
/// the in-app categories look like on a light background. The widget's
/// theming layer can apply its own dark-mode shifts on render — the
/// snapshot holds the canonical light-mode hex.
private enum CategoryHex {
    /// Fallback color when an unknown name is requested. Mauve light
    /// mode hex (`#B48CF0`) — same as the default theme accent — so a
    /// missing color never looks wildly out of place.
    static let fallback = "B48CF0"

    static func resolve(_ name: String) -> String {
        switch name.lowercased() {
        // Category-name aliases (default categories ship a name like
        // "groceries", not the palette name "lemonChiffon").
        case "groceries":      return "F5D746"
        case "food":           return "FFBEA0"
        case "transportation": return "64BEFF"
        case "entertainment":  return "EB8CD2"
        case "shopping":       return "FF96A0"
        case "utilities":      return "F5D746"
        case "health":         return "B48CF0"
        case "education":      return "6E96FF"
        case "travel":         return "5AD2FF"
        case "other":          return "82E18C"
        // Direct palette names (custom categories pick from this list).
        case "lemonchiffon":   return "F5D746"
        case "champagnepink":  return "FFBEA0"
        case "tearose":        return "FF96A0"
        case "pinklavender":   return "EB8CD2"
        case "mauve":          return "B48CF0"
        case "jordyblue":      return "6E96FF"
        case "nonphotoblue":   return "64BEFF"
        case "electricblue":   return "5AD2FF"
        case "aquamarine":     return "64DCBE"
        case "celadon":        return "82E18C"
        // 14 new — keep mirrored with `ColorExtension.LightColors` so
        // the widget renders custom categories in the same hue the user
        // sees inside the app.
        case "coral":          return "FF826E"
        case "apricot":        return "FFAF69"
        case "goldenrod":      return "F5C350"
        case "honey":          return "F0AF5F"
        case "mint":           return "82D7AF"
        case "sage":           return "A0C89B"
        case "forest":         return "5FAF82"
        case "seafoam":        return "82DCD7"
        case "ocean":          return "50A5C8"
        case "periwinkle":     return "9BA5F0"
        case "lavender":       return "C8AFF0"
        case "plum":           return "A573C3"
        case "blush":          return "F5AFC3"
        case "slate":          return "91A0B4"
        default:               return fallback
        }
    }
}
