import SwiftUI
import StoreKit

struct DonationView: View {
    @StateObject private var donationManager = DonationManager.shared
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Namespace private var animation
    
    var body: some View {
        ZStack {
            // v2: calm tinted background, identical treatment to Paywall,
            // Export, Import, and Recap so the "support family" of
            // commercial-ish screens read as one product surface.
            ZStack {
                Color(uiColor: .systemBackground)
                Color.appPrimary.opacity(0.06)
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xl) {
                    VStack(spacing: Theme.Spacing.md) {
                        HeroGlyph(systemName: "heart.fill")
                        Text("Support CashLens")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Built by one person, paid for by people who like it. If CashLens is useful to you, a small tip keeps the lights on and the updates coming.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    VStack(spacing: Theme.Spacing.md) {
                        ForEach(donationManager.products) { product in
                            DonationCard(product: product, isProcessing: isProcessing) {
                                await purchase(product)
                            }
                        }
                    }

                    Text("These are one-time tips. No subscription, no obligation. Thank you.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            
            if isProcessing {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }
    
    private func purchase(_ product: Product) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await donationManager.purchase(product)
            HapticManager.shared.success()
        } catch StoreError.userCancelled {
            // User cancelled, no need to show error
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            HapticManager.shared.error()
        }
    }
}

struct DonationCard: View {
    let product: Product
    let isProcessing: Bool
    let action: () async -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button {
            guard !isProcessing else { return }
            HapticManager.shared.lightTap()
            isPressed = true
            Task {
                await action()
                isPressed = false
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconForProduct(product))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(.primary)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)
                    .monospacedDigit()
            }
            .padding(Theme.Spacing.md + 2)
            .cardSurface()
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Picks a friendly icon per StoreKit identifier — keeps the tiles
    /// visually distinct without depending on app-bundle artwork.
    private func iconForProduct(_ product: Product) -> String {
        let lower = product.id.lowercased()
        if lower.contains("small") || lower.contains("coffee") || lower.contains("tip1") { return "cup.and.saucer.fill" }
        if lower.contains("medium") || lower.contains("snack") || lower.contains("tip2") { return "fork.knife" }
        if lower.contains("large") || lower.contains("dinner") || lower.contains("tip3") { return "gift.fill" }
        return "heart.fill"
    }
}

#Preview {
    NavigationView {
        DonationView()
    }
} 
