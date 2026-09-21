//
//  StreakWidget.swift
//  CashLensWidgets
//
//  No-Spend Streak widget — celebrates consecutive zero-spend days.
//  Hero number is large but uses .bold (not .black) to keep the
//  surface feeling refined instead of shouty.
//

import WidgetKit
import SwiftUI

// MARK: - Provider

struct StreakTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), snapshot: WidgetSnapshotIO.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(date: Date(), snapshot: WidgetSnapshotIO.read())
        let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct StreakWidget: Widget {
    let kind: String = "NoSpendStreak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakTimelineProvider()) { entry in
            StreakEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SpendingBackground(themeId: entry.snapshot.activeThemeId)
                }
        }
        .configurationDisplayName("No-Spend Streak")
        .description("Celebrate your zero-spend days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry view (size router)

struct StreakEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        if !entry.snapshot.isPro {
            WidgetProUpsellView(themeId: entry.snapshot.activeThemeId, title: "No-Spend Streak")
        } else {
            switch family {
            case .systemSmall:  StreakSmallView(entry: entry)
            case .systemMedium: StreakMediumView(entry: entry)
            default:            StreakSmallView(entry: entry)
            }
        }
    }
}

// MARK: - Small

struct StreakSmallView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StreakEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let s = entry.snapshot.streak
        let primary = theme.primary(for: scheme)
        let isOnStreak = s.currentStreak > 0
        let accent = isOnStreak ? Color.orange : primary

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(isOnStreak ? "ON A STREAK" : "STREAK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            // Hero — bold (not black) so it reads premium, not heavy
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(s.currentStreak)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.primary)
                Text(s.currentStreak == 1 ? "day" : "days")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.noSpendDaysThisMonth) of \(s.daysElapsedThisMonth) no-spend")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Best · \(s.bestStreak) day\(s.bestStreak == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Medium

struct StreakMediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StreakEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let s = entry.snapshot.streak
        let primary = theme.primary(for: scheme)
        let isOnStreak = s.currentStreak > 0
        let accent = isOnStreak ? Color.orange : primary
        let monthRatio = s.daysElapsedThisMonth > 0
            ? min(1.0, Double(s.noSpendDaysThisMonth) / Double(s.daysElapsedThisMonth))
            : 0
        let bestRatio = s.bestStreak > 0
            ? min(1.0, Double(s.currentStreak) / Double(s.bestStreak))
            : 0

        HStack(alignment: .top, spacing: 16) {
            // Left: hero
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(isOnStreak ? "ON A STREAK" : "STREAK")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(s.currentStreak)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(s.currentStreak == 1 ? "day" : "days")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)
                }

                Spacer(minLength: 0)

                Text(motivationalLine(for: s, isOnStreak: isOnStreak))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: stats stack
            VStack(alignment: .leading, spacing: 14) {
                statBlock(
                    label: "This month",
                    value: "\(s.noSpendDaysThisMonth)/\(s.daysElapsedThisMonth)",
                    suffix: "days",
                    ratio: monthRatio,
                    color: primary
                )
                statBlock(
                    label: "Vs best",
                    value: "\(s.currentStreak)/\(s.bestStreak)",
                    suffix: "days",
                    ratio: bestRatio,
                    color: .orange
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func statBlock(label: String, value: String, suffix: String, ratio: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(color)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(suffix)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.16))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
    }

    private func motivationalLine(for s: WidgetSnapshot.StreakBlock, isOnStreak: Bool) -> String {
        if isOnStreak && s.currentStreak >= s.bestStreak && s.bestStreak > 0 {
            return "New personal best — keep going."
        }
        if isOnStreak && s.bestStreak > 0 {
            let togo = s.bestStreak - s.currentStreak
            return "\(togo) day\(togo == 1 ? "" : "s") to your best run."
        }
        if s.bestStreak > 0 {
            return "Best run: \(s.bestStreak) day\(s.bestStreak == 1 ? "" : "s")"
        }
        return "Start a streak today."
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .preview)
}

#Preview("Medium", as: .systemMedium) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .preview)
}
