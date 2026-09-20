//
//  BudgetWidget.swift
//  CashLensWidgets
//
//  Budget Progress widget — usage rings and bars with a calm typography
//  ladder. Small surface focuses on a single most-relevant budget;
//  Medium shows two with thick capsule bars; Extra Large (iPad) shows
//  every active budget as a two-column card grid with a roll-up header.
//

import WidgetKit
import SwiftUI

// MARK: - Provider

struct BudgetTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(BudgetEntry(date: Date(), snapshot: WidgetSnapshotIO.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let entry = BudgetEntry(date: Date(), snapshot: WidgetSnapshotIO.read())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct BudgetWidget: Widget {
    let kind: String = "BudgetProgress"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetTimelineProvider()) { entry in
            BudgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SpendingBackground(themeId: entry.snapshot.activeThemeId)
                }
        }
        .configurationDisplayName("Budget Progress")
        .description("Track your active budgets at a glance.")
        // `.systemExtraLarge` is iPad-only; WidgetKit never offers it on
        // iPhone, so listing it is safe for a universal binary.
        .supportedFamilies([.systemSmall, .systemMedium, .systemExtraLarge])
    }
}

// MARK: - Entry view (size router)

struct BudgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry

    var body: some View {
        if !entry.snapshot.isPro {
            WidgetProUpsellView(themeId: entry.snapshot.activeThemeId, title: "Budget Progress")
        } else if entry.snapshot.budgets.isEmpty {
            BudgetEmptyView(themeId: entry.snapshot.activeThemeId)
        } else {
            switch family {
            case .systemSmall:      BudgetSmallView(entry: entry)
            case .systemMedium:     BudgetMediumView(entry: entry)
            case .systemExtraLarge: BudgetExtraLargeView(entry: entry)
            default:                BudgetSmallView(entry: entry)
            }
        }
    }
}

// MARK: - Picker

private extension BudgetEntry {
    /// "Most relevant" budget for the Small surface — over-budget rows
    /// rank first (those need user attention), then highest usage %.
    var primaryBudget: WidgetSnapshot.BudgetRow? {
        snapshot.budgets.max(by: { a, b in
            if a.isOverBudget != b.isOverBudget {
                return !a.isOverBudget
            }
            return a.usageRatio < b.usageRatio
        })
    }
}

// MARK: - Small

struct BudgetSmallView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: BudgetEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let budget = entry.primaryBudget!
        let color = ringColor(for: budget, theme: theme)

        VStack(alignment: .leading, spacing: 0) {
            // Header carries the budget name so it identifies which
            // budget is shown AND has all the breathing room it needs.
            // The target icon makes the widget category obvious.
            HStack(spacing: 5) {
                Image(systemName: "target")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primary(for: scheme))
                Text(budget.name.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(theme.primary(for: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 6)

            // Clean ring — only the % lives inside. No more text
            // fighting the stroke for space.
            ZStack {
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: budget.usageRatio)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                (
                    Text("\(Int((budget.usageRatio * 100).rounded()))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    + Text("%")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 92, maxHeight: 92)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 6)

            // Bottom info — calm single line, amounts on the left,
            // days-left flush right.
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(WidgetMoneyFormatter.compact(budget.spent, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("/ \(WidgetMoneyFormatter.compact(budget.cap, currencyCode: entry.snapshot.currencyCode))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(budget.daysRemaining)d left")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func ringColor(for b: WidgetSnapshot.BudgetRow, theme: WidgetTheme) -> Color {
        if b.isOverBudget { return .red }
        if b.usageRatio >= 0.8 { return .orange }
        return Color(hex: b.hex) ?? theme.primary(for: scheme)
    }
}

// MARK: - Medium

struct BudgetMediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: BudgetEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        // Cap at 2 so the bars + amounts can read from arm's length.
        let rows = Array(entry.snapshot.budgets.prefix(2))

        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primary(for: scheme))
                Text("BUDGETS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(theme.primary(for: scheme))
                Spacer(minLength: 0)
                Text("\(entry.snapshot.budgets.count) active")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 13) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, b in
                    budgetRow(b, theme: theme)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func budgetRow(_ b: WidgetSnapshot.BudgetRow, theme: WidgetTheme) -> some View {
        let color: Color = b.isOverBudget ? .red
            : b.usageRatio >= 0.8 ? .orange
            : (Color(hex: b.hex) ?? theme.primary(for: scheme))
        let pct = Int((b.usageRatio * 100).rounded())

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.20))
                    Image(systemName: b.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 24, height: 24)

                Text(b.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(WidgetMoneyFormatter.compact(b.spent, currencyCode: entry.snapshot.currencyCode))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("/")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(WidgetMoneyFormatter.compact(b.cap, currencyCode: entry.snapshot.currencyCode))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.16))
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * b.usageRatio)
                    }
                }
                .frame(height: 6)

                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
    }
}

