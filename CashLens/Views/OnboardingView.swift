import SwiftUI

/// First-run onboarding — v7 ("show, don't tell").
///
/// v6 got the structure right (value-first, zero asks, interactive
/// first expense). v7 is a craft pass grounded in what best-in-class
/// onboarding actually ships in 2025/26:
///
///   • **Narrative spine** (Arc-style pacing): the Welcome page plants
///     the three-part story — log in seconds / instant verdict /
///     private by design — as three pillars, and every later page pays
///     one of them off. The user hears the claim, then *experiences*
///     each one.
///   • **Input met with output** (Duolingo's 2024 onboarding insight —
///     every user action gets a visible response): after the user
///     saves their real first expense, the Finish page renders it
///     inside a live miniature Today card whose "spent" numeral counts
///     up from zero to their amount. Cause and effect, felt.
///   • **Data as motion** (Copilot Money): the Capability preview's
///     hero numeral now rolls up via `numericText`, the verdict ring
///     draws in, and the insights bars stagger — the preview *behaves*
///     like the product instead of picturing it.
///   • **Privacy as hero moment**: the #1 differentiator gets a
///     one-shot halo pulse on its shield and a cascading checklist
///     instead of a static card. Still calm — one pulse, no loops.
///   • **Reduce Motion**: every decorative reveal (offsets, scales,
///     ring draw-in, count-ups) collapses to a plain opacity fade or
///     final value when `accessibilityReduceMotion` is on.
///
/// Pages:
///
///   1. **Welcome**   — brand mark + the three story pillars.
///   2. **Privacy**   — "Your money stays your business": shield halo
///                      pulse + cascading no-account / no-cloud /
///                      no-trackers / offline checklist.
///   3. **Capability**— live-feeling Today verdict preview (numeral
///                      count-up, ring draw-in) + insights strip +
///                      quick-log chips (Siri / Widgets / Search).
///   4. **First expense** — interactive mini add-form that saves a
///                      REAL expense through `ExpenseViewModel`.
///                      Skippable. Once saved, the page's CTA flips to
///                      "Continue" so re-visiting can't double-save.
///   5. **Finish**    — if an expense was saved: a miniature live
///                      Today card showing *their* expense with the
///                      total counting up ("this is your Today screen
///                      — it updates as you spend"). If skipped: the
///                      calm sparkles send-off. No Pro pitch — the
///                      post-value auto-paywall owns that moment.
///
/// Flow contracts (v7.1):
///   • Currency defaults from the device locale (ExpenseViewModel's
///     `autoSelectCurrencyIfNeeded`). The first-expense page surfaces
///     it as a tappable chip on the amount field; opening that chip's
///     picker marks `hasShownCurrencyPicker` so the post-onboarding
///     picker is skipped. If the chip is never tapped,
///     `finishOnboarding` still leaves `hasShownCurrencyPicker`
///     unset and `CashLensApp`'s `onChange` presents the canonical
///     picker right after this overlay fades — nobody gets stuck
///     with a wrong locale guess.
///   • No notification permission ask (lives at budget creation).
///   • No Pro pitch (auto-paywall handles it post-value).
///   • No save toast (the toast host is mounted beneath this overlay).
///
/// Visual rules: `systemBackground` chrome, `Color.appPrimary`
/// accents, semantic colours only inside preview cards, canonical
/// tokens everywhere, no gradients, no confetti.
struct OnboardingView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Binding var showOnboarding: Bool

    @State private var currentStep: OnboardingStep = .welcome

    // MARK: - First-expense form state

    @State private var firstExpenseAmount: String = ""
    @State private var firstExpenseTitle: String = ""
    @State private var firstExpenseCategory: Expense.Category = .food
    /// Set after a successful save so the finish page can render the
    /// live landing card and the first-expense page can't double-save.
    @State private var firstExpenseSaved = false
    /// Snapshot of what was actually saved (title may have fallen back
    /// to the category name) — feeds the finish page's landing card.
    @State private var savedExpenseAmount: Double = 0
    @State private var savedExpenseTitle: String = ""
    @State private var savedExpenseCategory: Expense.Category = .food

    @FocusState private var focusedField: FirstExpenseField?
    private enum FirstExpenseField: Hashable { case amount, title }

    /// Currency chooser presented from the first-expense form's
    /// currency chip. The locale auto-pick is right for most users,
    /// but "Region = United States" phones (common outside the US)
    /// get USD — the chip makes the guess visible and fixable at the
    /// exact moment it first matters, instead of one screen later.
    @State private var showingCurrencyChooser = false

    /// Category chips offered on the first-expense page. A curated
    /// subset — the full picker (with custom categories) lives in the
    /// real Add sheet; onboarding only needs enough range that almost
    /// any "thing I bought today" has an obvious home.
    private let firstExpenseCategories: [Expense.Category] = [
        .food, .groceries, .transportation, .shopping, .entertainment, .other
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)

                TabView(selection: $currentStep) {
                    ForEach(OnboardingStep.allCases) { step in
                        pageContent(for: step)
                            .tag(step)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                ctaFooter
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xxxl)
            }
        }
        .onChange(of: currentStep) { _, newStep in
            HapticManager.shared.lightTap()
            // Defer auto-focus past the page-swipe animation so the
            // keyboard doesn't fight the slide-in.
            if newStep == .firstExpense && !firstExpenseSaved {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedField = .amount
                }
            } else {
                focusedField = nil
            }
        }
    }

    // MARK: - Top bar (progress + skip)

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.appPrimary)
                        .frame(
                            width: max(proxy.size.width * progressFraction, 8),
                            height: 4
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentStep)
                }
            }
            .frame(height: 4)

            Button {
                HapticManager.shared.mediumTap()
                finishOnboarding()
            } label: {
                Text("Skip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .background(
                        Capsule().fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            }
        }
    }

    private var progressFraction: CGFloat {
        let total = CGFloat(OnboardingStep.allCases.count)
        let current = CGFloat(currentStep.rawValue + 1)
        return current / total
    }

    private func isActive(_ step: OnboardingStep) -> Bool {
        currentStep == step
    }

    // MARK: - Per-page content

    @ViewBuilder
    private func pageContent(for step: OnboardingStep) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)

            hero(for: step)

            VStack(spacing: Theme.Spacing.sm + 2) {
                Text(step.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                Text(pageDescription(for: step))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.sm)
            }

            inlineControl(for: step)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Heros (per-step focal visual)

    @ViewBuilder
    private func hero(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeLogo()
        case .privacy:
            PrivacyHero(isActive: isActive(.privacy))
        case .capability:
            CapabilityPreviewStack(viewModel: viewModel, isActive: isActive(.capability))
        case .firstExpense:
            // The form is the star of this page — no competing hero.
            EmptyView()
        case .finish:
            if firstExpenseSaved {
                FirstExpenseLanding(
                    viewModel: viewModel,
                    amount: savedExpenseAmount,
                    title: savedExpenseTitle,
                    category: savedExpenseCategory,
                    isActive: isActive(.finish)
                )
            } else {
                IconBadge(symbol: "sparkles")
            }
        }
    }

    // MARK: - Per-step inline control (form / card / etc.)

    @ViewBuilder
    private func inlineControl(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            StoryPillars(isActive: isActive(.welcome))
        case .privacy:
            privacyChecklistCard
        case .firstExpense:
            firstExpenseForm
        case .capability, .finish:
            EmptyView()
        }
    }

    // MARK: - Privacy checklist card

    /// The four concrete promises behind "your money stays your
    /// business". Rows cascade in one at a time when the page becomes
    /// active — a checklist that *checks itself off* reads as proof,
    /// not marketing copy.
    private var privacyChecklistCard: some View {
        let active = isActive(.privacy)
        return VStack(spacing: 0) {
            FeatureRow(
                icon: "person.crop.circle.badge.xmark",
                title: "No account",
                subtitle: "Nothing to sign up for. Ever."
            )
            .cascadeIn(0, active: active, baseDelay: 0.25)
            Divider().padding(.leading, 56).opacity(0.4)
            FeatureRow(
                icon: "icloud.slash.fill",
                title: "No cloud",
                subtitle: "Your data lives on this device, full stop."
            )
            .cascadeIn(1, active: active, baseDelay: 0.25)
            Divider().padding(.leading, 56).opacity(0.4)
            FeatureRow(
                icon: "eye.slash.fill",
                title: "No trackers",
                subtitle: "Zero analytics, zero ads, zero sharing."
            )
            .cascadeIn(2, active: active, baseDelay: 0.25)
            Divider().padding(.leading, 56).opacity(0.4)
            FeatureRow(
                icon: "wifi.slash",
                title: "Works offline",
                subtitle: "Airplane mode? Everything still works."
            )
            .cascadeIn(3, active: active, baseDelay: 0.25)
        }
        .cardSurface()
        .frame(maxWidth: 360)
    }

    // MARK: - First-expense mini form

    /// A deliberately tiny version of the real Add sheet: amount,
    /// six category chips, optional title. Saving writes a REAL
    /// expense through `ExpenseViewModel.addExpense`, so the user's
    /// Today tab is alive the moment onboarding fades out.
    private var firstExpenseForm: some View {
        let active = isActive(.firstExpense)
        return VStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                sectionLabel("HOW MUCH?")
                amountField
            }
            .cascadeIn(0, active: active, baseDelay: 0.1)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                sectionLabel("CATEGORY")
                categoryChips
            }
            .cascadeIn(1, active: active, baseDelay: 0.1)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                sectionLabel("WHAT WAS IT? (OPTIONAL)")
                titleField
            }
            .cascadeIn(2, active: active, baseDelay: 0.1)
        }
        .frame(maxWidth: 360)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.7)
            .foregroundColor(.secondary)
            .padding(.leading, Theme.Spacing.xs)
    }

    private var amountField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Tappable currency chip — shows the locale-detected
            // currency and opens the full picker. Kept inside the
            // field so the affordance is read in context ("this is
            // the currency your amounts will use").
            Button {
                HapticManager.shared.lightTap()
                showingCurrencyChooser = true
            } label: {
                HStack(spacing: 3) {
                    Text("\(viewModel.selectedCurrency.symbol) \(viewModel.selectedCurrency.rawValue)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Theme.Spacing.sm + 2)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.appPrimary.opacity(0.10)))
            }
            .buttonStyle(.plain)

            TextField("0", text: $firstExpenseAmount)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .amount)
        }
        .padding(.vertical, Theme.Spacing.md + 2)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .fieldCard(isFocused: focusedField == .amount)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .amount }
        .sheet(isPresented: $showingCurrencyChooser, onDismiss: {
            // The user has now seen (and possibly used) the canonical
            // picker — mark it consumed so `CashLensApp` doesn't
            // present the same picker again right after onboarding.
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
            viewModel.hasShownCurrencyPicker = true
        }) {
            CurrencyPickerView(viewModel: viewModel, isInitialSetup: true)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(firstExpenseCategories, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(_ category: Expense.Category) -> some View {
        let isSelected = firstExpenseCategory == category
        let tint = Color.forCategory(category.color)
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                firstExpenseCategory = category
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(category.displayName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? tint : .secondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                Capsule().stroke(
                    isSelected ? tint.opacity(0.55) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var titleField: some View {
        TextField("e.g. Coffee", text: $firstExpenseTitle)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .focused($focusedField, equals: .title)
            .submitLabel(.done)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .fieldCard(isFocused: focusedField == .title)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .title }
    }

    private var firstExpenseIsValid: Bool {
        (viewModel.parseAmount(firstExpenseAmount) ?? 0) > 0
    }

    // MARK: - CTA footer

    @ViewBuilder
    private var ctaFooter: some View {
        VStack(spacing: Theme.Spacing.md) {
            primaryCTA

            // "Skip for now" disappears once the expense is saved —
            // there's nothing left to skip.
            if let label = currentStep.secondaryCTA,
               !(currentStep == .firstExpense && firstExpenseSaved) {
                Button {
                    HapticManager.shared.lightTap()
                    handleSecondaryCTA()
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var primaryCTA: some View {
        Button {
            HapticManager.shared.mediumTap()
            handlePrimaryCTA()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(primaryCTALabel)
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: currentStep.isFinal ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md + 4)
            .background(primaryCTAEnabled ? Color.appPrimary : Color.gray.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .primaryGlow(strength: primaryCTAEnabled ? 0.28 : 0)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!primaryCTAEnabled)
        .animation(Theme.Motion.snappy, value: primaryCTAEnabled)
    }

    /// The first-expense page is the only one whose primary CTA can
    /// be disabled (until the amount parses) — the always-available
    /// exit is the "Skip for now" secondary underneath. Once an
    /// expense is saved the page becomes a plain "Continue" page.
    private var primaryCTAEnabled: Bool {
        currentStep != .firstExpense || firstExpenseSaved || firstExpenseIsValid
    }

    private var primaryCTALabel: String {
        switch currentStep {
        case .firstExpense:
            return firstExpenseSaved ? "Continue" : "Save Expense"
        default:
            return currentStep.isFinal ? "Get Started" : "Continue"
        }
    }

    // MARK: - CTA actions

    private func handlePrimaryCTA() {
        switch currentStep {
        case .firstExpense:
            if firstExpenseSaved {
                // User swiped back after saving — just move forward,
                // never double-save.
                advanceOrFinish()
            } else {
                saveFirstExpense()
            }
        default:
            advanceOrFinish()
        }
    }

    private func handleSecondaryCTA() {
        // Only the first-expense page has a secondary ("Skip for now").
        advanceOrFinish()
    }

    private func advanceOrFinish() {
        focusedField = nil
        if let next = currentStep.next {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                currentStep = next
            }
        } else {
            finishOnboarding()
        }
    }

    // MARK: - Side effects

    /// Persist the mini-form as a REAL expense. Title falls back to
    /// the category name — same convention users see from quick adds
    /// elsewhere. Fires the standard success haptic.
    ///
    /// No save toast is shown here by design: the toast is posted by
    /// the Add sheet's save path (not by `addExpense`), and its host
    /// is mounted under `MainTabView` — beneath this overlay — so
    /// nothing needs suppressing.
    private func saveFirstExpense() {
        guard let amountValue = viewModel.parseAmount(firstExpenseAmount), amountValue > 0 else { return }

        let trimmedTitle = firstExpenseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? firstExpenseCategory.displayName : trimmedTitle
        let expense = Expense(
            title: resolvedTitle,
            amount: amountValue,
            currency: viewModel.selectedCurrency,
            date: Date(),
            category: firstExpenseCategory
        )
        viewModel.addExpense(expense)
        HapticManager.shared.success()
        firstExpenseSaved = true
        savedExpenseAmount = amountValue
        savedExpenseTitle = resolvedTitle
        savedExpenseCategory = firstExpenseCategory
        advanceOrFinish()
    }

    private func pageDescription(for step: OnboardingStep) -> String {
        if step == .finish && firstExpenseSaved {
            return "That card is your Today screen in miniature — it updates the moment you spend. Add more anytime with the + button."
        }
        return step.description
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasCompletedOnboarding)
        // NOTE: `hasShownCurrencyPicker` is NOT set here. Two paths:
        //   • User opened the currency chip on the first-expense page
        //     → that sheet's onDismiss already marked the picker as
        //     shown, so `CashLensApp` skips the follow-up.
        //   • User never touched the chip → the flag is still false
        //     and `CashLensApp`'s `onChange(of: showOnboarding)`
        //     presents the canonical initial-setup picker right after
        //     this overlay fades, confirming the locale guess.
        withAnimation { showOnboarding = false }
    }
}

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable, Identifiable, Hashable {
    case welcome, privacy, capability, firstExpense, finish

    var id: Int { rawValue }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var isFinal: Bool { next == nil }

    var title: String {
        switch self {
        case .welcome:      return "Welcome to CashLens"
        case .privacy:      return "Your money stays your business"
        case .capability:   return "Know you’re on track"
        case .firstExpense: return "Log your first expense"
        case .finish:       return "You’re set"
        }
    }

    var description: String {
        switch self {
        case .welcome:
            return "Money clarity in seconds — not spreadsheets, not stress."
        case .privacy:
            return "Everything stays on this device. We can’t see your spending — and neither can anyone else."
        case .capability:
            return "A calm daily verdict, patterns you can plan around — and logging fast enough to actually stick."
        case .firstExpense:
            return "Takes five seconds — that’s the whole point."
        case .finish:
            return "Add expenses anytime with the + button. CashLens handles the rest."
        }
    }

    /// Only the first-expense page offers a soft exit.
    var secondaryCTA: String? {
        self == .firstExpense ? "Skip for now" : nil
    }
}

// MARK: - Cascade-in reveal
//
// Canonical staggered entrance for elements *inside* an onboarding
// page: fade + small rise, offset per index, replayed each time the
// page becomes the TabView selection. Deliberately applied to inner
// elements only (checklist rows, story pillars, form fields) — the
// page skeleton (title, description) stays visible during swipe drags
// so a half-dragged page is never blank.
//
// Reduce Motion: the rise is dropped entirely; the reveal collapses to
// a short plain fade.
private struct CascadeInModifier: ViewModifier {
    let index: Int
    let active: Bool
    let baseDelay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var delay: Double { baseDelay + Double(index) * 0.08 }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: (shown || reduceMotion) ? 0 : 10)
            .onAppear { update(active) }
            .onChange(of: active) { _, nowActive in update(nowActive) }
    }

    private func update(_ nowActive: Bool) {
        if nowActive {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.25).delay(delay)
                    : Theme.Motion.emphasized.delay(delay)
            ) {
                shown = true
            }
        } else {
            // Reset instantly (and invisibly — the page is off-screen)
            // so the cascade replays if the user swipes back.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { shown = false }
        }
    }
}

private extension View {
    func cascadeIn(_ index: Int, active: Bool, baseDelay: Double = 0.2) -> some View {
        modifier(CascadeInModifier(index: index, active: active, baseDelay: baseDelay))
    }
}

// MARK: - Welcome logo
//
// Real app brand mark. Hairline edge stroke that defines the shape on
// retina, plus a two-layer shadow stack — a soft brand-tinted halo
// for premium feel + a regular soft drop shadow for depth. Same
// approach Apple uses on Wallet card hero images.
private struct WelcomeLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateIn = false

    var body: some View {
        Image("Logo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .shadow(color: Color.appPrimary.opacity(0.22), radius: 30, x: 0, y: 14)
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
            .scaleEffect(animateIn || reduceMotion ? 1.0 : 0.86)
            .opacity(animateIn ? 1.0 : 0.0)
            .onAppear {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.3)
                        : .spring(response: 0.6, dampingFraction: 0.78)
                ) {
                    animateIn = true
                }
            }
            .frame(height: 160)
    }
}

