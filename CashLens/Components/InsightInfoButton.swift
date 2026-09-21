import SwiftUI

/// Plain-English explanation of a single stat — passed into `InsightInfoButton`.
///
/// Designed to keep the Pro Insights cards glanceable while giving first-time users
/// a tap-to-learn affordance (no permanent text clutter).
struct InsightInfo {
    /// Display title shown at the top of the explanation sheet.
    let title: String
    /// SF Symbol drawn in the header medallion.
    let symbol: String
    /// Brand color used for the medallion + accents.
    let accent: Color
    /// What the stat represents in everyday language.
    let description: String
    /// How the number is calculated. Keep it to 1–2 sentences.
    let formula: String
    /// Why the user should care about this stat.
    let tip: String
}

// MARK: - Copy

/// Canonical copy for each Pro Insights stat. Centralised here so the cards and the
/// sheet never drift — and so marketing tweaks land in one file.
extension InsightInfo {
    static let dailyPace = InsightInfo(
        title: "Daily Pace",
        symbol: "calendar.day.timeline.left",
        accent: .appPrimary,
        description: "The average amount you've spent per day so far in the selected period.",
        formula: "Total spent ÷ number of days elapsed (capped at today, so the first few days of a long range don't deflate the average).",
        tip: "If this number's climbing vs. the previous period, you're spending faster than usual — a great early warning before the total starts to look scary."
    )

    static let velocity = InsightInfo(
        title: "On Pace For",
        symbol: "bolt.fill",
        accent: .appPrimary,
        description: "A projection of where your spending will land by the end of the selected period if you keep going at today's rate.",
        formula: "Current total ÷ fraction of the period elapsed. When the period has already ended, this just shows the actual final total.",
        tip: "Red means you're on track to overspend vs. the previous period. Green means you're pacing below it. Use it to adjust mid-period instead of discovering the damage at the end."
    )

    static let yearOverYear = InsightInfo(
        title: "Year over Year",
        symbol: "chart.bar.xaxis",
        accent: .appPrimary,
        description: "Your monthly spending this year next to the same months last year, for the trailing six months.",
        formula: "Expenses are grouped by (year, month); this year's bars use your accent color, last year's are greyed. The delta pill sums both series and compares them.",
        tip: "Great for spotting seasonal patterns — holidays, yearly bills, back-to-school bumps — and for seeing whether you're trending better or worse year over year."
    )

    static let forecast = InsightInfo(
        title: "Forecast",
        symbol: "chart.line.uptrend.xyaxis",
        accent: .appPrimary,
        description: "A projection of how much you'll spend over the next 30, 60, or 90 days based on your recent habits and any subscriptions due in that window.",
        formula: "Past 90 days of discretionary spending are split by weekday and recency-weighted (recent days count more than old ones). Outliers are softened so a single big day doesn't skew things. Active subscriptions are added on top using their actual due dates so we never double-count. The shaded band is ±1 standard deviation of your daily variation — a realistic range, not a wish.",
        tip: "Use the horizon switch to see further ahead. The 'Subscription impact' card shows how much of your forecast is locked in by recurring bills — that's the part of your spending you'd need to cancel something to change."
    )

    // MARK: - Non-Pro section explanations
    //
    // These cover the free-tier sections on the Statistics screen. They use the
    // same explanation sheet pattern so the whole screen feels uniformly tappable
    // and learnable — not just the Pro cards.

    static let heroOverview = InsightInfo(
        title: "Overview",
        symbol: "creditcard.fill",
        accent: .appPrimary,
        description: "The total you've spent in the selected period, with a comparison to the same-length window immediately before it. The three mini-stats below show the expense count, per-expense average, and your single biggest expense.",
        formula: "Total = sum of every expense matching the current filters. Delta = (current total − previous total) ÷ previous total × 100. Average = total ÷ expense count.",
        tip: "Use the chevrons in the filter bar to walk backwards through history — the delta pill stays anchored to the period immediately before the one you're viewing."
    )

    static let highlights = InsightInfo(
        title: "Highlights",
        symbol: "sparkles",
        accent: .appPrimary,
        description: "Automatically surfaced observations from the current view — unusual increases, large single expenses, category shifts, and other patterns worth knowing about.",
        formula: "CashLens scans the filtered set for outliers (amounts > 2× your average), category concentration (one category > 40% of total), and period-over-period swings. Cards only appear when there's something genuinely interesting to show.",
        tip: "Highlights change as you navigate periods or switch categories — they're always relative to what's currently on screen."
    )

