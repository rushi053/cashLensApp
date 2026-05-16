//
//  SpendingWidget.swift
//  CashLensWidgets
//
//  Spending Snapshot — the headline widget surface for CashLens.
//
//  Three sizes:
//
//  - **Small**  → big net total, delta vs prior period, timeframe label,
//                 a row of category dots for at-a-glance variety.
//  - **Medium** → left column with total/delta/timeframe, right column
//                 with the top 3 categories and progress bars.
//  - **Large**  → header strip + total + 5–6 category rows with bars.
//
//  Configurable via App Intent — the user picks Today / Week / Month /
//  Year on the widget configuration sheet, and the widget re-renders
//  against the corresponding `WidgetSnapshot.TimeframeAggregate`.
//
//  Pro-aware: free users get an upsell variant inviting them to unlock
//  premium widgets. We never silently downgrade a Pro user's widget if
//  their Pro state lapses — the snapshot will start emitting `isPro:
//  false` and the widget gracefully falls back.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration intent

/// User-configurable timeframe selector. iOS 18+ shows this in the
/// widget configuration sheet (long-press → Edit Widget) as a single
/// dropdown row.
struct SpendingWidgetIntent: AppIntent, WidgetConfigurationIntent {

    static var title: LocalizedStringResource = "Spending Snapshot"
    static var description = IntentDescription("Choose which timeframe of spending the widget shows.")

    @Parameter(title: "Timeframe", default: .month)
    var timeframe: SpendingWidgetTimeframe

    init() {}

    init(timeframe: SpendingWidgetTimeframe) {
        self.timeframe = timeframe
    }
}

/// AppEnum mirror of `WidgetSnapshot.Timeframe` — App Intents requires
/// an `AppEnum` (not just any `RawRepresentable`) for parameter types.
enum SpendingWidgetTimeframe: String, AppEnum {
    case today, week, month, year

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Spending Timeframe"

    static var caseDisplayRepresentations: [SpendingWidgetTimeframe: DisplayRepresentation] = [
        .today: "Today",
        .week: "This Week",
        .month: "This Month",
        .year: "This Year"
    ]

    /// Bridge to the snapshot's wire-level enum.
    var snapshotKey: WidgetSnapshot.Timeframe {
        switch self {
        case .today: return .today
        case .week:  return .week
        case .month: return .month
        case .year:  return .year
        }
    }

    /// Short label for in-widget chrome ("This Month", etc.).
    var label: String {
        switch self {
        case .today: return "Today"
        case .week:  return "This Week"
        case .month: return "This Month"
        case .year:  return "This Year"
        }
    }

    /// Phrase for "vs <previous>" callouts.
    var previousLabel: String {
        switch self {
        case .today: return "vs yesterday"
        case .week:  return "vs last week"
        case .month: return "vs last month"
        case .year:  return "vs last year"
        }
    }
}

// MARK: - Timeline provider

/// Configurable timeline provider — every entry carries the snapshot
/// AND the user's selected timeframe so the view can render against
/// the right aggregate without doing any further work.
struct SpendingTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> SpendingEntry {
        SpendingEntry(date: Date(), snapshot: .placeholder, timeframe: .month)
    }

    func snapshot(for configuration: SpendingWidgetIntent, in context: Context) async -> SpendingEntry {
        SpendingEntry(date: Date(), snapshot: WidgetSnapshotIO.read(), timeframe: configuration.timeframe)
    }

    func timeline(for configuration: SpendingWidgetIntent, in context: Context) async -> Timeline<SpendingEntry> {
        let entry = SpendingEntry(date: Date(), snapshot: WidgetSnapshotIO.read(), timeframe: configuration.timeframe)
        // The main app calls `WidgetCenter.reloadAllTimelines()` on every
        // mutation, so the hourly cadence here is just a stale-data
        // safety net — most refreshes happen on push.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct SpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let timeframe: SpendingWidgetTimeframe
}

// MARK: - Widget definition

struct SpendingWidget: Widget {
    let kind: String = "SpendingSnapshot"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SpendingWidgetIntent.self,
            provider: SpendingTimelineProvider()
        ) { entry in
            SpendingEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SpendingBackground(themeId: entry.snapshot.activeThemeId)
                }
        }
        .configurationDisplayName("Spending Snapshot")
        .description("Your CashLens spend at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry view (size router)

struct SpendingEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingEntry

    var body: some View {
        // Spending Snapshot is intentionally free for everyone — it's
        // the hero surface that drives Pro upgrades by demonstrating
        // quality. Other widgets are Pro-gated via `WidgetProUpsellView`.
        switch family {
        case .systemSmall:  SpendingSmallView(entry: entry)
        case .systemMedium: SpendingMediumView(entry: entry)
        case .systemLarge:  SpendingLargeView(entry: entry)
        default:            SpendingSmallView(entry: entry)
        }
    }
}

// MARK: - Background

/// Subtle theme-tinted **solid** background for the widget container.
/// We keep it deliberately quiet so the numbers and category bars stay
/// the focal point. No gradient — the design language is solid only.
struct SpendingBackground: View {
    @Environment(\.colorScheme) private var scheme
    let themeId: String

