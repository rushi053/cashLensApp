import SwiftUI

/// "Pro Insights" section inserted into the Statistics screen.
///
/// For Pro users this renders three data-rich cards (daily pace, velocity, YoY chart).
/// For free users it renders a single premium teaser that funnels into the paywall —
/// no layout jump between the two states, so upgrading feels like the view *lights up*
/// rather than moves.
struct ProInsightsSection: View {
    let isPro: Bool
    let dailyPace: AdvancedStatsCalculator.DailyPace
    let velocity: AdvancedStatsCalculator.Velocity
    let yearOverYearPoints: [AdvancedStatsCalculator.YearOverYearPoint]
    let accent: Color
    let formattedAmount: (Double) -> String
    let onUpgradeTap: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            header

            if isPro {
                proContent
            } else {
                teaserContent
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text("Pro Insights")
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(.primary)

            proPill

            Spacer()
        }
    }

    private var proPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("PRO")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.5)
        }
        .foregroundColor(.white)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.appPrimary)
        )
    }

    // MARK: - Pro Content

    @ViewBuilder
    private var proContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                DailyPaceCard(pace: dailyPace, accent: accent, formattedAmount: formattedAmount)
                VelocityCard(velocity: velocity, accent: accent, formattedAmount: formattedAmount)
            }

            if AdvancedStatsCalculator.hasAnyData(yearOverYearPoints) {
                YearOverYearCard(
                    points: yearOverYearPoints,
                    accent: accent,
                    formattedAmount: formattedAmount
                )
            }
        }
    }

    // MARK: - Teaser (free users)

    private var teaserContent: some View {
        Button(action: {
            HapticManager.shared.mediumTap()
            onUpgradeTap()
        }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient.appPrimaryDiagonal)
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.appPrimary.opacity(0.35), radius: 10, x: 0, y: 6)

                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unlock Pro Insights")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("See daily pace, spending velocity, year-over-year comparisons, and export PDF reports.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }

                teaserPreviewRow

                HStack {
                    Text("Try Pro")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .background(
                    Capsule()
                        .fill(Color.appPrimary)
                )
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .stroke(LinearGradient.appPrimary, lineWidth: 1.2)
                    .opacity(0.35)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .padding(Theme.Spacing.md)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var teaserPreviewRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            teaserPreviewPill(icon: "calendar.day.timeline.left", label: "Daily pace")
            teaserPreviewPill(icon: "bolt.fill", label: "Velocity")
            teaserPreviewPill(icon: "chart.bar.xaxis", label: "YoY")
        }
    }

    private func teaserPreviewPill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundColor(.appPrimary)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.appPrimary.opacity(0.12))
        )
    }
}

// MARK: - Daily Pace Card

private struct DailyPaceCard: View {
    let pace: AdvancedStatsCalculator.DailyPace
    let accent: Color
    let formattedAmount: (Double) -> String

    private var deltaText: String? {
        guard let change = pace.changePercent else { return nil }
        let arrow = change >= 0 ? "↑" : "↓"
        let capped = min(abs(change), 999)
        return "\(arrow) \(String(format: "%.1f", capped))%"
    }

    private var deltaColor: Color {
        guard let change = pace.changePercent else { return .secondary }
        return change >= 0 ? .red : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text("Daily Pace")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                InsightInfoButton(info: .dailyPace)
            }

            Text(formattedAmount(pace.dailyAverage))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 6) {
                if let delta = deltaText {
                    Text(delta)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(deltaColor)
                }
                Text(pace.changePercent == nil ? "per day" : "vs previous")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .cardSurface()
        .softShadow()
    }
}

// MARK: - Velocity Card

private struct VelocityCard: View {
    let velocity: AdvancedStatsCalculator.Velocity
    let accent: Color
    let formattedAmount: (Double) -> String

    private var titleLabel: String {
        velocity.state == .projecting ? "On Pace For" : "Final Total"
    }

    private var deltaText: String? {
        guard let change = velocity.changePercent else { return nil }
        let arrow = change >= 0 ? "↑" : "↓"
        let capped = min(abs(change), 999)
        return "\(arrow) \(String(format: "%.1f", capped))%"
    }

    private var deltaColor: Color {
        guard let change = velocity.changePercent else { return .secondary }
        return change >= 0 ? .red : .green
    }

    private var iconName: String {
        switch velocity.state {
        case .projecting:
            return "bolt.fill"
        case .completed:
            return "checkmark.seal.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text(titleLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                InsightInfoButton(info: .velocity)
            }

            Text(formattedAmount(velocity.projectedTotal))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 6) {
                if let delta = deltaText {
                    Text(delta)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(deltaColor)
                    Text("vs previous")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if velocity.state == .projecting {
                    Text("\(Int(velocity.progress * 100))% through")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("period ended")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .cardSurface()
        .softShadow()
    }
}

// MARK: - YoY Card (chart wrapped in a card surface)

private struct YearOverYearCard: View {
    let points: [AdvancedStatsCalculator.YearOverYearPoint]
    let accent: Color
    let formattedAmount: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text("Year over Year")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                InsightInfoButton(info: .yearOverYear)
            }

            YearOverYearChart(points: points, accent: accent, formattedAmount: formattedAmount)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .softShadow()
    }
}
