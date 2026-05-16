import SwiftUI

/// "Forecast" section on the Statistics screen.
///
/// For Pro users this renders a horizon switcher (30/60/90 days), a headline
/// projected total with confidence range, the forecast chart, and supporting
/// sub-cards (subscription impact, top spending driver). For free users it
/// renders a single premium teaser that funnels into the paywall — laid out
/// to match the Pro Insights teaser so the screen feels uniform.
///
/// All compute happens upstream in `StatisticsView.recomputeStatsNow` and is
/// passed in via `forecast`. This view is render-only.
struct ForecastSection: View {
    let isPro: Bool
    let forecast: ForecastEngine.Forecast
    let horizon: Horizon
    let topDriverDisplayName: String?
    let topDriverColor: Color?
    let accent: Color
    let formattedAmount: (Double) -> String
    /// Active currency, threaded through so any money-displaying `Text`
    /// paired with `.contentTransition(.numericText())` can include it in
    /// its animation key. Without this, switching currency in Settings
    /// leaves the old symbol on screen because the numericText cache
    /// keys off the underlying amount (which doesn't move).
    let currency: Expense.Currency
    let onHorizonChange: (Horizon) -> Void
    let onUpgradeTap: () -> Void

    enum Horizon: Int, CaseIterable, Identifiable {
        case thirty = 30
        case sixty = 60
        case ninety = 90

        var id: Int { rawValue }
        var label: String { "\(rawValue)d" }
        var fullLabel: String {
            switch self {
            case .thirty: return "Next 30 days"
            case .sixty: return "Next 60 days"
            case .ninety: return "Next 90 days"
            }
        }
    }

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
            Text("Forecast")
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(.primary)

            proPill

            Spacer()

            if isPro {
                InsightInfoButton(info: .forecast)
            }
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

    // MARK: - Pro content

    @ViewBuilder
    private var proContent: some View {
        if forecast.dataQuality == .insufficient {
            insufficientDataCard
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                horizonSwitcher
                headlineCard
                if forecast.dataQuality == .limited {
                    limitedDataNote
                }

                HStack(spacing: Theme.Spacing.md) {
                    subscriptionImpactCard
                    topDriverCard
                }
            }
        }
    }

    // MARK: - Horizon switcher

    private var horizonSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(Horizon.allCases) { h in
                let selected = h == horizon
                Button {
                    HapticManager.shared.selectionChanged()
                    withAnimation(Theme.Motion.snappy) {
                        onHorizonChange(h)
                    }
                } label: {
                    Text(h.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(selected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule().fill(Color.appPrimary)
                            } else {
                                Capsule().fill(Color.clear)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule().fill(Color.tertiarySystemBackground)
        )
        .overlay(
            Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Headline card

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text("PROJECTED")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer(minLength: 0)
                Text(horizon.fullLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.tertiarySystemBackground)
                    )
            }

            Text(formattedAmount(forecast.projectedTotal))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .moneyAnimation(amount: forecast.projectedTotal, currency: currency)

            confidenceRow

            ForecastChart(forecast: forecast, accent: accent, formattedAmount: formattedAmount)

            legendRow
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .softShadow()
    }

    private var confidenceRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Range")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(formattedAmount(forecast.confidenceLow)) – \(formattedAmount(forecast.confidenceHigh))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
            if let endDate = forecast.horizonEnd {
                Text("through \(monthDay(endDate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendDot(color: accent, label: "Actual", solid: true)
            legendDot(color: accent.opacity(0.7), label: "Projected", solid: false)
            legendDot(color: .yellow, label: "Subscription", solid: true, isCircle: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String, solid: Bool, isCircle: Bool = false) -> some View {
        HStack(spacing: 5) {
            if isCircle {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            } else if solid {
                Capsule()
                    .fill(color)
                    .frame(width: 14, height: 3)
            } else {
                HStack(spacing: 2) {
                    Capsule().fill(color).frame(width: 4, height: 3)
                    Capsule().fill(color).frame(width: 4, height: 3)
                    Capsule().fill(color).frame(width: 4, height: 3)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sub-cards

    private var subscriptionImpactCard: some View {
        let total = max(forecast.projectedTotal, 0.01)
        let share = forecast.projectedSubscriptionTotal / total
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                Text("SUBSCRIPTIONS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.4)
                Spacer(minLength: 0)
            }

            Text(formattedAmount(forecast.projectedSubscriptionTotal))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 6) {
                Text("\(Int((share * 100).rounded()))%")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.appPrimary)
                Text("of forecast")
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

    private var topDriverCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(topDriverColor ?? accent)
                Text("TOP DRIVER")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.4)
                Spacer(minLength: 0)
            }

            Text(topDriverDisplayName ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 6) {
                if let share = forecast.topDriverCategory?.projectedShare {
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(topDriverColor ?? .appPrimary)
                    Text("of recent spend")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Need more data")
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

    // MARK: - Empty / limited states

    private var insufficientDataCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text("Building your forecast")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }

            Text("CashLens needs at least two weeks of spending history to project the next 30 days reliably. Keep logging — your forecast will appear here automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .softShadow()
    }

    private var limitedDataNote: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.appPrimary)
            Text("Forecast accuracy improves as you log more days.")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appPrimary.opacity(0.08))
        )
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
                        Text("See Where You're Heading")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Pro forecasts the next 30, 60, or 90 days using your habits and known subscriptions — with a confidence band so you know what's certain and what isn't.")
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
            teaserPreviewPill(icon: "calendar", label: "30 / 60 / 90d")
            teaserPreviewPill(icon: "arrow.triangle.2.circlepath", label: "Subs included")
            teaserPreviewPill(icon: "scope", label: "Confidence band")
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

    // MARK: - Helpers

    private func monthDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
