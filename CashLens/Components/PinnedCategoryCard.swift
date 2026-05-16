import SwiftUI

/// Premium Pinned Category tile used on Home.
///
/// The glanceable unit of the "Pinned Categories" grid. Designed for a
/// deliberate vertical hierarchy (category title → big amount → meta) and
/// a FIXED outer height so tiles never look mismatched when only some of
/// them carry a budget bar.
///
///  ┌─────────────────────────────┐
///  │ [icon]            [↑ 12%]   │   ← 40 pt medallion + trend pill
///  │                             │
///  │ Food & Drinks               │   ← subheadline.semibold (identity)
///  │ $255.00                     │   ← 26 pt rounded bold
///  │ 7 expenses                  │   ← caption secondary
///  │                             │
///  │ ━━━━━━━━━━━━━━━━            │   ← optional budget bar (bottom)
///  └─────────────────────────────┘
///
///  Selected state (this card is the active Recent Expenses filter) adds a
///  gradient border in the category tint and a soft color-tinted shadow.
struct PinnedCategoryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    let expenseCount: Int
    let trend: Trend?
    let budget: BudgetSignal?
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject var viewModel: ExpenseViewModel

    enum Trend: Equatable {
        /// Percentage of increase (e.g. 0.12 = +12%).
        case up(Double)
        /// Percentage of decrease (e.g. 0.08 = -8%).
        case down(Double)
        /// Change is within ±2% — effectively unchanged.
        case flat
    }

    struct BudgetSignal: Equatable {
        let spent: Double
        let limit: Double

        var fraction: Double {
            guard limit > 0 else { return 0 }
            return min(1.0, spent / limit)
        }

        var isOver: Bool { spent > limit }
    }

    // MARK: Layout constants

    /// Fixed outer height. Identical regardless of whether a budget bar is
    /// rendered — when absent we reserve the bar's footprint as whitespace so
    /// every tile in the grid reads as exactly the same size.
    private var cardHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 172 : 156
    }

    private let iconSize: CGFloat = 40
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 16

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Spacer(minLength: 10)
                contentBlock
                Spacer(minLength: 8)
                budgetBarSlot
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: cardHeight, alignment: .topLeading)
            // Selected state: tinted flat fill + tinted ring (so the user's
            // pick reads loud and clear). Non-selected: default glass card
            // surface — material + brand wash + glass-edge hairline.
            //
            // The base elevation (crisp + soft shadow) is already painted
            // inside `cardSurface`. Selected-state ONLY adds an extra
            // tinted halo on top so the active tile pops; idle tiles
            // rely on the card surface's built-in shadow alone (one
            // shadow pass per tile, not two).
            .modifier(PinnedCardSurface(isSelected: isSelected, color: color))
            .shadow(
                color: isSelected ? color.opacity(0.22) : .clear,
                radius: isSelected ? 12 : 0,
                x: 0,
                y: isSelected ? 5 : 0
            )
            .animation(Theme.Motion.snappy, value: isSelected)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Sub-views

    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            iconMedallion
            Spacer(minLength: 4)
            if let trend {
                trendPill(for: trend)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: iconSize)
    }

    private var iconMedallion: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.28 : 0.18))
                .frame(width: iconSize, height: iconSize)
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(viewModel.formattedAmount(amount))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .contentTransition(.numericText())
                .moneyAnimation(amount: amount, currency: viewModel.selectedCurrency)
                .padding(.top, 1)

            Text(expenseCountText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
    }

    /// Reserves a consistent vertical slot so cards with and without a
    /// budget bar are the same outer height.
    @ViewBuilder
    private var budgetBarSlot: some View {
        if let budget {
            budgetBar(budget)
        } else {
            Color.clear.frame(height: 4)
        }
    }

    @ViewBuilder
    private func trendPill(for trend: Trend) -> some View {
        let (iconName, label, tint): (String, String, Color) = {
            switch trend {
            case .up(let pct):   return ("arrow.up.right",   percentLabel(pct), .red)
            case .down(let pct): return ("arrow.down.right", percentLabel(pct), Color(.systemGreen))
            case .flat:          return ("equal",            "Flat",            .secondary)
            }
        }()

        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.13)))
    }

    private func percentLabel(_ fraction: Double) -> String {
        // Clamp absurd ratios so a $1 → $200 jump doesn't render as "19900%".
        let clamped = min(fraction, 9.99)
        if clamped >= 1 {
            return String(format: "%.0fx", clamped + 1)
        }
        return "\(Int((clamped * 100).rounded()))%"
    }

    private var expenseCountText: String {
        expenseCount == 1 ? "1 expense" : "\(expenseCount) expenses"
    }

    @ViewBuilder
    private func budgetBar(_ budget: BudgetSignal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let filled = max(0, min(1, budget.fraction))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(budget.isOver ? Color.red : color)
                        .frame(width: width * filled)
                }
            }
            .frame(height: 4)
        }
        .accessibilityLabel("Budget used \(Int(budget.fraction * 100)) percent")
    }

    private var accessibilityLabel: String {
        var parts = [title, viewModel.formattedAmount(amount), expenseCountText]
        if isSelected {
            parts.append("Active filter")
        }
        if let trend {
            switch trend {
            case .up(let p):   parts.append("Up \(Int((p * 100).rounded())) percent vs previous period")
            case .down(let p): parts.append("Down \(Int((p * 100).rounded())) percent vs previous period")
            case .flat:        parts.append("Unchanged vs previous period")
            }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Surface modifier
//
// Picks the right `cardSurface` variant for the card's selection state:
// - Selected → flat tinted fill + tinted ring (loud, signals "active filter")
// - Idle → default glass surface (material backdrop + glass-edge hairline)
//
// Pulled into its own modifier because `.cardSurface(...)` returns a
// different opaque type per overload, so we need a `Group` (or modifier
// wrapper) to unify the two branches in the call-site chain.
private struct PinnedCardSurface: ViewModifier {
    let isSelected: Bool
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.cardSurface(
                radius: Theme.Radius.card,
                fill: color.opacity(0.10),
                stroke: color,
                strokeWidth: 1.5
            )
        } else {
            content.cardSurface(
                radius: Theme.Radius.card,
                stroke: Color.primary.opacity(0.06),
                strokeWidth: Theme.Stroke.hairline
            )
        }
    }
}

#if DEBUG
struct PinnedCategoryCard_Previews: PreviewProvider {
    static var previews: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            PinnedCategoryCard(
                title: "Food & Drinks",
                amount: 340.50,
                icon: "fork.knife",
                color: .orange,
                expenseCount: 12,
                trend: .up(0.12),
                budget: .init(spent: 340, limit: 500),
                isSelected: true,
                action: {}
            )
            PinnedCategoryCard(
                title: "Entertainment",
                amount: 58,
                icon: "tv",
                color: .pink,
                expenseCount: 3,
                trend: .down(0.25),
                budget: nil,
                isSelected: false,
                action: {}
            )
            PinnedCategoryCard(
                title: "Shopping",
                amount: 459.81,
                icon: "bag",
                color: .red,
                expenseCount: 5,
                trend: nil,
                budget: nil,
                isSelected: false,
                action: {}
            )
            PinnedCategoryCard(
                title: "Transportation",
                amount: 1240.00,
                icon: "car",
                color: .blue,
                expenseCount: 22,
                trend: .flat,
                budget: .init(spent: 1240, limit: 1000),
                isSelected: false,
                action: {}
            )
        }
        .padding()
        .environmentObject(ExpenseViewModel())
        .previewLayout(.sizeThatFits)
    }
}
#endif
