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
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.appPrimary.opacity(0.15), Color.appSecondary.opacity(0.10)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 70, height: 70)
                                .shadow(color: Color.appPrimary.opacity(0.18), radius: 10, x: 0, y: 5)
                            Image(systemName: "heart.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Support CashLens")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Your support helps us continue improving CashLens and adding new features. Thank you for your generosity!")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 16)
                    
                    // Donation Options
                    VStack(spacing: 18) {
                        ForEach(donationManager.products) { product in
                            DonationCard(product: product, isProcessing: isProcessing) {
                                await purchase(product)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    
                    Spacer(minLength: 24)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
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
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(product.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundColor(.appPrimary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondarySystemBackground)
                    .shadow(color: Color.appPrimary.opacity(isPressed ? 0.10 : 0.18), radius: isPressed ? 2 : 8, x: 0, y: isPressed ? 1 : 4)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationView {
        DonationView()
    }
} 
