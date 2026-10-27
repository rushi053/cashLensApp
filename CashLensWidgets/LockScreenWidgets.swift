//
//  LockScreenWidgets.swift
//  CashLensWidgets
//
//  Lock Screen accessory variants. We deliberately keep these tiny
//  and high-contrast — Lock Screen widgets render in monochrome over
//  the user's wallpaper, so glyphs and short numerics carry the load.
//
//  - **Spending Lock — circular**: ring with the month's spend % vs a
//    soft "100%" reference, total compact in the middle.
//  - **Spending Lock — rectangular**: "$1.2K this month • +12%" row.
//  - **Streak Lock — circular**: flame + day count.
//  - **Streak Lock — rectangular**: "8 of 19 days no-spend • Best 9".
//
//  All use `.widgetAccentable()` so the system tint follows the user's
//  Lock Screen accent color choice.
//

import WidgetKit
import SwiftUI

// MARK: - Spending — Lock Screen

struct SpendingLockWidget: Widget {
    let kind: String = "SpendingLockScreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpendingLockTimelineProvider()) { entry in
            SpendingLockEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Spending — Lock Screen")
        .description("Glanceable monthly spend on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SpendingLockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendingLockEntry {
        SpendingLockEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendingLockEntry) -> Void) {
        completion(SpendingLockEntry(date: Date(), snapshot: WidgetSnapshotIO.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingLockEntry>) -> Void) {
        let entry = SpendingLockEntry(date: Date(), snapshot: WidgetSnapshotIO.read())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SpendingLockEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SpendingLockEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingLockEntry

    var body: some View {
        let agg = entry.snapshot.spending.byTimeframe[.month]
            ?? .init(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)

        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(WidgetMoneyFormatter.compact(agg.net, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("month")
                    .font(.system(size: 8, weight: .medium))
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("This month")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(WidgetMoneyFormatter.full(agg.net, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                let delta = WidgetMoneyFormatter.percentDelta(current: agg.net, previous: agg.previousNet)
                Text("\(delta) vs last month")
                    .font(.system(size: 10, weight: .medium))
            }
            .widgetAccentable()
        case .accessoryInline:
            Text("CashLens • \(WidgetMoneyFormatter.compact(agg.net, currencyCode: entry.snapshot.currencyCode)) this month")
        default:
            EmptyView()
        }
    }
}

// MARK: - Streak — Lock Screen

struct StreakLockWidget: Widget {
    let kind: String = "StreakLockScreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakLockTimelineProvider()) { entry in
            StreakLockEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Streak — Lock Screen")
        .description("Your no-spend streak on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakLockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakLockEntry {
        StreakLockEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakLockEntry) -> Void) {
        completion(StreakLockEntry(date: Date(), snapshot: WidgetSnapshotIO.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakLockEntry>) -> Void) {
        let entry = StreakLockEntry(date: Date(), snapshot: WidgetSnapshotIO.read())
        let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StreakLockEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StreakLockEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakLockEntry

    var body: some View {
        // Pro-gated. Lock Screen real estate is too small for a full
        // upsell tile, so we show a tiny "Pro" lock glyph instead and
        // let the user discover the upgrade by tapping into the app.
        if entry.snapshot.isPro {
            unlockedView
        } else {
            lockedView
        }
    }

    @ViewBuilder
    private var unlockedView: some View {
        let s = entry.snapshot.streak
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(s.currentStreak)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(s.currentStreak == 1 ? "day" : "days")
                    .font(.system(size: 8, weight: .medium))
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(s.currentStreak > 0 ? "On a streak" : "No-spend streak")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text("\(s.currentStreak) day\(s.currentStreak == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Text("\(s.noSpendDaysThisMonth) of \(s.daysElapsedThisMonth) days • Best \(s.bestStreak)")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .widgetAccentable()
        case .accessoryInline:
            Text("CashLens • \(s.currentStreak) day no-spend streak")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var lockedView: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                Text("Pro").font(.system(size: 9, weight: .heavy, design: .rounded))
            }
            .widgetAccentable()
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Streak").font(.system(size: 11, weight: .semibold))
                    Text("Unlock with CashLens Pro").font(.system(size: 9, weight: .medium))
                }
            }
            .widgetAccentable()
        case .accessoryInline:
            Text("CashLens • Streak is a Pro widget")
        default:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Spending Circular", as: .accessoryCircular) {
    SpendingLockWidget()
} timeline: {
    SpendingLockEntry(date: .now, snapshot: .preview)
}

#Preview("Spending Rectangular", as: .accessoryRectangular) {
    SpendingLockWidget()
} timeline: {
    SpendingLockEntry(date: .now, snapshot: .preview)
}

#Preview("Streak Circular", as: .accessoryCircular) {
    StreakLockWidget()
} timeline: {
    StreakLockEntry(date: .now, snapshot: .preview)
}

#Preview("Streak Rectangular", as: .accessoryRectangular) {
    StreakLockWidget()
} timeline: {
    StreakLockEntry(date: .now, snapshot: .preview)
}
