import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var proManager = ProManager.shared
    @State private var selectedPlan: SelectedPlan = .yearly
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var animateFeatures = false

    enum SelectedPlan {
        case monthly, yearly, lifetime
    }

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xxxl - 4) {
                    headerSection
                    featuresSection
                    pricingSection
                    purchaseButton
                    restoreAndTerms
                }
                .padding(.horizontal, Theme.Spacing.xl)
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
        .onAppear {
            withAnimation(Theme.Motion.emphasized.delay(0.15)) {
                animateFeatures = true
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient.appPrimarySoft
            .background(Color(.systemBackground))
            .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(Theme.Spacing.sm + 2)
                        .background(Color.secondarySystemBackground)
                        .clipShape(Circle())
                }
            }

            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 15, x: 0, y: 8)

                Image(systemName: "crown.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("CashLens Pro")
                .font(Theme.Typography.pageTitle)

            Text("Unlock the full power of your finances")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: Theme.Spacing.md + 2) {
            featureRow(icon: "chart.pie.fill", title: "Budgets & Alerts", subtitle: "Set spending limits with smart notifications", delay: 0)
            featureRow(icon: "tag.fill", title: "Smart Tags", subtitle: "Label expenses for trips, reimbursements & more", delay: 0.05)
            featureRow(icon: "doc.richtext.fill", title: "PDF Reports", subtitle: "Generate & share professional spending reports", delay: 0.1)
            featureRow(icon: "doc.text.viewfinder", title: "Receipt Scanner", subtitle: "Scan or attach receipts — back up & restore with your CashLens archive", delay: 0.15)
            featureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Analytics", subtitle: "Year-over-year comparisons & forecasting", delay: 0.2)
            featureRow(icon: "paintpalette.fill", title: "Custom Themes & Icons", subtitle: "Personalize your app experience", delay: 0.25)
        }
        .padding(Theme.Spacing.xl)
        .cardSurface(radius: Theme.Radius.container, fill: Color.secondarySystemBackground.opacity(0.7))
    }

    private func featureRow(icon: String, title: String, subtitle: String, delay: Double) -> some View {
        HStack(spacing: Theme.Spacing.md + 2) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.appPrimary)
                .frame(width: 36, height: 36)
                .background(Color.appPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.sm + 2, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appPrimary)
        }
        .opacity(animateFeatures ? 1 : 0)
        .offset(y: animateFeatures ? 0 : 12)
        .animation(.easeOut(duration: 0.4).delay(delay), value: animateFeatures)
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Monthly
            if let monthly = proManager.monthlyProduct {
                planCard(
                    plan: .monthly,
                    title: "Monthly",
                    price: monthly.displayPrice,
                    period: "/ month",
                    badge: nil,
                    product: monthly
                )
            }

            // Yearly
            if let yearly = proManager.yearlyProduct {
                let savingsBadge = proManager.yearlySavingsPercent > 0
                    ? "Save \(proManager.yearlySavingsPercent)%"
                    : nil
                planCard(
                    plan: .yearly,
                    title: "Yearly",
                    price: yearly.displayPrice,
                    period: "/ year",
                    badge: savingsBadge,
                    product: yearly
                )
            }

            // Lifetime
            if let lifetime = proManager.lifetimeProduct {
                planCard(
                    plan: .lifetime,
                    title: "Lifetime",
                    price: lifetime.displayPrice,
                    period: "one-time",
                    badge: "Best Value",
                    product: lifetime
                )
            }

            if !proManager.proProducts.isEmpty {
                trialNotice
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

    private func planCard(plan: SelectedPlan, title: String, price: String, period: String, badge: String?, product: Product) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                selectedPlan = plan
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(title)
                            .font(Theme.Typography.subsectionTitle)
                            .foregroundColor(.primary)

                        if let badge = badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 3)
                                .background(Color.appPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.xs + 2, style: .continuous))
                        }
                    }

                    if plan != .lifetime,
                       product.subscription?.introductoryOffer != nil {
                        Text("7-day free trial")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.appPrimary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    Text(price)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text(period)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(
                        isSelected ? Color.appPrimary : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trialNotice: some View {
        if selectedPlan != .lifetime {
            HStack(spacing: Theme.Spacing.xs + 2) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.appPrimary)
                Text("Start with a 7-day free trial. Cancel anytime.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        PrimaryGradientButton(
            title: selectedPlan == .lifetime ? "Unlock Pro Forever" : "Start Free Trial",
            isEnabled: !proManager.proProducts.isEmpty && !isProcessing
        ) {
            HapticManager.shared.mediumTap()
            Task { await performPurchase() }
        }
    }

    // MARK: - Restore & Terms

    private var restoreAndTerms: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button {
                HapticManager.shared.lightTap()
                Task { await proManager.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundColor(.appPrimary)
            }

            Text("Payment is charged to your Apple ID account at confirmation of purchase. Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your App Store account settings.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
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

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await proManager.purchase(product)
            HapticManager.shared.success()
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
