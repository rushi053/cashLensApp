import SwiftUI

/// Month-in-review sheet — the calm CashLens take on a "wrapped"
/// moment (think Apple Fitness monthly summary, not Spotify Wrapped).
///
/// v2 rebuild of the deleted paged-story recap: instead of a
/// full-screen `TabView` with per-page tinted backgrounds, this is a
/// single scrolling sequence of design-system cards (elevated white,
/// hairline borders, entrance cascade) so it reads as part of the
/// app, not a marketing interstitial. Ends with a `ShareLink` that
/// exports a rendered summary card (`ImageRenderer`) — the recap is
/// free for everyone because a shared card is organic growth.
///
/// Entry points:
///   • Today tab — automatic "Your June recap is ready" card during
///     the first few days of a new month (dismisses after viewing).
///   • Insights tab — a permanent "Monthly Recap" row.
///
/// Both present `MonthlyRecapSheet`, which owns the compute: it waits
/// for full hydration (the engine must see the whole month, not the
/// windowed launch slice), computes off-main, then renders this view.
struct MonthlyRecapView: View {
    let recap: MonthlyRecap
    let formattedAmount: (Double) -> String

    @Environment(\.dismiss) private var dismiss
    @State private var animateSections = false
    @State private var shareImage: Image? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header
                    .modifier(SectionEntrance(order: 0, animate: animateSections))

                heroCard
                    .modifier(SectionEntrance(order: 1, animate: animateSections))

                if recap.topCategoryName != nil {
                    topCategoryCard
                        .modifier(SectionEntrance(order: 2, animate: animateSections))
                }

                HStack(spacing: Theme.Spacing.md) {
                    busiestDayCard
                    biggestExpenseCard
                }
                .modifier(SectionEntrance(order: 3, animate: animateSections))

                quietDaysCard
                    .modifier(SectionEntrance(order: 4, animate: animateSections))

                if recap.subscriptionTotal > 0 {
                    subscriptionsCard
                        .modifier(SectionEntrance(order: 5, animate: animateSections))
                }

                awardCard
                    .modifier(SectionEntrance(order: 6, animate: animateSections))

