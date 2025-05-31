import SwiftUI
import StoreKit

struct FeedbackRequestView: View {
    @State private var showingAnimation = false
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissModal()
                }
            
            // Main modal content
            VStack(spacing: 0) {
                // Header with animation
                VStack(spacing: 20) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.appPrimary.opacity(0.2), Color.appSecondary.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.appPrimary)
                            .scaleEffect(showingAnimation ? 1.0 : 0.8)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: showingAnimation)
                    }
                    
                    // Title and message
                    VStack(spacing: 12) {
                        Text("Loving CashLens?")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .opacity(showingAnimation ? 1 : 0)
                            .offset(y: showingAnimation ? 0 : 10)
                            .animation(.easeOut(duration: 0.6).delay(0.2), value: showingAnimation)
                        
                        Text("We'd appreciate your feedback! It helps us improve and reach more people.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .opacity(showingAnimation ? 1 : 0)
                            .offset(y: showingAnimation ? 0 : 10)
                            .animation(.easeOut(duration: 0.6).delay(0.3), value: showingAnimation)
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                
                // Action buttons
                VStack(spacing: 12) {
                    // Rate on App Store button
                    Button(action: rateApp) {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 18, weight: .semibold))
                            
                            Text("Rate on App Store")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.appPrimary, Color.appSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .opacity(showingAnimation ? 1 : 0)
                    .offset(y: showingAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.6).delay(0.4), value: showingAnimation)
                    
                    // Share with friends button
                    Button(action: shareApp) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Share with Friends")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.appPrimary.opacity(0.1))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .opacity(showingAnimation ? 1 : 0)
                    .offset(y: showingAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.6).delay(0.5), value: showingAnimation)
                    
                    // Not now button
                    Button(action: {
                        HapticManager.shared.impact(style: .light)
                        dismissModal()
                    }) {
                        Text("Not Now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .opacity(showingAnimation ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: showingAnimation)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
            .scaleEffect(showingAnimation ? 1.0 : 0.95)
            .opacity(showingAnimation ? 1.0 : 0.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showingAnimation)
        }
        .onAppear {
            withAnimation {
                showingAnimation = true
            }
        }
    }
    
    private func dismissModal() {
        FeedbackManager.shared.shouldShowFeedbackRequest = false
    }
    
    private func rateApp() {
        HapticManager.shared.impact(style: .medium)
        
        // Mark as feedback requested
        FeedbackManager.shared.markFeedbackRequested()
        
        // Open App Store directly for rating
        let appStoreURL = "https://apps.apple.com/us/app/cashlens/id6743153951?action=write-review" 
        
        if let url = URL(string: appStoreURL) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    print("Failed to open App Store URL")
                    // Fallback: try to open general App Store page
                    if let fallbackURL = URL(string: "https://apps.apple.com/us/app/cashlens/id6743153951") {
                        UIApplication.shared.open(fallbackURL)
                    }
                }
            }
        }
        
        dismissModal()
    }
    
    private func shareApp() {
        HapticManager.shared.impact(style: .medium)
        
        // Mark as feedback requested
        FeedbackManager.shared.markFeedbackRequested()
        
        let appURL = "https://apps.apple.com/us/app/cashlens/id6743153951"
        let shareText = "Check out CashLens - the best expense tracking app! 💰📱"
        
        let activityController = UIActivityViewController(
            activityItems: [shareText, URL(string: appURL)!],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            activityController.popoverPresentationController?.sourceView = rootViewController.view
            rootViewController.present(activityController, animated: true)
        }
        
        dismissModal()
    }
}

// MARK: - Feedback Manager
class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()
    
    private let hasRequestedFeedbackKey = "hasRequestedFeedback"
    private let successfulActionsCountKey = "successfulActionsCount"
    private let feedbackTriggerThreshold = 3 // Show after 3 successful actions
    
    @Published var shouldShowFeedbackRequest = false
    
    private init() {}
    
    var hasRequestedFeedback: Bool {
        UserDefaults.standard.bool(forKey: hasRequestedFeedbackKey)
    }
    
    func markFeedbackRequested() {
        UserDefaults.standard.set(true, forKey: hasRequestedFeedbackKey)
        shouldShowFeedbackRequest = false
        print("✅ Feedback request marked as completed")
    }
    
    func incrementSuccessfulAction() {
        // Don't track if already requested feedback
        guard !hasRequestedFeedback else { return }
        
        let currentCount = UserDefaults.standard.integer(forKey: successfulActionsCountKey)
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: successfulActionsCountKey)
        
        print("📊 Successful actions count: \(newCount)/\(feedbackTriggerThreshold)")
        
        // Check if we should show feedback request
        if newCount >= feedbackTriggerThreshold {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.shouldShowFeedbackRequest = true
                print("🎉 Triggering feedback request after \(newCount) successful actions")
            }
        }
    }
    
    // For testing purposes
    func resetFeedbackState() {
        UserDefaults.standard.removeObject(forKey: hasRequestedFeedbackKey)
        UserDefaults.standard.removeObject(forKey: successfulActionsCountKey)
        shouldShowFeedbackRequest = false
        print("🔄 Feedback state reset for testing")
    }
}

struct FeedbackRequestView_Previews: PreviewProvider {
    static var previews: some View {
        FeedbackRequestView()
    }
} 