    var body: some View {
        let theme = WidgetTheme.resolve(id: themeId)
        let primary = theme.primary(for: scheme)
        primary.opacity(scheme == .dark ? 0.12 : 0.06)
    }
}

// MARK: - Shared chrome

/// Standardised section header label used across every widget surface
/// so the visual language stays consistent — same size, same weight,
/// same letter-spacing, same icon coupling.
private struct WidgetSectionHeader: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

/// Shared up/down delta pill — same design across every widget so
/// "+12%" reads identically whether it's on the small Spending card
/// or the large hero.
private struct WidgetDeltaPill: View {
    let current: Double
    let previous: Double
    let compact: Bool

    var body: some View {
        let delta = WidgetMoneyFormatter.percentDelta(current: current, previous: previous)
        if delta != "—" {
            let isUp = current > previous
            let color: Color = isUp ? .orange : .green
            HStack(spacing: 3) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                Text(delta)
                    .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(Capsule().fill(color.opacity(0.14)))
        }
    }
}

// MARK: - Small

struct SpendingSmallView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: SpendingEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let agg = entry.snapshot.spending.byTimeframe[entry.timeframe.snapshotKey]
            ?? .init(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)

        VStack(alignment: .leading, spacing: 0) {
            // Header gets the whole row to itself — no more fighting
            // for space with the delta pill. The timeframe label can
            // breathe and never gets truncated to "THIS M…"
            WidgetSectionHeader(
                icon: "creditcard.fill",
                label: entry.timeframe.label,
                color: theme.primary(for: scheme)
            )

            Spacer(minLength: 0)

            // Hero total
            Text(WidgetMoneyFormatter.compact(agg.net, currencyCode: entry.snapshot.currencyCode))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.primary)

            // Delta lives directly under the hero as quiet inline text
            // (no pill chrome) — visually it now reads as part of the
            // value, not as competing chrome.
            deltaInlineRow(current: agg.net, previous: agg.previousNet)
                .padding(.top, 2)

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Text("\(agg.expenseCount) \(agg.expenseCount == 1 ? "expense" : "expenses")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                categoryDots(slices: agg.topCategories, theme: theme)
            }
        }
    }

    @ViewBuilder
    private func deltaInlineRow(current: Double, previous: Double) -> some View {
        let delta = WidgetMoneyFormatter.percentDelta(current: current, previous: previous)
        if delta != "—" {
            let isUp = current > previous
            HStack(spacing: 3) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text(delta)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isUp ? Color.orange : Color.green)
        }
    }

    @ViewBuilder
    private func categoryDots(slices: [WidgetSnapshot.CategorySlice], theme: WidgetTheme) -> some View {
        if slices.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(Array(slices.prefix(5).enumerated()), id: \.offset) { _, slice in
                    Circle()
                        .fill(Color(hex: slice.hex) ?? theme.primary(for: scheme))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }
}

// MARK: - Medium

