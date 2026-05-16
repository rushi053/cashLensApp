import SwiftUI

/// Hero budget card shown on Home when the user has a single active budget.
///
/// Layout (vertical, spacious):
///
///   Header row     → budget name + status pill
///   Hero row       → big spent amount (+ "of $limit") and big % readout
///   Progress bar   → full-width gradient capsule (8pt)
///   Footer row     → three evenly-spaced stats: Left / Daily / Days
struct BudgetProgressCard: View {
    let budget: Budget
    let progress: BudgetViewModel.BudgetProgress
    let currencySymbol: String
    let formattedAmount: (Double) -> String
    /// Active currency, used as part of the `.contentTransition` animation
    /// key so that switching currency in Settings refreshes the displayed
    /// amount immediately instead of showing the old symbol until the next
    /// budget mutation.
    let currency: Expense.Currency
    var onTap: (() -> Void)?

    @State private var animateProgress = false

    // MARK: - Status mapping

    private var ringColor: Color {
        switch progress.status {
        case .safe:     return .appPrimary
        case .warning:  return .orange
        case .exceeded: return .red
        }
    }

    private var statusLabel: String {
        switch progress.status {
        case .safe:     return "On Track"
        case .warning:  return "Heads Up"
        case .exceeded: return "Over Budget"
        }
    }

    private var statusIcon: String {
        switch progress.status {
        case .safe:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .exceeded: return "exclamationmark.octagon.fill"
        }
    }

    private var percentText: String {
        "\(Int(min(progress.percentage * 100, 999)))%"
    }

    /// Solid fill for the progress bar — colour matches the ring/state colour.
    /// Name kept for backwards compatibility with the call site below.
    private var progressGradient: Color { ringColor }

    // MARK: - Body

    var body: some View {
        Button {
            HapticManager.shared.lightTap()
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headerRow
                heroRow
                progressBar
                footerRow
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Glass card; warning/over-budget states paint a tinted ring on
            // top of the default glass edge so the status reads at a glance.
            .cardSurface(
                radius: Theme.Radius.container,
                stroke: progress.status == .safe ? nil : ringColor.opacity(0.35),
                strokeWidth: progress.status == .safe ? Theme.Stroke.thin : 1
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                animateProgress = true
            }
        }
    }

    // MARK: - Header (name + status pill)

    private var headerRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Text(budget.name)
                .font(Theme.Typography.subsectionTitle)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(ringColor)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(
                Capsule().fill(ringColor.opacity(0.12))
            )
        }
    }

    // MARK: - Hero (spent amount + percentage)

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(formattedAmount(progress.spent))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("of \(formattedAmount(progress.limit))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(percentText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(ringColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            let clampedPct = max(0, min(CGFloat(progress.percentage), 1.0))
            let fillWidth = animateProgress ? geo.size.width * clampedPct : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ringColor.opacity(0.12))

                Capsule()
                    .fill(progressGradient)
                    .frame(width: fillWidth)
                    .shadow(color: ringColor.opacity(0.25), radius: 4, x: 0, y: 2)
            }
        }
        .frame(height: 8)
    }

    // MARK: - Footer stats

    private var footerRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            footerStat(
                value: formattedAmount(progress.remainingBudget),
                label: "Left"
            )

            statDivider

            footerStat(
                value: formattedAmount(progress.dailyAllowance),
                label: "Per day"
            )

            statDivider

            footerStat(
                value: "\(progress.daysRemaining)",
                label: progress.daysRemaining == 1 ? "Day left" : "Days left"
            )
        }
    }

    private func footerStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }
}

// MARK: - Multi-budget grid tile
//
// Used when the user has 2+ active budgets. Visually a peer of
// `PinnedCategoryCard` on Home — same outer dimensions, same corner radius,
// same typographic rhythm — so the Budgets and Pinned Categories grids sit
// next to each other as siblings rather than siblings-of-different-parents.

struct BudgetMiniCard: View {
    let budget: Budget
    let progress: BudgetViewModel.BudgetProgress
    let formattedAmount: (Double) -> String
    /// Active currency, used as part of the `.contentTransition` animation
    /// key so a currency switch in Settings refreshes the displayed
    /// amount immediately instead of leaving the old symbol on screen.
    let currency: Expense.Currency
    var onTap: (() -> Void)?

    // MARK: Status mapping (mirrors BudgetProgressCard so a single budget
    // and a multi-budget tile read identically).

    private var statusColor: Color {
        switch progress.status {
        case .safe:     return .appPrimary
        case .warning:  return .orange
        case .exceeded: return .red
        }
    }

    private var statusIcon: String {
        switch progress.status {
        case .safe:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .exceeded: return "exclamationmark.octagon.fill"
        }
    }

    private var percentText: String {
        "\(Int(min(progress.percentage * 100, 999)))%"
    }

    private var metaLine: String {
        // "of $300 · 7 days left" — if days are 0 we drop that half so we
        // never render "0 days left" as a cheerful status.
        let limit = "of \(formattedAmount(progress.limit))"
        if progress.daysRemaining > 0 {
            let label = progress.daysRemaining == 1 ? "1 day left" : "\(progress.daysRemaining) days left"
            return "\(limit) · \(label)"
        }
        return limit
    }

    // MARK: Layout constants — kept in sync with `PinnedCategoryCard`.

    private var cardHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 172 : 156
    }

    private let iconSize: CGFloat = 40
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 16

    var body: some View {
        Button {
            HapticManager.shared.lightTap()
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Spacer(minLength: 10)
                contentBlock
                Spacer(minLength: 8)
                progressBar
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: cardHeight, alignment: .topLeading)
            // Glass surface so the multi-budget grid matches the Pinned
            // Categories grid sitting next to it.
            .cardSurface(radius: Theme.Radius.card)
            .shadow(
                color: Theme.Shadow.cardColor,
                radius: Theme.Shadow.cardRadius,
                x: 0,
                y: Theme.Shadow.cardY
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Sub-views

    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            iconMedallion
            Spacer(minLength: 4)
            statusPill
        }
        .frame(height: iconSize)
    }

    private var iconMedallion: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.18))
                .frame(width: iconSize, height: iconSize)
            Image(systemName: budget.categoryFilter.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(statusColor)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            Image(systemName: statusIcon)
                .font(.system(size: 10, weight: .bold))
            Text(percentText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(statusColor.opacity(0.13)))
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(budget.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(formattedAmount(progress.spent))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .contentTransition(.numericText())
                .moneyAnimation(amount: progress.spent, currency: currency)
                .padding(.top, 1)

            Text(metaLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = max(0, min(1, CGFloat(progress.percentage)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(statusColor)
                    .frame(width: width * filled)
            }
        }
        .frame(height: 4)
    }

    private var accessibilityLabel: String {
        var parts = [
            budget.name,
            "\(formattedAmount(progress.spent)) of \(formattedAmount(progress.limit))",
            "\(percentText) used"
        ]
        if progress.daysRemaining > 0 {
            parts.append("\(progress.daysRemaining) days left")
        }
        switch progress.status {
        case .safe:     parts.append("On track")
        case .warning:  parts.append("Heads up")
        case .exceeded: parts.append("Over budget")
        }
        return parts.joined(separator: ", ")
    }
}