// MARK: - Story pillars (Welcome)
//
// The three-part story the rest of onboarding pays off, planted as
// three compact pillars: log in seconds → instant verdict → private
// by design. Each later page demonstrates one of these, so the arc
// reads claim → proof instead of five unrelated slides.
private struct StoryPillars: View {
    let isActive: Bool

    private struct Pillar: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
    }

    private let pillars: [Pillar] = [
        Pillar(icon: "bolt.fill", label: "Log in\nseconds"),
        Pillar(icon: "speedometer", label: "Instant\nverdict"),
        Pillar(icon: "lock.fill", label: "Private\nby design")
    ]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            ForEach(Array(pillars.enumerated()), id: \.element.id) { idx, pillar in
                VStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary.opacity(0.10))
                            .frame(width: 46, height: 46)
                        Image(systemName: pillar.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }
                    Text(pillar.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .cascadeIn(idx, active: isActive, baseDelay: 0.45)
            }
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Privacy hero
//
// The shield badge with a single expanding halo pulse when the page
// becomes active — one calm "sealed" beat, not a looping alert. The
// pulse is skipped entirely under Reduce Motion.
private struct PrivacyHero: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateIn = false
    @State private var pulsed = false

    var body: some View {
        ZStack {
            // One-shot halo: expands ~1.5x while fading out.
            Circle()
                .stroke(Color.appPrimary.opacity(pulsed ? 0 : 0.30), lineWidth: 1.5)
                .frame(width: 100, height: 100)
                .scaleEffect(pulsed ? 1.5 : 1.0)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appPrimary)
        }
        .scaleEffect(animateIn || reduceMotion ? 1.0 : 0.86)
        .opacity(animateIn ? 1.0 : 0.0)
        .frame(height: 130)
        .onAppear { run(isActive) }
        .onChange(of: isActive) { _, nowActive in run(nowActive) }
    }

    private func run(_ active: Bool) {
        guard active else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                animateIn = false
                pulsed = false
            }
            return
        }
        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.3)
                : .spring(response: 0.5, dampingFraction: 0.82)
        ) {
            animateIn = true
        }
        if !reduceMotion {
            withAnimation(.easeOut(duration: 1.1).delay(0.35)) {
                pulsed = true
            }
        } else {
            pulsed = true
        }
    }
}