struct SpendingMediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: SpendingEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let agg = entry.snapshot.spending.byTimeframe[entry.timeframe.snapshotKey]
            ?? .init(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)
        let topMax = max(1, agg.topCategories.first.map { abs($0.total) } ?? 1)

        HStack(alignment: .top, spacing: 16) {
            // Left column: hero
            VStack(alignment: .leading, spacing: 0) {
                WidgetSectionHeader(
                    icon: "creditcard.fill",
                    label: entry.timeframe.label,
                    color: theme.primary(for: scheme)
                )

                Spacer(minLength: 0)

                Text(WidgetMoneyFormatter.compact(agg.net, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                deltaRow(current: agg.net, previous: agg.previousNet, label: entry.timeframe.previousLabel)
                    .padding(.top, 4)

                Spacer(minLength: 0)

                Text("\(agg.expenseCount) \(agg.expenseCount == 1 ? "expense" : "expenses")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: top 3 categories
            VStack(alignment: .leading, spacing: 9) {
                if agg.topCategories.isEmpty {
                    placeholderCategories(theme: theme)
                } else {
                    ForEach(Array(agg.topCategories.prefix(3).enumerated()), id: \.offset) { _, slice in
                        categoryRow(slice: slice, max: topMax, theme: theme)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func deltaRow(current: Double, previous: Double, label: String) -> some View {
        let delta = WidgetMoneyFormatter.percentDelta(current: current, previous: previous)
        if delta != "—" {
            let isUp = current > previous
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text(delta)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isUp ? Color.orange : Color.green)
        }
    }

    @ViewBuilder
    private func categoryRow(slice: WidgetSnapshot.CategorySlice, max: Double, theme: WidgetTheme) -> some View {
        let color = Color(hex: slice.hex) ?? theme.primary(for: scheme)
        let ratio = min(1, abs(slice.total) / max)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: slice.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 13)
                Text(slice.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text(WidgetMoneyFormatter.compact(slice.total, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16))
                    Capsule().fill(color).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 5)
        }
    }

    @ViewBuilder
    private func placeholderCategories(theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No expenses yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Open CashLens to log\nyour first one.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: - Large

struct SpendingLargeView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: SpendingEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let agg = entry.snapshot.spending.byTimeframe[entry.timeframe.snapshotKey]
            ?? .init(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)
        let topMax = max(1, agg.topCategories.first.map { abs($0.total) } ?? 1)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetSectionHeader(
                        icon: "creditcard.fill",
                        label: entry.timeframe.label,
                        color: theme.primary(for: scheme)
                    )
                    Text(WidgetMoneyFormatter.full(agg.net, currencyCode: entry.snapshot.currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    WidgetDeltaPill(current: agg.net, previous: agg.previousNet, compact: false)
                    Text(entry.timeframe.previousLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.22)

            VStack(spacing: 11) {
                if agg.topCategories.isEmpty {
                    Spacer()
                    Text("No expenses in \(entry.timeframe.label.lowercased()).")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Open CashLens to log one.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                } else {
                    ForEach(Array(agg.topCategories.prefix(6).enumerated()), id: \.offset) { _, slice in
                        categoryRow(slice: slice, max: topMax, theme: theme)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(agg.expenseCount) \(agg.expenseCount == 1 ? "expense" : "expenses") · Updated ")
                    + Text(entry.snapshot.generatedAt, style: .relative)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func categoryRow(slice: WidgetSnapshot.CategorySlice, max: Double, theme: WidgetTheme) -> some View {
        let color = Color(hex: slice.hex) ?? theme.primary(for: scheme)
        let ratio = min(1, abs(slice.total) / max)

        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.20))
                Image(systemName: slice.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(slice.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(WidgetMoneyFormatter.full(slice.total, currencyCode: entry.snapshot.currencyCode))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.16))
                        Capsule().fill(color).frame(width: geo.size.width * ratio)
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    SpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .preview, timeframe: .month)
}

#Preview("Medium", as: .systemMedium) {
    SpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .preview, timeframe: .month)
}

#Preview("Large", as: .systemLarge) {
    SpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .preview, timeframe: .month)
}

// MARK: - Preview snapshot helper

extension WidgetSnapshot {
    /// Hand-tuned, representative snapshot used by Xcode previews so
    /// we can iterate on widget layouts without running the simulator.
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot.placeholder
        s.userName = "Rushi"
        s.isPro = true
        let categories: [WidgetSnapshot.CategorySlice] = [
            .init(name: "Food & Drinks", symbol: "fork.knife", hex: "FFBEA0", total: 187.40),
            .init(name: "Groceries", symbol: "cart.fill", hex: "F5D746", total: 142.10),
            .init(name: "Transport", symbol: "car.fill", hex: "64BEFF", total: 96.55),
            .init(name: "Entertainment", symbol: "tv.fill", hex: "EB8CD2", total: 64.00),
            .init(name: "Shopping", symbol: "bag.fill", hex: "FF96A0", total: 38.75)
        ]
        let agg = WidgetSnapshot.TimeframeAggregate(
            net: 528.80,
            previousNet: 472.60,
            topCategories: categories,
            expenseCount: 23
        )
        s.spending = WidgetSnapshot.SpendingBlock(byTimeframe: [
            .today: .init(net: 14.50, previousNet: 22.10, topCategories: Array(categories.prefix(2)), expenseCount: 2),
            .week:  .init(net: 132.20, previousNet: 118.40, topCategories: Array(categories.prefix(4)), expenseCount: 7),
            .month: agg,
            .year:  .init(net: 5_842.30, previousNet: 5_140.80, topCategories: categories, expenseCount: 248)
        ])
        s.budgets = [
            .init(id: "1", name: "Food & Drinks", cap: 300, spent: 187.40,
                  period: .monthly, daysRemaining: 11, symbol: "fork.knife", hex: "FFBEA0"),
            .init(id: "2", name: "Shopping", cap: 100, spent: 96.50,
                  period: .monthly, daysRemaining: 11, symbol: "bag.fill", hex: "FF96A0"),
            .init(id: "3", name: "Entertainment", cap: 80, spent: 64.00,
                  period: .monthly, daysRemaining: 11, symbol: "tv.fill", hex: "EB8CD2")
        ]
        s.upcomingSubscriptions = [
            .init(id: "n", name: "Netflix", amount: 15.99,
                  nextDueDate: Date().addingTimeInterval(86_400 * 2),
                  symbol: "tv.fill", hex: "EB8CD2"),
            .init(id: "s", name: "Spotify", amount: 9.99,
                  nextDueDate: Date().addingTimeInterval(86_400 * 5),
                  symbol: "music.note", hex: "82E18C"),
            .init(id: "i", name: "iCloud+", amount: 2.99,
                  nextDueDate: Date().addingTimeInterval(86_400 * 9),
                  symbol: "icloud.fill", hex: "64BEFF")
        ]
        s.streak = .init(noSpendDaysThisMonth: 8, daysElapsedThisMonth: 19,
                         currentStreak: 2, bestStreak: 9)
        return s
    }
}
