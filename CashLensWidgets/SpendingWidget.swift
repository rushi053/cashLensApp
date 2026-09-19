//
//  SpendingWidget.swift
//  CashLensWidgets
//
//  Spending Snapshot — the headline widget surface for CashLens.
//
//  Four sizes:
//
//  - **Small**       → big net total, delta vs prior period, timeframe
//                      label, a row of category dots for at-a-glance variety.
//  - **Medium**      → left column with total/delta/timeframe, right column
//                      with the top 3 categories and progress bars.
//  - **Large**       → header strip + total + 5–6 category rows with bars.
//  - **Extra Large** → iPad only. Hero column (total, delta, 7-day
//                      sparkline) beside a full category breakdown with
//                      share-of-total percentages. Not a stretched Large.
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
        // `.systemExtraLarge` is iPad-only; WidgetKit simply never offers
        // it on iPhone, so listing it here is safe for a universal binary.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
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
        case .systemSmall:      SpendingSmallView(entry: entry)
        case .systemMedium:     SpendingMediumView(entry: entry)
        case .systemLarge:      SpendingLargeView(entry: entry)
        case .systemExtraLarge: SpendingExtraLargeView(entry: entry)
        default:                SpendingSmallView(entry: entry)
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

// MARK: - Extra Large (iPad)

/// iPad-only 4×2 surface. A genuine two-column design rather than a
/// stretched Large:
///
///   ┌────────────────────────┬────────────────────────────────┐
///   │ THIS MONTH             │ CATEGORIES            6 shown  │
///   │ $528.80                │ ▣ Food & Drinks   $187.40  35% │
///   │ +12%  vs last month    │ ▣ Groceries       $142.10  27% │
///   │                        │ ▣ Transport        $96.55  18% │
///   │ LAST 7 DAYS            │ ▣ …                            │
///   │ ▁ ▃ ▂ ▅ ▇ ▄ ▆  M T W…  │                                │
///   │ 23 expenses · Updated  │                                │
///   └────────────────────────┴────────────────────────────────┘
///
/// The two columns split the width evenly (each is roughly one Large
/// widget wide), so nothing depends on a fixed point size.
struct SpendingExtraLargeView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: SpendingEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let primary = theme.primary(for: scheme)
        let agg = entry.snapshot.spending.byTimeframe[entry.timeframe.snapshotKey]
            ?? .init(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)
        let peak = max(1, agg.topCategories.first.map { abs($0.total) } ?? 1)
        // Share-of-total denominator is the sum of the rows shown, so the
        // percentages add up to ~100% even when a refund makes `agg.net`
        // smaller than the biggest single category.
        let shareBase = max(1, agg.topCategories.reduce(0) { $0 + abs($1.total) })

        HStack(alignment: .top, spacing: 20) {
            // Left column: hero total + 7-day sparkline + footer.
            VStack(alignment: .leading, spacing: 10) {
                WidgetSectionHeader(
                    icon: "creditcard.fill",
                    label: entry.timeframe.label,
                    color: primary
                )

                Text(WidgetMoneyFormatter.full(agg.net, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    WidgetDeltaPill(current: agg.net, previous: agg.previousNet, compact: false)
                    Text(entry.timeframe.previousLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                WidgetSectionHeader(
                    icon: "chart.bar.fill",
                    label: "Last 7 days",
                    color: primary
                )

                SpendingSparkline(
                    days: entry.snapshot.dailyNetLast7Days ?? [],
                    accent: primary,
                    currencyCode: entry.snapshot.currencyCode
                )
                .frame(maxHeight: .infinity)

                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(agg.expenseCount) \(agg.expenseCount == 1 ? "expense" : "expenses") · Updated ")
                        + Text(entry.snapshot.generatedAt, style: .relative)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.22)

            // Right column: full category breakdown.
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    WidgetSectionHeader(
                        icon: "square.grid.2x2.fill",
                        label: "Categories",
                        color: primary
                    )
                    Spacer(minLength: 0)
                    if !agg.topCategories.isEmpty {
                        Text("\(agg.topCategories.count) shown")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if agg.topCategories.isEmpty {
                    Spacer(minLength: 0)
                    Text("No expenses in \(entry.timeframe.label.lowercased()).")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Open CashLens to log one.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(agg.topCategories.prefix(6).enumerated()), id: \.offset) { _, slice in
                        categoryRow(slice: slice, peak: peak, shareBase: shareBase, theme: theme)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func categoryRow(
        slice: WidgetSnapshot.CategorySlice,
        peak: Double,
        shareBase: Double,
        theme: WidgetTheme
    ) -> some View {
        let color = Color(hex: slice.hex) ?? theme.primary(for: scheme)
        let ratio = min(1, abs(slice.total) / peak)
        let share = Int((abs(slice.total) / shareBase * 100).rounded())

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.20))
                Image(systemName: slice.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(slice.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(WidgetMoneyFormatter.full(slice.total, currencyCode: entry.snapshot.currencyCode))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(share)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.16))
                        Capsule().fill(color).frame(width: geo.size.width * ratio)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

/// Seven-bar daily spend chart for the Extra Large surface. Plain
/// SwiftUI shapes (no Swift Charts) so it stays cheap inside the widget
/// render budget. Today's bar is drawn in the full accent colour; the
/// six prior days are muted.
private struct SpendingSparkline: View {
    let days: [WidgetSnapshot.DailyTotal]
    let accent: Color
    let currencyCode: String

    /// Narrow weekday letter ("M", "T", …) under each bar.
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    var body: some View {
        let shown = Array(days.suffix(7))
        // Refund-only days go negative; the bar height only reflects
        // spending, so clamp at zero.
        let values = shown.map { max(0, $0.net) }
        let peak = max(values.max() ?? 0, 0.01)
        let total = shown.reduce(0) { $0 + $1.net }

        if shown.isEmpty {
            placeholder
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, day in
                        let isToday = index == shown.count - 1
                        let ratio = CGFloat(max(0, day.net) / peak)
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(isToday ? accent : accent.opacity(0.38))
                                        .frame(height: max(3, geo.size.height * ratio))
                                }
                            }
                            Text(Self.weekdayFormatter.string(from: day.date))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(isToday ? accent : Color.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Text("7-day total \(WidgetMoneyFormatter.compact(total, currencyCode: currencyCode))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Shown when the snapshot predates the `dailyNetLast7Days` field
    /// (app not yet updated or not yet relaunched since the update).
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }
            Text("Daily totals appear after the next CashLens refresh.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
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

// Extra Large only renders on an iPad preview device — pick one in the
// canvas device menu, otherwise the preview shows an empty canvas.
#Preview("Extra Large", as: .systemExtraLarge) {
    SpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .preview, timeframe: .month)
}

#Preview("Extra Large (no daily data)", as: .systemExtraLarge) {
    SpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .previewWithoutDailyTotals, timeframe: .month)
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
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dailyNets: [Double] = [12.40, 48.90, 0, 31.25, 96.10, 22.00, 14.50]
        var totals: [WidgetSnapshot.DailyTotal] = []
        for (index, net) in dailyNets.enumerated() {
            let date = cal.date(byAdding: .day, value: index - 6, to: today) ?? today
            totals.append(WidgetSnapshot.DailyTotal(date: date, net: net))
        }
        s.dailyNetLast7Days = totals
        return s
    }

    /// Same as `preview` but with the 2.2 sparkline field missing, to
    /// check the Extra Large placeholder path (old snapshot on disk).
    static var previewWithoutDailyTotals: WidgetSnapshot {
        var s = WidgetSnapshot.preview
        s.dailyNetLast7Days = nil
        return s
    }
}