// MARK: - Icon badge
//
// Generic per-step icon: one large hierarchical SF Symbol — no
// backdrop disc (the bubble treatment read as template/stock).
private struct IconBadge: View {
    let symbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateIn = false

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appPrimary)
                .frame(width: 100, height: 100)
        }
        .scaleEffect(animateIn || reduceMotion ? 1.0 : 0.86)
        .opacity(animateIn ? 1.0 : 0.0)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.3)
                    : .spring(response: 0.5, dampingFraction: 0.82)
            ) {
                animateIn = true
            }
        }
        .frame(height: 130)
    }
}

// MARK: - Feature row (privacy checklist card)

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md - 2)
    }
}

// MARK: - Capability preview stack
//
// The consolidated "what the app does" visual: the Today verdict
// card (numeral count-up + ring draw-in) with a compact insights
// strip beneath it and a quick-log chip row that pays off the
// "log in seconds" pillar (Siri / Widgets / Search). One glance =
// verdict + where the money goes + how fast logging is.
private struct CapabilityPreviewStack: View {
    let viewModel: ExpenseViewModel
    let isActive: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            TodayPreviewCard(viewModel: viewModel, isActive: isActive)
            MiniInsightsStrip(isActive: isActive)
            QuickLogChips(isActive: isActive)
        }
        .frame(maxWidth: 340)
    }
}

