import SwiftUI

// MARK: - Insights on regular width (iPad, iPhone Duo inner display)
//
// The iPhone Insights is a long single column (hero → Pro → forecast →
// highlights → donut → payment methods → heatmap → trend → recap). On a
// big screen the same cached results tile into a dashboard:
//
//   ┌ Insights ─────────────────────────────── (+) [export] ┐
//   │ controls card (time frame · period · category)        │
//   │ ┌ TOTAL SPENT hero ──────┐ ┌ Pro Insights ──────────┐ │
//   │ └────────────────────────┘ └────────────────────────┘ │
//   │ ┌ Trend (full width, range picker anchored above) ──┐ │
//   │ ┌ Where It Goes ─────────┐ ┌ Payment Methods ───────┐ │
//   │ ┌ Spending Pattern ──────┐ ┌ Forecast ──────────────┐ │
//   │ ┌ Highlights (2-col grid) ───────────────────────────┐ │
//   │ ┌ Monthly Recap ─────────────────────────────────────┐ │
//
// Even pairs everywhere so a Duo fold in book pose runs down the gutter,
// never through a chart. Below `LargeScreenLayout.twoColumnMinimumWidth`
// (`usesTwoColumns == false`) or at accessibility Dynamic Type the pairs
// stack in the iPhone order. The trend section keeps its
// `DuoArrangement` wrapper (an `ArrangementView(.split)` candidate on
// iOS 27.1) so the pager tabs and the chart can land on opposite halves
// of a partially folded display.
//
// Only reached from `StatisticsView.body` when `isWideLayout`. State,
// recompute pipeline and sheets are unchanged and shared.
extension StatisticsView {

    var largeScreenContent: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            largeScreenHeader
            controlSection

            if viewModel.expenses.isEmpty {
                emptyStateView
            } else {
                largeScreenStatistics
            }
        }
        .padding(.horizontal, LargeScreenLayout.horizontalPadding(for: measuredContentWidth))
        .padding(.bottom, Theme.Spacing.scrollBottomClearance)
        .frame(maxWidth: LargeScreenLayout.dashboardMaxWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    /// Title + subtitle leading; the placed "+" and the Pro-gated export
    /// button trailing. Same vertical rhythm as the compact header.
    private var largeScreenHeader: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: Theme.Spacing.xl)

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Insights")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(.primary)

                    Text(getHeaderSubtitle())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: Theme.Spacing.md) {
                    largeScreenAddAction
                    exportReportButton
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    // MARK: Tiles

    private var largeScreenStatistics: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            // Row 1: the number people came for, beside the Pro cards
            // (or the Pro teaser). Both were the first two sections on
            // the phone; here they share the first fold.
            LargeScreenColumns(twoColumns: usesTwoColumns) {
                Group {
                    if statsResultsReady {
                        heroOverviewSection
                    } else {
                        heroSkeleton
                    }
                }
                .modifier(SectionEntrance(order: 0, animate: animateCards))
            } trailing: {
                proInsightsBlock
                    .modifier(SectionEntrance(order: 1, animate: animateCards))
            }

            if cachedFilteredCount > 0 {
                // Row 2: the trend chart wants every point of width it
                // can get; on a 1100pt column its adaptive height caps
                // at 420pt, which is a real chart rather than a strip.
                trendSection
                    .modifier(SectionEntrance(order: 2, animate: animateCards))
                    .sectionScrollTransition()

                if showsPaymentMethodsSection {
                    // Row 3: composition — two donuts side by side.
                    LargeScreenColumns(twoColumns: usesTwoColumns) {
                        whereItGoesSection
                            .modifier(SectionEntrance(order: 3, animate: animateCards))
                            .sectionScrollTransition()
                    } trailing: {
                        paymentMethodsSection
                            .modifier(SectionEntrance(order: 4, animate: animateCards))
                            .sectionScrollTransition()
                    }

                    // Row 4: pattern (past) beside forecast (future).
                    LargeScreenColumns(twoColumns: usesTwoColumns) {
                        spendingPatternSection
                            .modifier(SectionEntrance(order: 5, animate: animateCards))
                            .sectionScrollTransition()
                    } trailing: {
                        forecastBlock
                            .modifier(SectionEntrance(order: 6, animate: animateCards))
                            .sectionScrollTransition()
                    }
                } else {
                    // No payment-method data (free user, nothing tagged):
                    // the section is empty, so pair the donut with the
                    // heatmap instead of leaving it beside a blank half,
                    // and give the forecast the full width.
                    LargeScreenColumns(twoColumns: usesTwoColumns) {
                        whereItGoesSection
                            .modifier(SectionEntrance(order: 3, animate: animateCards))
                            .sectionScrollTransition()
                    } trailing: {
                        spendingPatternSection
                            .modifier(SectionEntrance(order: 4, animate: animateCards))
                            .sectionScrollTransition()
                    }

                    forecastBlock
                        .modifier(SectionEntrance(order: 5, animate: animateCards))
                        .sectionScrollTransition()
                }
            } else {
                // Nothing in the filtered window: the forecast still
                // reads from the full history, so it keeps its slot.
                forecastBlock
                    .modifier(SectionEntrance(order: 2, animate: animateCards))
            }

            // Highlights already lay out in a two-column grid on
            // `usesTwoColumns`, so the full-width slot is right for it.
            if !insights.isEmpty {
                highlightsSection
                    .modifier(SectionEntrance(order: 7, animate: animateCards))
                    .sectionScrollTransition()
            }

            if cachedHasLastMonthData {
                monthlyRecapRow
                    .modifier(SectionEntrance(order: 8, animate: animateCards))
                    .sectionScrollTransition()
            }
        }
    }
}
