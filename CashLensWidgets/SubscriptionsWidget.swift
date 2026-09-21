//
//  SubscriptionsWidget.swift
//  CashLensWidgets
//
//  Subscriptions Due widget — upcoming recurring charges in the next
//  14 days. Rows are intentionally lean: medallion, name with a soft
//  date subtitle, amount on the right. The header carries the widget
//  identity ("SUBSCRIPTIONS") and the 14-day total.
//

import WidgetKit
import SwiftUI

// MARK: - Provider

struct SubscriptionsTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> SubscriptionsEntry {
        SubscriptionsEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SubscriptionsEntry) -> Void) {
        completion(SubscriptionsEntry(date: Date(), snapshot: WidgetSnapshotIO.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SubscriptionsEntry>) -> Void) {
        let entry = SubscriptionsEntry(date: Date(), snapshot: WidgetSnapshotIO.read())
        let next = nextMidnight() ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func nextMidnight() -> Date? {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.startOfDay(for: tomorrow)
    }
}

struct SubscriptionsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct SubscriptionsWidget: Widget {
    let kind: String = "SubscriptionsDue"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SubscriptionsTimelineProvider()) { entry in
            SubscriptionsEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SpendingBackground(themeId: entry.snapshot.activeThemeId)
                }
        }
        .configurationDisplayName("Subscriptions Due")
        .description("See what's billing in the next two weeks.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Entry view

struct SubscriptionsEntryView: View {
    let entry: SubscriptionsEntry

    var body: some View {
        if !entry.snapshot.isPro {
            WidgetProUpsellView(themeId: entry.snapshot.activeThemeId, title: "Subscriptions Due")
        } else if entry.snapshot.upcomingSubscriptions.isEmpty {
            SubscriptionsEmptyView(themeId: entry.snapshot.activeThemeId)
        } else {
            SubscriptionsMediumView(entry: entry)
        }
    }
}

// MARK: - Medium

struct SubscriptionsMediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: SubscriptionsEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        // Cap at 3 rows so each row has real breathing room. Anything
        // beyond is implied by the 14-day total in the header.
        let rows = Array(entry.snapshot.upcomingSubscriptions.prefix(3))
        let total = entry.snapshot.upcomingSubscriptions.reduce(0) { $0 + $1.amount }

        VStack(alignment: .leading, spacing: 11) {
            // Identity header — clear "SUBSCRIPTIONS" label so the
            // widget reads instantly on a busy home screen.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primary(for: scheme))
                Text("SUBSCRIPTIONS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(theme.primary(for: scheme))
                Spacer(minLength: 0)
                Text(WidgetMoneyFormatter.compact(total, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("· next 14d")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 9) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, sub in
                    subscriptionRow(sub, theme: theme)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func subscriptionRow(_ sub: WidgetSnapshot.SubscriptionRow, theme: WidgetTheme) -> some View {
        let color = Color(hex: sub.hex) ?? theme.primary(for: scheme)
        let days = max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: sub.nextDueDate)
        ).day ?? 0)
        // Only flag the most urgent rows visually — anything beyond
        // tomorrow is just neutral grey.
        let urgent = days <= 1
        let dateColor: Color = urgent ? .orange : .secondary

        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.20))
                Image(systemName: sub.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 28, height: 28)

            // Two-line row: name + soft date subtitle. No more pill.
            VStack(alignment: .leading, spacing: 1) {
                Text(sub.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(daysLabel(for: days))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(dateColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(WidgetMoneyFormatter.compact(sub.amount, currencyCode: entry.snapshot.currencyCode))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func daysLabel(for days: Int) -> String {
        switch days {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        default: return "in \(days) days"
        }
    }
}

// MARK: - Empty state

struct SubscriptionsEmptyView: View {
    @Environment(\.colorScheme) private var scheme
    let themeId: String

    var body: some View {
        let theme = WidgetTheme.resolve(id: themeId)
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(theme.primary(for: scheme).opacity(0.18))
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primary(for: scheme))
            }
            .frame(width: 40, height: 40)
            Text("All clear")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Nothing due in the next 14 days")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Medium", as: .systemMedium) {
    SubscriptionsWidget()
} timeline: {
    SubscriptionsEntry(date: .now, snapshot: .preview)
}