// MARK: - Today preview card
//
// Faithful reproduction of the real Today verdict card. Uses the
// user's selected currency for all amounts so the preview feels
// personal ("the app already knows my currency"). Uses semantic
// colours (status green, etc.) within the card because that's
// what the live card shows; dropping them would lie about the
// product. The card chrome itself is the same elevated white
// `cardSurface()` the user sees on Today.
//
// v7: the hero numeral rolls up from zero via `numericText` — the
// preview *behaves* like the product (Copilot-style data-as-motion)
// instead of showing a static screenshot-of-a-number.
private struct TodayPreviewCard: View {
    let viewModel: ExpenseViewModel
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateRing = false
    @State private var animateContent = false
    @State private var displayedSpent: Double = 0

    private let tint: Color = .green
    private let ringTarget: CGFloat = 0.62
    private let spentAmount: Double = 1247.80
    private let budgetTotal: Double = 2000

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                statusPill
                Spacer()
                daysLeftChip
            }

            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("SPENT THIS MONTH")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundColor(.secondary)
                    Text(viewModel.formattedAmount(displayedSpent))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .contentTransition(.numericText(value: displayedSpent))
                        .opacity(animateContent ? 1 : 0)
                    Text("of \(viewModel.formattedAmount(budgetTotal)) budget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                ring
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text("Pacing 18% under last month")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(tint)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.12)))
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent || reduceMotion ? 0 : 8)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.Radius.hero)
        .onAppear { runAnimations(active: isActive) }
        .onChange(of: isActive) { _, new in runAnimations(active: new) }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text("ON TRACK")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundColor(tint)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    private var daysLeftChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .bold))
            Text("8 days left")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 6)
                .frame(width: 68, height: 68)
            Circle()
                .trim(from: 0, to: animateRing ? ringTarget : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 1.0), value: animateRing)
            Text(animateRing ? "62%" : "0%")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: animateRing)
        }
    }

    private func runAnimations(active: Bool) {
        if active {
            animateContent = false
            animateRing = false
            displayedSpent = 0
            if reduceMotion {
                // No choreography: content appears, numbers are final.
                withAnimation(.easeOut(duration: 0.25)) { animateContent = true }
                animateRing = true
                displayedSpent = spentAmount
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.08)) {
                    animateContent = true
                }
                withAnimation(.easeOut(duration: 1.0).delay(0.18)) {
                    animateRing = true
                }
                withAnimation(.easeOut(duration: 0.9).delay(0.2)) {
                    displayedSpent = spentAmount
                }
            }
        } else {
            animateContent = false
            animateRing = false
            displayedSpent = 0
        }
    }
}

