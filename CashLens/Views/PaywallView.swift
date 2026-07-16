import SwiftUI
import StoreKit

/// Where the paywall was opened from. Drives the feature-list order so
/// the thing the user just tapped leads the sell instead of a generic
/// pitch. `.general` keeps the canonical order with no highlight.
enum PaywallContext {
    case general
    case budgets
    case receipts
    case tags
    case themes
    case icons
    case insights
    case forecast
    case reports
    case importFormats

    /// ID of the feature row that should lead (and be highlighted).
    /// `nil` = keep the default order.
    var leadFeatureID: String? {
        switch self {
        case .general:            return nil
        case .budgets:            return "budgets"
        case .receipts:           return "receipts"
        case .tags:               return "tags"
        case .themes, .icons:     return "themes"
        case .insights, .forecast: return "insights"
        case .reports:            return "reports"
        case .importFormats:      return "import"
        }
    }
}

/// The Pro paywall.
///
/// Layout follows the archetype that tests best for trust-sensitive
/// finance apps: benefit-led hero → context spotlight (the feature the
/// user was just gated on, sold as an outcome) → outcome-framed benefit
/// list → privacy/trust block → annual-anchored plan cards → honest
/// trial timeline (Blinkist pattern, only when this Apple ID is
/// actually eligible) → CTA with the exact charge spelled out.
///
/// Compliance guardrails baked in: the full price is always visible
/// before purchase, no fake urgency, the close button is always
/// reachable, and trial copy never appears for ineligible users.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var proManager = ProManager.shared
    @State private var selectedPlan: SelectedPlan = .yearly
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var animateIn = false
    @State private var isRestoring = false
    @State private var restoreResultMessage: String?

    /// Entry-point context — surfaces the gated feature the user just
    /// hit as a spotlight card above the generic benefit list.
    var context: PaywallContext = .general

    enum SelectedPlan {
        case monthly, yearly, lifetime
    }

    // MARK: - Feature catalog

    private struct Feature: Identifiable {
        let id: String
        let icon: String
        /// Outcome the user gets, not the feature's name.
        let title: String
        let subtitle: String
    }

    /// Benefit list, framed as outcomes ("what changes for you"), with
    /// the concrete capability in the subtitle for scanners who want
    /// specifics.
    private static let baseFeatures: [Feature] = [
        Feature(id: "budgets", icon: "chart.pie.fill", title: "Catch overspending early", subtitle: "Per-category budgets, weekly periods & alerts before you blow through them"),
        Feature(id: "insights", icon: "chart.line.uptrend.xyaxis", title: "Know if you're on track before you spend", subtitle: "30/60/90-day forecasts & year-over-year trends"),
        Feature(id: "receipts", icon: "doc.text.viewfinder", title: "Log receipts without typing", subtitle: "Scan a receipt — amount & merchant fill themselves, all on-device"),
        Feature(id: "tags", icon: "tag.fill", title: "Find any expense in seconds", subtitle: "Tag trips, reimbursements & shared costs, then filter by tag"),
        Feature(id: "reports", icon: "doc.richtext.fill", title: "Share polished reports", subtitle: "Professional PDF spending reports in one tap"),
        Feature(id: "themes", icon: "paintpalette.fill", title: "Make it feel like yours", subtitle: "Custom accent themes & alternate app icons")
    ]

    /// Only surfaced when the user arrives from the import flow — it
    /// isn't part of the default six-row pitch.
    private static let importFeature = Feature(
        id: "import", icon: "square.and.arrow.down.fill",
        title: "Bring your history with you",
        subtitle: "Auto-mapped CSVs from Mint, YNAB & bank statements"
    )

    /// Feature rows shown in the list. When a context spotlight exists,
    /// its feature is pulled out of the list (it already leads the page)
    /// so nothing is pitched twice.
    private var listFeatures: [Feature] {
        guard let leadID = context.leadFeatureID else { return Self.baseFeatures }
        return Self.baseFeatures.filter { $0.id != leadID }
    }

    // MARK: - Context spotlight

    private struct Spotlight {
        let icon: String
        let title: String
        let message: String
        /// Decorative mini forecast bars — only for the insights /
        /// forecast contexts where "seeing the trend" is the sell.
        let showsChart: Bool
    }

    /// Richer, outcome-led pitch for the feature the user was just
    /// gated on. Keyed off `leadFeatureID` so `.themes`/`.icons` and
    /// `.insights`/`.forecast` share copy exactly like they share a row.
    private var spotlight: Spotlight? {
        guard let id = context.leadFeatureID else { return nil }
        switch id {
        case "budgets":
            return Spotlight(
                icon: "chart.pie.fill",
                title: "Catch overspending early",
                message: "Set a budget for any category — monthly or weekly — and get an alert before you blow through it, not after.",
                showsChart: false
            )
        case "receipts":
            return Spotlight(
                icon: "doc.text.viewfinder",
                title: "Log receipts without typing",
                message: "Point your camera at a receipt and the amount and merchant fill themselves in. Processed entirely on your device.",
                showsChart: false
            )
        case "tags":
            return Spotlight(
                icon: "tag.fill",
                title: "Find any expense in seconds",
                message: "Tag trips, reimbursements and shared costs, then filter your whole history by tag.",
                showsChart: false
            )
        case "themes":
            return Spotlight(
                icon: "paintpalette.fill",
                title: "Make it feel like yours",
                message: "Unlock every accent theme and alternate app icon, and switch whenever the mood strikes.",
                showsChart: false
            )
        case "insights":
            return Spotlight(
                icon: "chart.line.uptrend.xyaxis",
                title: "Know if you're on track before you spend",
                message: "Forecasts and year-over-year comparisons show where the month is heading — while there's still time to change course.",
                showsChart: true
            )
        case "reports":
            return Spotlight(
                icon: "doc.richtext.fill",
                title: "Share polished reports",
                message: "Turn any period into a professional PDF spending report and share it in one tap.",
                showsChart: false
            )
        case "import":
            return Spotlight(
                icon: "square.and.arrow.down.fill",
                title: "Bring your history with you",
                message: "Import CSVs from Mint, YNAB and bank statements — columns map themselves automatically.",
                showsChart: false
            )
        default:
            return nil
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Calm tinted background — a single low-opacity tint over
            // the system background, matching the rest of the v2
            // surfaces.
            ZStack {
                Color(uiColor: .systemBackground)
                Color.appPrimary.opacity(0.08)
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xxl) {
                    headerSection
                        .modifier(SectionEntrance(order: 0, animate: entranceState))
                    if let spotlight {
                        spotlightCard(spotlight)
                            .modifier(SectionEntrance(order: 1, animate: entranceState))
                    }
                    featuresSection
                        .modifier(SectionEntrance(order: 2, animate: entranceState))
                    pricingSection
                        .modifier(SectionEntrance(order: 3, animate: entranceState))
                    ctaSection
                        .modifier(SectionEntrance(order: 4, animate: entranceState))
                    restoreAndTerms
                        .modifier(SectionEntrance(order: 5, animate: entranceState))
                }
                .padding(.horizontal, Theme.Spacing.xl)
                // Breathing room below the sheet's grab-handle zone.
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 40)
            }

            if isProcessing {
                processingOverlay
            }
        }
        .alert("Purchase Successful!", isPresented: $showSuccess) {
            Button("Let's Go!") { dismiss() }
        } message: {
            Text("Welcome to CashLens Pro. All features are now unlocked.")
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert("Restore Purchases", isPresented: Binding(
            get: { restoreResultMessage != nil },
            set: { if !$0 { restoreResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { restoreResultMessage = nil }
        } message: {
            Text(restoreResultMessage ?? "")
        }
        .onAppear {
            withAnimation(Theme.Motion.emphasized.delay(0.1)) {
                animateIn = true
            }
            recordImpression()
            // Resolve trial eligibility right at the decision moment.
            // Copy defaults to non-trial until this lands, so a slow
            // network can only ever under-promise.
            Task { await proManager.refreshIntroOfferEligibility() }
        }
    }

    /// Reduce Motion: sections render settled from the first frame —
    /// `SectionEntrance` never sees a value change, so nothing slides.
    private var entranceState: Bool {
        reduceMotion ? true : animateIn
    }

    /// Every presentation counts as one impression, regardless of the
    /// entry point — onAppear is the single choke point all
    /// presentations flow through.
    private func recordImpression() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: UserDefaultsKeys.hasSeenPaywall)
        let count = defaults.integer(forKey: UserDefaultsKeys.paywallImpressionCount)
        defaults.set(count + 1, forKey: UserDefaultsKeys.paywallImpressionCount)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Spacer()
                // Shared close-button chrome (SheetCloseButton) so
                // every sheet's X reads identically — and it's always
                // reachable, never hidden or delayed.
                SheetCloseButton(action: { dismiss() })
            }
            .padding(.bottom, Theme.Spacing.md)

            // Calm crown mark — hierarchical glyph, no disc, no glow.
            HeroGlyph(systemName: "crown.fill")

            Text("CashLens Pro")
                .font(Theme.Typography.pageTitle)
                .foregroundColor(.primary)

            // Benefit-led subtitle: the job the user is hiring Pro for,
            // not a feature inventory.
            Text("See where your money goes — and where it's headed.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.md)
        }
    }

    // MARK: - Context spotlight card

    /// Hero card for the feature the user was just gated on — the
    /// paywall answers "what do I get?" with "the thing you just
    /// tapped", sold as an outcome, before the generic list.
    private func spotlightCard(_ spotlight: Spotlight) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: spotlight.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Included in Pro".uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(.appPrimary)
                    Text(spotlight.title)
                        .font(Theme.Typography.subsectionTitle)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(spotlight.message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if spotlight.showsChart {
                forecastMiniBars
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .cardSurface(
            radius: Theme.Radius.hero,
            fill: Color.appPrimary.opacity(0.07),
            stroke: Color.appPrimary.opacity(0.25),
            strokeWidth: Theme.Stroke.thin
        )
    }

    /// Decorative "month so far → forecast" bars for the insights /
    /// forecast spotlight. Solid bars are the past; the lighter pair is
    /// the projection. Purely illustrative — no data, no motion.
    private var forecastMiniBars: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            ForEach(Array([22, 34, 27, 42, 36, 48, 54].enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(Color.appPrimary.opacity(index >= 5 ? 0.28 : 0.75))
                    .frame(width: 16, height: CGFloat(height))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Features

    private var featuresSection: some View {
        // Grouped list (one elevated card, hairline-separated rows)
        // mirrors the SettingsGroup pattern on the You tab.
        let features = listFeatures

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(spotlight == nil ? "What Pro unlocks" : "Plus everything else in Pro")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
                .padding(.leading, Theme.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    featureRow(icon: feature.icon, title: feature.title, subtitle: feature.subtitle)
                    if index < features.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.md + 2) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appPrimary.opacity(0.7))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Privacy as a conversion asset — for a local-only finance
            // app this is the strongest trust element we have, so it
            // gets real visual weight right before the ask.
            trustBlock
                .padding(.bottom, Theme.Spacing.xs)

            // Annual-first anchoring: yearly leads (and is preselected),
            // monthly is the low-commitment fallback, lifetime closes as
            // the premium anchor.
            if let yearly = proManager.yearlyProduct {
                let savingsBadge = proManager.yearlySavingsPercent > 0
                    ? "Save \(proManager.yearlySavingsPercent)%"
                    : nil
                planCard(
                    plan: .yearly,
                    title: "Yearly",
                    price: yearly.displayPrice,
                    period: "/ year",
                    equivalent: yearlyMonthlyEquivalent.map { "≈ \($0) / month" },
                    badge: savingsBadge,
                    note: trialNoteIfEligible(for: yearly)
                )
            }

            if let monthly = proManager.monthlyProduct {
                planCard(
                    plan: .monthly,
                    title: "Monthly",
                    price: monthly.displayPrice,
                    period: "/ month",
                    equivalent: nil,
                    badge: nil,
                    note: trialNoteIfEligible(for: monthly)
                )
            }

            if let lifetime = proManager.lifetimeProduct {
                planCard(
                    plan: .lifetime,
                    title: "Lifetime",
                    price: lifetime.displayPrice,
                    period: "one-time",
                    equivalent: nil,
                    badge: nil,
                    note: "Pay once, yours forever"
                )
            }

            if showsTrialTimeline {
                trialTimeline
                    .padding(.top, Theme.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if proManager.proProducts.isEmpty && !proManager.isLoading {
                Text("Unable to load pricing. Please check your connection and try again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private var trustBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text("Private by design")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
            }
            Text("No account. No ads. Your data never leaves your device.")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// "N-day free trial included" — only when this Apple ID can
    /// actually redeem the intro offer (once-per-Apple-ID).
    private func trialNoteIfEligible(for product: Product) -> String? {
        guard product.subscription?.introductoryOffer != nil,
              proManager.isEligibleForIntroOffer else { return nil }
        return "\(trialDays(for: product))-day free trial included"
    }

    private func planCard(plan: SelectedPlan, title: String, price: String, period: String, equivalent: String?, badge: String?, note: String?) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                selectedPlan = plan
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Radio indicator — the iOS-native paywall pattern.
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.appPrimary : Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 12, height: 12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(title)
                            .font(Theme.Typography.rowTitle)
                            .foregroundColor(.primary)

                        if let badge = badge {
                            Text(badge.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 3)
                                .background(Color.appPrimary)
                                .clipShape(Capsule())
                        }
                    }

                    if let note {
                        Text(note)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(price)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text(period)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                    // Weekly-price-style reframing: the annual card also
                    // shows its per-month equivalent so no mental math
                    // is needed to see the deal.
                    if let equivalent {
                        Text(equivalent)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.appPrimary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? Color.appPrimary.opacity(0.08) : Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(
                        isSelected ? Color.appPrimary.opacity(0.5) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0 : 0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Trial timeline

    /// Blinkist-style "how your free trial works" timeline — the
    /// most-copied trust pattern in subscription apps because it removes
    /// the #1 trial fear ("I'll forget and get charged"). Shown only
    /// when the intro offer is genuinely redeemable and a subscription
    /// plan is selected. The day-N reminder is a real local notification
    /// scheduled at purchase (see `performPurchase`), not an empty
    /// promise.
    private var showsTrialTimeline: Bool {
        selectedPlan != .lifetime
            && proManager.isEligibleForIntroOffer
            && selectedSubscriptionProduct?.subscription?.introductoryOffer != nil
    }

    private var trialTimeline: some View {
        let days = trialDays(for: selectedSubscriptionProduct)
        let reminderDay = max(days - 2, 1)
        let chargeText = selectedPlanChargeText

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("How your free trial works")
                .font(Theme.Typography.subsectionTitle)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 0) {
                timelineStep(
                    icon: "lock.open.fill",
                    title: "Today",
                    detail: "Everything unlocks — budgets, forecasts, receipt scanning and more.",
                    isLast: false
                )
                if days > 2 {
                    timelineStep(
                        icon: "bell.badge.fill",
                        title: "Day \(reminderDay)",
                        detail: "We send you a reminder that your trial is ending soon.",
                        isLast: false
                    )
                }
                timelineStep(
                    icon: "creditcard.fill",
                    title: "Day \(days)",
                    detail: "First charge: \(chargeText). Cancel any time before this in Settings and pay nothing.",
                    isLast: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }

    private func timelineStep(icon: String, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.appPrimary.opacity(0.22))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.lg)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Price helpers

    /// The subscription product the current selection maps to (nil for
    /// lifetime).
    private var selectedSubscriptionProduct: Product? {
        switch selectedPlan {
        case .monthly:  return proManager.monthlyProduct
        case .yearly:   return proManager.yearlyProduct
        case .lifetime: return nil
        }
    }

    /// Trial length in days, derived from the live intro offer so the
    /// copy can never drift from what App Store Connect is configured
    /// to grant. Falls back to 7 (the configured offer) if the product
    /// hasn't loaded.
    private func trialDays(for product: Product?) -> Int {
        guard let period = product?.subscription?.introductoryOffer?.period else { return 7 }
        switch period.unit {
        case .day:   return period.value
        case .week:  return period.value * 7
        case .month: return period.value * 30
        case .year:  return period.value * 365
        @unknown default: return 7
        }
    }

    /// Locale-correct per-month reframing of the annual price, computed
    /// from the live `Product` price with the product's own currency
    /// format style.
    private var yearlyMonthlyEquivalent: String? {
        guard let yearly = proManager.yearlyProduct else { return nil }
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    /// "₹X / period" for the selected subscription — used by the
    /// timeline's charge step and the trial reminder notification.
    private var selectedPlanChargeText: String {
        switch selectedPlan {
        case .monthly:
            guard let p = proManager.monthlyProduct else { return "" }
            return "\(p.displayPrice) / month"
        case .yearly:
            guard let p = proManager.yearlyProduct else { return "" }
            return "\(p.displayPrice) / year"
        case .lifetime:
            return ""
        }
    }

    // MARK: - CTA

    /// CTA whose primary line says what *happens*, and whose subline
    /// shows the exact price — no ambiguity about the post-trial charge,
    /// ever. Under it, the single highest-tested reassurance line:
    /// cancel anytime.
    private var ctaSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button {
                HapticManager.shared.mediumTap()
                Task { await performPurchase() }
            } label: {
                VStack(spacing: 2) {
                    Text(ctaPrimaryLine)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    if let sub = ctaSubLine {
                        Text(sub)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md + 4)
                .background(Color.appPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .primaryGlow(strength: ctaEnabled ? 0.3 : 0)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!ctaEnabled)
            .opacity(ctaEnabled ? 1 : 0.5)
            .animation(Theme.Motion.snappy, value: selectedPlan)

            Text(selectedPlan == .lifetime
                 ? "One payment. No subscription, no renewals."
                 : "No commitment — cancel anytime in Settings.")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var ctaEnabled: Bool {
        !proManager.proProducts.isEmpty && !isProcessing
    }

    private var ctaPrimaryLine: String {
        switch selectedPlan {
        case .lifetime:
            return "Unlock Pro Forever"
        case .monthly, .yearly:
            return selectedProductHasTrial
                ? "Start \(trialDays(for: selectedSubscriptionProduct))-day free trial"
                : "Subscribe"
        }
    }

    private var ctaSubLine: String? {
        switch selectedPlan {
        case .lifetime:
            guard let p = proManager.lifetimeProduct else { return nil }
            return "\(p.displayPrice) · one-time"
        case .monthly:
            guard let p = proManager.monthlyProduct else { return nil }
            return selectedProductHasTrial
                ? "then \(p.displayPrice) / month"
                : "\(p.displayPrice) / month"
        case .yearly:
            guard let p = proManager.yearlyProduct else { return nil }
            return selectedProductHasTrial
                ? "then \(p.displayPrice) / year"
                : "\(p.displayPrice) / year"
        }
    }

    private var selectedProductHasTrial: Bool {
        // The product carrying an intro offer isn't enough — the user
        // must also still be eligible to redeem it, or the purchase
        // sheet will contradict the CTA.
        return selectedSubscriptionProduct?.subscription?.introductoryOffer != nil
            && proManager.isEligibleForIntroOffer
    }

    // MARK: - Restore & Terms

    /// Privacy points at our custom on-device policy. Terms use Apple's
    /// standard Licensed Application EULA so auto-renew subscription
    /// language (Guideline 3.1.2) is covered without depending on our
    /// custom terms page staying in sync.
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyPolicyURL = URL(string: "https://cashlens.app/privacy")!

    private var restoreAndTerms: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button {
                guard !isRestoring else { return }
                HapticManager.shared.lightTap()
                isRestoring = true
                Task {
                    await proManager.restorePurchases()
                    isRestoring = false
                    // Always answer the tap — a silent restore reads as
                    // broken (and 3.1.1 reviewers test this button).
                    if proManager.isPro {
                        HapticManager.shared.success()
                        showSuccess = true
                    } else if let storeError = proManager.purchaseError {
                        restoreResultMessage = storeError
                    } else {
                        restoreResultMessage = "No previous purchases were found for this Apple ID."
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                }
            }
            .disabled(isRestoring)

            Text("Payment is charged to your Apple ID account at confirmation of purchase. Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your App Store account settings.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            // Guideline 3.1.2: Terms of Use & Privacy Policy links must
            // appear on any screen offering auto-renewing subscriptions.
            HStack(spacing: Theme.Spacing.sm) {
                Link("Terms of Use", destination: Self.termsOfUseURL)
                Text("·")
                    .foregroundColor(.secondary.opacity(0.5))
                Link("Privacy Policy", destination: Self.privacyPolicyURL)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .tint(.secondary)
        }
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.3)
                Text("Processing...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(Theme.Spacing.xxxl - 2)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
        }
    }

    // MARK: - Purchase Logic

    private func performPurchase() async {
        let product: Product?
        switch selectedPlan {
        case .monthly:  product = proManager.monthlyProduct
        case .yearly:   product = proManager.yearlyProduct
        case .lifetime: product = proManager.lifetimeProduct
        }

        guard let product else { return }

        // Capture trial facts before the purchase — eligibility flips
        // once the intro offer is consumed.
        let startedTrial = selectedProductHasTrial
        let reminderDays = trialDays(for: product)
        let renewalText = selectedPlanChargeText

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await proManager.purchase(product)
            HapticManager.shared.success()
            if startedTrial {
                // Honor the timeline's "we send you a reminder" step
                // with a real local notification 2 days before the
                // trial converts.
                await NotificationScheduler.scheduleTrialEndingReminder(
                    trialDays: reminderDays,
                    renewalPriceText: renewalText
                )
            }
            showSuccess = true
        } catch ProPurchaseError.userCancelled {
            // No-op
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            HapticManager.shared.error()
        }
    }
}

#Preview {
    PaywallView()
}

#Preview("Forecast context") {
    PaywallView(context: .forecast)
}
