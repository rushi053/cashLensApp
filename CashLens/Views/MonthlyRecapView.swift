import SwiftUI

/// Full-screen, swipeable "story" recap of last month — the
/// CashLens take on Spotify Wrapped. Pro feature; surfaced as a
/// card on the Insights tab and as a row in You → Pro section.
///
/// Page order (engine returns nil for missing pages, which we skip):
///   1. Intro / month title
///   2. Headline — total spent + delta vs previous month
///   3. Top category
///   4. Biggest single expense
///   5. No-spend days
///   6. Award badge
///   7. Outro / share + close
///
/// Interaction model:
///   • Horizontal swipe between pages (`TabView` with `.page` style).
///   • Swipe-down to dismiss.
///   • A persistent "Done" pill in the top-right is the
///     primary exit so users on smaller devices don't fight the
///     swipe-down gesture.
struct MonthlyRecapView: View {
    let recap: MonthlyRecap
    let currencySymbol: String
    let formattedAmount: (Double) -> String

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var animateContent = false

    var body: some View {
        ZStack {
            // Page-aware tinted background. Each page's primary
            // accent gently bleeds onto the screen so the story
            // feels cohesive across pages but visually distinct
            // per chapter.
            backgroundForCurrentPage
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                IntroPage(recap: recap)
                    .tag(0)

                HeadlinePage(
                    recap: recap,
                    currencySymbol: currencySymbol,
                    formattedAmount: formattedAmount
                )
                .tag(1)

                if recap.topCategoryName != nil {
                    TopCategoryPage(
                        recap: recap,
                        formattedAmount: formattedAmount
                    )
                    .tag(2)
                }

                if let title = recap.biggestExpenseTitle, !title.isEmpty {
                    BiggestExpensePage(
                        recap: recap,
                        title: title,
                        formattedAmount: formattedAmount
                    )
                    .tag(3)
                }

                if recap.noSpendDays > 0 {
                    NoSpendPage(recap: recap)
                        .tag(4)
                }

                AwardPage(recap: recap)
                    .tag(5)

                OutroPage(onDone: { dismiss() })
                    .tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .animation(Theme.Motion.snappy, value: currentPage)

            // Top "Done" pill — always visible regardless of page.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        HapticManager.shared.lightTap()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 2)
                            .background(
                                Capsule().fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                Spacer()
            }
        }
        .onAppear {
            HapticManager.shared.success()
            withAnimation(.easeOut(duration: 0.6)) {
                animateContent = true
            }
        }
        .onChange(of: currentPage) { _, _ in
            HapticManager.shared.lightTap()
        }
    }

    @ViewBuilder
    private var backgroundForCurrentPage: some View {
        let tint: Color = {
            switch currentPage {
            case 0:  return Color.appPrimary
            case 1:  return (recap.monthOverMonthDelta ?? 0) >= 0 ? Color.orange : Color.green
            case 2:  return Color.appPrimary
            case 3:  return Color.pink
            case 4:  return Color.mint
            case 5:  return Color.appPrimary
            default: return Color.appPrimary
            }
        }()
        // Soft tint over the system background — never a true
        // gradient, just a calm wash that lets the cards float.
        ZStack {
            Color(uiColor: .systemBackground)
            tint.opacity(0.10)
        }
    }
}

// MARK: - Pages

private struct IntroPage: View {
    let recap: MonthlyRecap

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Color.appPrimary)
                .scaleEffect(didAppear ? 1 : 0.6)
                .opacity(didAppear ? 1 : 0)

            VStack(spacing: Theme.Spacing.sm) {
                Text("YOUR")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundColor(.secondary)

                Text(Self.monthYearFormatter.string(from: recap.month))
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("RECAP")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(8)
                    .foregroundColor(.appPrimary)
            }
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 12)

            Spacer()

            Text("Swipe to explore →")
                .font(.footnote.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.bottom, Theme.Spacing.xxxl)
                .opacity(didAppear ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.7)) {
                didAppear = true
            }
        }
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()
}

private struct HeadlinePage: View {
    let recap: MonthlyRecap
    let currencySymbol: String
    let formattedAmount: (Double) -> String

    @State private var didAppear = false
    @State private var animatedAmount: Double = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Text("YOU SPENT")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)

            Text(formattedAmount(animatedAmount))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())

            if let delta = recap.monthOverMonthDelta {
                let up = delta >= 0
                HStack(spacing: 6) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                    Text(String(format: "%.1f%% vs previous month", abs(delta * 100)))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(up ? .orange : .green)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs + 2)
                .background(Capsule().fill((up ? Color.orange : Color.green).opacity(0.14)))
                .opacity(didAppear ? 1 : 0)
            } else {
                Text("Your first full month — nothing to compare yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Text("\(recap.expenseCount) \(recap.expenseCount == 1 ? "expense" : "expenses") logged")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, Theme.Spacing.sm)
                .opacity(didAppear ? 1 : 0)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Spacing.xl)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) {
                animatedAmount = recap.totalSpent
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                didAppear = true
            }
        }
    }
}