// MARK: - Mini insights strip
//
// Compact "where it goes" preview: three category dots with animated
// share bars. Enough to say "the app shows you where it goes" without
// a second full-height card competing with the Today verdict above it.
private struct MiniInsightsStrip: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private struct Slice {
        let label: String
        let value: Double
        let tint: Color
    }

    private let slices: [Slice] = [
        Slice(label: "Food", value: 0.32, tint: .green),
        Slice(label: "Travel", value: 0.21, tint: .blue),
        Slice(label: "Bills", value: 0.18, tint: .orange)
    ]

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(Array(slices.enumerated()), id: \.offset) { idx, slice in
                sliceCell(slice, delay: 0.25 + Double(idx) * 0.08)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .onAppear { animate = isActive }
        .onChange(of: isActive) { _, new in
            animate = false
            if new {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { animate = true }
            }
        }
    }

    private func sliceCell(_ slice: Slice, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 1) {
            HStack(spacing: 5) {
                Circle()
                    .fill(slice.tint)
                    .frame(width: 7, height: 7)
                Text(slice.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Int(slice.value * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(slice.tint.opacity(0.15))
                    Capsule()
                        .fill(slice.tint)
                        .frame(width: animate ? proxy.size.width * slice.value / 0.32 : 0)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.55).delay(delay),
                            value: animate
                        )
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick-log chips
//
// Pays off the "log in seconds" pillar with the concrete surfaces:
// Siri, home-screen widgets, instant search. Kept as bare capsule
// chips (no third card) so the verdict preview stays the page's
// single anchoring block.
private struct QuickLogChips: View {
    let isActive: Bool

    private struct Chip: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
    }

    private let chips: [Chip] = [
        Chip(icon: "waveform", label: "Siri"),
        Chip(icon: "square.grid.2x2.fill", label: "Widgets"),
        Chip(icon: "magnifyingglass", label: "Instant search")
    ]

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { idx, chip in
                HStack(spacing: 5) {
                    Image(systemName: chip.icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(chip.label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                .cascadeIn(idx, active: isActive, baseDelay: 0.55)
            }
        }
    }
}

// MARK: - First-expense landing card (Finish)
//
// The "input met with output" beat: the user's REAL first expense
// rendered inside a miniature Today card, with the month total
// counting up from zero to their amount and the expense row sliding
// in beneath. This is the moment cause-and-effect lands — "I typed a
// number on the last page, and there's my Today screen reacting."
private struct FirstExpenseLanding: View {
    let viewModel: ExpenseViewModel
    let amount: Double
    let title: String
    let category: Expense.Category
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardShown = false
    @State private var rowShown = false
    @State private var displayedAmount: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("YOUR TODAY SCREEN")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("SPENT THIS MONTH")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundColor(.secondary)
                Text(viewModel.formattedAmount(displayedAmount))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: displayedAmount))
            }

            Divider().opacity(0.5)

            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.forCategory(category.color).opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: category.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.forCategory(category.color))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("Just now")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Text(viewModel.formattedAmount(amount))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .opacity(rowShown ? 1 : 0)
            .offset(y: rowShown || reduceMotion ? 0 : 10)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 340, alignment: .leading)
        .cardSurface(radius: Theme.Radius.hero)
        .scaleEffect(cardShown || reduceMotion ? 1.0 : 0.94)
        .opacity(cardShown ? 1 : 0)
        .onAppear { run(isActive) }
        .onChange(of: isActive) { _, nowActive in run(nowActive) }
    }

    private func run(_ active: Bool) {
        guard active else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cardShown = false
                rowShown = false
                displayedAmount = 0
            }
            return
        }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) {
                cardShown = true
                rowShown = true
            }
            displayedAmount = amount
        } else {
            withAnimation(Theme.Motion.emphasized.delay(0.1)) { cardShown = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.35)) { displayedAmount = amount }
            withAnimation(Theme.Motion.emphasized.delay(0.55)) { rowShown = true }
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(showOnboarding: .constant(true))
            .environmentObject(ExpenseViewModel())
    }
}