// MARK: - Extra Large (iPad)

/// iPad-only 4×2 surface: roll-up header (total spent of total cap,
/// over-budget count) above a two-column grid of budget cards. Rows are
/// built by pairing budgets, so the grid needs no fixed cell size and
/// reflows with whatever width the Home Screen gives the widget.
struct BudgetExtraLargeView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: BudgetEntry

    /// 2 columns × 3 rows. The snapshot carries at most 8 budgets; any
    /// beyond six are summarised in the footer rather than squeezed in.
    private static let maxCards = 6

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)
        let primary = theme.primary(for: scheme)
        // Over-budget rows first (they need attention), then by usage.
        let sorted = entry.snapshot.budgets.sorted { a, b in
            if a.isOverBudget != b.isOverBudget { return a.isOverBudget }
            return a.usageRatio > b.usageRatio
        }
        let shown = Array(sorted.prefix(Self.maxCards))
        let hidden = sorted.count - shown.count
        let overCount = sorted.filter { $0.isOverBudget }.count
        let totalSpent = sorted.reduce(0) { $0 + $1.spent }
        let totalCap = sorted.reduce(0) { $0 + $1.cap }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primary)
                Text("BUDGETS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(primary)
                Text("\(sorted.count) active")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("\(WidgetMoneyFormatter.compact(totalSpent, currencyCode: entry.snapshot.currencyCode)) of \(WidgetMoneyFormatter.compact(totalCap, currencyCode: entry.snapshot.currencyCode))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                statusPill(overCount: overCount)
            }

            ForEach(Array(pairs(shown).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, budget in
                        budgetCard(budget, theme: theme)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }

            Spacer(minLength: 0)

            if hidden > 0 {
                Text("+\(hidden) more in CashLens")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Splits the budgets into rows of two for the grid.
    private func pairs(_ budgets: [WidgetSnapshot.BudgetRow]) -> [[WidgetSnapshot.BudgetRow]] {
        stride(from: 0, to: budgets.count, by: 2).map { start in
            Array(budgets[start..<min(start + 2, budgets.count)])
        }
    }

    @ViewBuilder
    private func statusPill(overCount: Int) -> some View {
        let isOver = overCount > 0
        let color: Color = isOver ? .red : .green
        HStack(spacing: 3) {
            Image(systemName: isOver ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(isOver ? "\(overCount) over budget" : "All on track")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .lineLimit(1)
    }

    @ViewBuilder
    private func budgetCard(_ b: WidgetSnapshot.BudgetRow, theme: WidgetTheme) -> some View {
        let color: Color = b.isOverBudget ? .red
            : b.usageRatio >= 0.8 ? .orange
            : (Color(hex: b.hex) ?? theme.primary(for: scheme))
        let pct = Int((b.usageRatio * 100).rounded())
        let remaining = b.cap - b.spent

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.20))
                    Image(systemName: b.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(b.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(periodLabel(b.period))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(WidgetMoneyFormatter.compact(b.spent, currencyCode: entry.snapshot.currencyCode))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("of \(WidgetMoneyFormatter.compact(b.cap, currencyCode: entry.snapshot.currencyCode))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.16))
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * b.usageRatio)
                    }
                }
                .frame(height: 6)

                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .frame(minWidth: 32, alignment: .trailing)
            }

            HStack {
                if b.isOverBudget {
                    Text("Over by \(WidgetMoneyFormatter.compact(-remaining, currencyCode: entry.snapshot.currencyCode))")
                        .foregroundStyle(Color.red)
                } else {
                    Text("\(WidgetMoneyFormatter.compact(remaining, currencyCode: entry.snapshot.currencyCode)) left")
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
                Text("\(b.daysRemaining)d left")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(scheme == .dark ? 0.10 : 0.07))
        )
    }

    private func periodLabel(_ period: WidgetSnapshot.BudgetPeriod) -> String {
        switch period {
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        case .custom:  return "Custom period"
        }
    }
}

// MARK: - Empty state

struct BudgetEmptyView: View {
    @Environment(\.colorScheme) private var scheme
    let themeId: String

    var body: some View {
        let theme = WidgetTheme.resolve(id: themeId)
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(theme.primary(for: scheme).opacity(0.18))
                Image(systemName: "target")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primary(for: scheme))
            }
            .frame(width: 40, height: 40)
            Text("No budgets yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Add a budget in CashLens\nto track it here.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .preview)
}

#Preview("Medium", as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .preview)
}

// Extra Large only renders on an iPad preview device — pick one in the
// canvas device menu, otherwise the preview shows an empty canvas.
#Preview("Extra Large", as: .systemExtraLarge) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .preview)
}