private struct TopCategoryPage: View {
    let recap: MonthlyRecap
    let formattedAmount: (Double) -> String

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Text("MOST OF IT WENT TO")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)

            Text(recap.topCategoryName ?? "Other")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(didAppear ? 1 : 0.8)
                .opacity(didAppear ? 1 : 0)

            Text(formattedAmount(recap.topCategoryAmount))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.appPrimary)
                .padding(.top, Theme.Spacing.sm)
                .opacity(didAppear ? 1 : 0)

            // Share bar — visualizes the % of total spend that
            // went to the top category. Reads better than just
            // saying "39% of your spend".
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("That's \(Int((recap.topCategoryShare * 100).rounded()))% of everything you spent.")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                shareBar
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.lg)
            .opacity(didAppear ? 1 : 0)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                didAppear = true
            }
        }
    }

    private var shareBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(height: 12)
                Capsule()
                    .fill(Color.appPrimary)
                    .frame(width: width * (didAppear ? CGFloat(recap.topCategoryShare) : 0), height: 12)
                    .animation(.easeOut(duration: 0.9).delay(0.3), value: didAppear)
            }
        }
        .frame(height: 12)
    }
}

private struct BiggestExpensePage: View {
    let recap: MonthlyRecap
    let title: String
    let formattedAmount: (Double) -> String

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Text("YOUR BIGGEST EXPENSE")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)

            Image(systemName: "creditcard.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundColor(.pink)
                .padding(.bottom, Theme.Spacing.md)
                .scaleEffect(didAppear ? 1 : 0.6)
                .opacity(didAppear ? 1 : 0)

            Text("\u{201C}\(title)\u{201D}")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, Theme.Spacing.xl)
                .opacity(didAppear ? 1 : 0)

            Text(formattedAmount(recap.biggestExpenseAmount))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.pink)
                .padding(.top, Theme.Spacing.sm)
                .opacity(didAppear ? 1 : 0)

            if recap.biggestExpenseDay > 0 {
                Text("on the \(ordinal(recap.biggestExpenseDay))")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.top, Theme.Spacing.xs)
                    .opacity(didAppear ? 1 : 0)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                didAppear = true
            }
        }
    }

    private func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: n as NSNumber) ?? "\(n)"
    }
}

private struct NoSpendPage: View {
    let recap: MonthlyRecap

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "leaf.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(.mint)
                .scaleEffect(didAppear ? 1 : 0.5)
                .opacity(didAppear ? 1 : 0)

            Text("YOU HAD")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)

            Text("\(recap.noSpendDays)")
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .opacity(didAppear ? 1 : 0)

            Text(recap.noSpendDays == 1 ? "no-spend day" : "no-spend days")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.mint)
                .padding(.top, -Theme.Spacing.sm)
                .opacity(didAppear ? 1 : 0)

            Text(commentary)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.md)
                .opacity(didAppear ? 1 : 0)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.7)) {
                didAppear = true
            }
        }
    }

    private var commentary: String {
        switch recap.noSpendDays {
        case 0:      return "Every day had at least one expense."
        case 1...3:  return "A few quiet days sprinkled through the month."
        case 4...7:  return "Nice — a solid mix of quiet days."
        case 8...14: return "Strong — you found real space in your spending."
        default:     return "Outstanding — your wallet had room to breathe."
        }
    }
}

private struct AwardPage: View {
    let recap: MonthlyRecap

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Text("YOUR AWARD")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)

            // The badge medallion — circular, accent-tinted, with
            // the award icon centered. Scaled in on appear.
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 160, height: 160)
                Image(systemName: recap.award.symbol)
                    .font(.system(size: 64, weight: .regular))
                    .foregroundColor(.appPrimary)
            }
            .scaleEffect(didAppear ? 1 : 0.4)
            .opacity(didAppear ? 1 : 0)
            .padding(.bottom, Theme.Spacing.md)

            Text(recap.award.title)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
                .opacity(didAppear ? 1 : 0)

            Text(recap.award.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xs)
                .opacity(didAppear ? 1 : 0)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                didAppear = true
            }
            HapticManager.shared.success()
        }
    }
}

private struct OutroPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(.appPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                Text("That's a wrap.")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)

                Text("Here's to another mindful month.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md + 2)
                    .background(Color.appPrimary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