    static let whereItGoes = InsightInfo(
        title: "Where It Goes",
        symbol: "chart.pie.fill",
        accent: .appPrimary,
        description: "A category-level breakdown of your spending. The donut shows each category's share at a glance; the list below gives you the exact amount, count, and percentage.",
        formula: "Percentage = category total ÷ all-categories total × 100. Categories with zero spending in the current view are hidden.",
        tip: "Tap any donut slice or any row — the other half highlights in sync. Tap again to clear the focus. Use the category filter up top to drill into a single category's full history."
    )

    static let spendingPattern = InsightInfo(
        title: "Spending Pattern",
        symbol: "calendar",
        accent: .appPrimary,
        description: "A day-by-day heatmap of your spending. Darker cells mean you spent more on that day; blank cells are days with no recorded spending.",
        formula: "Each cell represents one calendar day. Shade intensity is normalised against the heaviest day in the current view, so the darkest cell is always 100%.",
        tip: "Tap any day to see the exact amount. Clusters of dark cells often reveal weekly patterns — payday splurges, weekend dinners, or end-of-month bill runs."
    )

    // Pro-tier section explanation. Surfaces *how* the donut is computed so
    // people understand why an unspecified bucket might exist and what they
    // can do about it.
    static let paymentMethods = InsightInfo(
        title: "Payment Methods",
        symbol: "creditcard.fill",
        accent: .appPrimary,
        description: "How the spending in the current view splits across the payment methods you've recorded — so you can see at a glance how much went on credit, debit, cash, UPI, and the rest.",
        formula: "Each slice = (net spend tagged to that method) ÷ (total net spend in view) × 100. Refunds reduce their original method's slice. Expenses without a payment method tagged are excluded from the donut and surfaced as a 'tag more' nudge below.",
        tip: "Capturing the method on every expense takes one extra tap and instantly powers a credit-vs-cash flow view. Tap any slice to see the exact amount and count for that method."
    )

    static let trend = InsightInfo(
        title: "Trend",
        symbol: "chart.line.uptrend.xyaxis",
        accent: .appPrimary,
        description: "How your spending evolves across the selected period. The card has three pages: a time-series line chart, an average-by-weekday bar chart, and your five biggest single-day spends.",
        formula: "Over time: daily totals plotted chronologically. By weekday: total on each weekday ÷ number of times that weekday appears in the range. Top days: startOfDay totals, sorted descending.",
        tip: "Swipe between the three pages — each answers a different question: 'how is my spending moving?', 'which day of the week costs me most?', and 'which specific days blew the budget?'."
    )
}

// MARK: - Info Button

/// Small `info.circle` button that opens an explanation sheet for a given stat.
/// Used in the Pro Insights cards. The button manages its own presentation state so
/// each card is self-contained.
struct InsightInfoButton: View {
    let info: InsightInfo
    @State private var isPresented = false

    var body: some View {
        Button {
            HapticManager.shared.lightTap()
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
                .padding(2) // larger hit target
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("About \(info.title)"))
        .sheet(isPresented: $isPresented) {
            InsightExplanationSheet(info: info)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Explanation Sheet

/// Bottom-sheet explanation for a Pro Insights stat. Three clearly-labelled sections
/// keep the layout scannable: "What it means", "How it's calculated", "Why it matters".
struct InsightExplanationSheet: View {
    let info: InsightInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header
                    sections
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.systemBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(info.accent.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: info.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(info.accent)
            }

            Text(info.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer(minLength: 0)
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            sectionRow(label: "What it means", body: info.description)
            sectionRow(label: "How it's calculated", body: info.formula)
            sectionRow(label: "Why it matters", body: info.tip)
        }
    }

    private func sectionRow(label: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.6)

            Text(body)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

struct InsightInfoButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            InsightInfoButton(info: .dailyPace)
            InsightInfoButton(info: .velocity)
            InsightInfoButton(info: .yearOverYear)

            InsightExplanationSheet(info: .velocity)
                .frame(height: 400)
        }
        .padding()
    }
}