                shareRow
                    .modifier(SectionEntrance(order: 7, animate: animateSections))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            // `xl` top — the sheet-header convention's clear-air gap
            // below the grab handle (was `lg`, which read cramped).
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Color.systemBackground)
        .onAppear {
            HapticManager.shared.success()
            withAnimation { animateSections = true }
            renderShareImage()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MONTH IN REVIEW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundColor(.secondary)
                Text(Self.monthTitleFormatter.string(from: recap.month))
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(.primary)
            }

            Spacer()

            // Shared close-button chrome (SheetCloseButton) so every
            // sheet's X reads identically.
            SheetCloseButton(action: { dismiss() })
        }
    }

    // MARK: - Cards

    /// Headline: total spent + delta vs last month + expense count.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            eyebrow(icon: "chart.bar.fill", label: "YOU SPENT", tint: .appPrimary)

            Text(formattedAmount(recap.totalSpent))
                .font(Theme.Typography.heroNumeric)
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let delta = recap.monthOverMonthDelta {
                let up = delta >= 0
                HStack(spacing: 5) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(String(format: "%.0f%% vs %@", abs(delta * 100), previousMonthName))
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(up ? .orange : .green)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 5)
                .background(Capsule().fill((up ? Color.orange : Color.green).opacity(0.12)))
            } else {
                Text("Your first full month — nothing to compare yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("\(recap.expenseCount) \(recap.expenseCount == 1 ? "expense" : "expenses") logged")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .cardSurface(radius: Theme.Radius.hero)
    }

    /// Top category with a share bar.
    private var topCategoryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            eyebrow(icon: "square.stack.3d.up.fill", label: "MOST OF IT WENT TO", tint: .appPrimary)

            HStack(alignment: .firstTextBaseline) {
                Text(recap.topCategoryName ?? "Other")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: Theme.Spacing.sm)
                Text(formattedAmount(recap.topCategoryAmount))
                    .font(Theme.Typography.numeric)
                    .monospacedDigit()
                    .foregroundColor(.appPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appPrimary.opacity(0.12))
                    Capsule()
                        .fill(Color.appPrimary)
                        .frame(width: max(8, geo.size.width * CGFloat(min(recap.topCategoryShare, 1))))
                }
            }
            .frame(height: 10)

            Text("That's \(Int((recap.topCategoryShare * 100).rounded()))% of everything you spent.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    /// Busiest single day of the month.
    private var busiestDayCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            eyebrow(icon: "calendar", label: "BIGGEST DAY", tint: .orange)

            Text(recap.busiestDayDate.map { Self.dayFormatter.string(from: $0) } ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(formattedAmount(recap.busiestDayAmount))
                .font(Theme.Typography.numericSmall)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    /// Biggest single expense.
    private var biggestExpenseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            eyebrow(icon: "creditcard.fill", label: "BIGGEST EXPENSE", tint: .pink)

            Text(recap.biggestExpenseTitle?.isEmpty == false ? recap.biggestExpenseTitle! : "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(formattedAmount(recap.biggestExpenseAmount))
                .font(Theme.Typography.numericSmall)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    /// No-spend days + best in-month streak.
    private var quietDaysCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                eyebrow(icon: "leaf.fill", label: "QUIET DAYS", tint: .mint)

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text("\(recap.noSpendDays)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text(recap.noSpendDays == 1 ? "no-spend day" : "no-spend days")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.mint)
                }

                Text(quietDaysCommentary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if recap.bestNoSpendStreak >= 2 {
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                    Text("\(recap.bestNoSpendStreak)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text("day streak")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
            }
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    /// Fixed costs (subscription-generated expenses).
    private var subscriptionsCard: some View {
        let share = recap.totalSpent > 0 ? recap.subscriptionTotal / recap.totalSpent : 0
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Subscriptions")
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Text("\(Int((share * 100).rounded()))% of the month was fixed costs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(formattedAmount(recap.subscriptionTotal))
                .font(Theme.Typography.numericSmall)
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    /// The award medallion — the closing beat.
    private var awardCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Award ring: a single hairline circle around the
            // hierarchical glyph — medal without the sticker fill.
            ZStack {
                Circle()
                    .stroke(Color.appPrimary.opacity(0.25), lineWidth: Theme.Stroke.medium)
                    .frame(width: 88, height: 88)
                Image(systemName: recap.award.symbol)
                    .font(.system(size: 38, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.appPrimary)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(recap.award.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(recap.award.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .cardSurface(radius: Theme.Radius.hero)
    }

    // MARK: - Share

    /// Full-width ShareLink exporting the rendered summary card. The
    /// image is pre-rendered in `onAppear` (small view, milliseconds)
    /// so the share sheet opens instantly.
    @ViewBuilder
    private var shareRow: some View {
        if let shareImage {
            ShareLink(
                item: shareImage,
                preview: SharePreview(
                    "\(Self.monthTitleFormatter.string(from: recap.month)) Recap",
                    image: shareImage
                )
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Share your month")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md + 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Color.appPrimary)
                )
                .primaryGlow(strength: 0.25)
            }
            .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.mediumTap() })
        }
    }

    /// Renders `MonthlyRecapShareCard` to a `UIImage` at 3× so the
    /// exported card is crisp on any share target. Forced light mode
    /// so the shared artefact is deterministic regardless of the
    /// sender's appearance setting.
    @MainActor
    private func renderShareImage() {
        let card = MonthlyRecapShareCard(recap: recap, formattedAmount: formattedAmount)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: nil)
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }

    // MARK: - Copy helpers

    private var quietDaysCommentary: String {
        switch recap.noSpendDays {
        case 0:      return "Every day had at least one expense."
        case 1...3:  return "A few quiet days sprinkled through the month."
        case 4...7:  return "Nice — a solid mix of quiet days."
        case 8...14: return "Strong — you found real space in your spending."
        default:     return "Outstanding — your wallet had room to breathe."
        }
    }

    private var previousMonthName: String {
        guard let prev = Calendar.current.date(byAdding: .month, value: -1, to: recap.month) else { return "last month" }
        return Self.monthOnlyFormatter.string(from: prev)
    }

    private func eyebrow(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundColor(.secondary)
        }
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    private static let monthOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d"
        return f
    }()
}

// MARK: - Self-computing sheet wrapper

/// Owns the recap compute so entry points (Today card, Insights row)
/// just present a sheet with a month. Waits for full hydration first —
/// with windowed hydration the in-memory array may only hold the
/// recent launch slice for a beat after cold start, and a recap built
/// on partial data would silently under-report the month.
struct MonthlyRecapSheet: View {
    /// Any date inside the month to recap (typically last month).
    let month: Date

    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    @State private var recap: MonthlyRecap? = nil

    var body: some View {
        Group {
            if let recap {
                MonthlyRecapView(
                    recap: recap,
                    formattedAmount: viewModel.formattedAmount
                )
            } else {
                loadingSkeleton
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            // Mark the recap month as seen so Today's automatic card
            // dismisses after viewing (both entry points count).
            UserDefaults.standard.set(
                MonthlyRecapEngine.monthKey(for: month),
                forKey: UserDefaultsKeys.monthlyRecapLastSeenMonth
            )
        }
        .task {
            guard recap == nil else { return }
            await viewModel.waitUntilFullyHydrated()
            let expensesSnapshot = viewModel.expenses
            let names: [UUID: String] = Dictionary(
                uniqueKeysWithValues: categoryViewModel.customCategories.map { ($0.id, $0.name) }
            )
            let targetMonth = month
            let computed = await Task.detached(priority: .userInitiated) {
                MonthlyRecapEngine.compute(
                    month: targetMonth,
                    allExpenses: expensesSnapshot,
                    customCategoryNames: names
                )
            }.value
            recap = computed
        }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: 8).fill(Color.tertiarySystemBackground).frame(width: 140, height: 14)
            RoundedRectangle(cornerRadius: 12).fill(Color.tertiarySystemBackground).frame(width: 200, height: 34)
            RoundedRectangle(cornerRadius: Theme.Radius.hero).fill(Color.tertiarySystemBackground).frame(height: 160)
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Color.tertiarySystemBackground).frame(height: 120)
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Color.tertiarySystemBackground).frame(height: 120)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
    }
}

// MARK: - Shareable summary card

/// The image users actually share — a compact, brand-forward summary
/// rendered by `ImageRenderer` (never shown live in the UI). Fixed
/// 360pt width, rendered at 3× for a crisp 1080px export. Light
/// palette, solid fills, no gradients — the shared card should look
/// like the app.
private struct MonthlyRecapShareCard: View {
    let recap: MonthlyRecap
    let formattedAmount: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Brand row
            HStack {
                Text("CashLens")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)
                Spacer()
                Text("MONTH IN REVIEW")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.secondary)
            }

            // Month + total
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.monthYearFormatter.string(from: recap.month))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(formattedAmount(recap.totalSpent))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let delta = recap.monthOverMonthDelta {
                    let up = delta >= 0
                    Text(String(format: "%@%.0f%% vs last month", up ? "↑ " : "↓ ", abs(delta * 100)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(up ? .orange : .green)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            // Stat rows
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let top = recap.topCategoryName {
                    shareStat(icon: "square.stack.3d.up.fill", tint: .appPrimary,
                              label: "Top category",
                              value: "\(top) · \(Int((recap.topCategoryShare * 100).rounded()))%")
                }
                if recap.busiestDayDate != nil {
                    shareStat(icon: "calendar", tint: .orange,
                              label: "Biggest day",
                              value: formattedAmount(recap.busiestDayAmount))
                }
                shareStat(icon: "leaf.fill", tint: .mint,
                          label: "No-spend days",
                          value: "\(recap.noSpendDays)")
                shareStat(icon: recap.award.symbol, tint: .appPrimary,
                          label: "Award",
                          value: recap.award.title)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 360, alignment: .leading)
        .background(Color.white)
    }

    private func shareStat(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
