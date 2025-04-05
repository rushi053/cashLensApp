import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0
    @State private var showingCurrencyPicker = false
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to CashLens",
            description: "Your personal expense tracker designed to help you manage and visualize your spending habits.",
            imageName: "creditcard.fill",
            backgroundColor: .appPrimary
        ),
        OnboardingPage(
            title: "Track Expenses",
            description: "Easily add and categorize your expenses to keep track of where your money goes.",
            imageName: "plus.circle.fill",
            backgroundColor: .teaRose
        ),
        OnboardingPage(
            title: "View Statistics",
            description: "Get insights into your spending patterns with beautiful visualizations and breakdowns.",
            imageName: "chart.pie.fill",
            backgroundColor: .jordyBlue
        ),
        OnboardingPage(
            title: "Personalize",
            description: "Create custom categories that match your unique spending habits and lifestyle.",
            imageName: "slider.horizontal.3",
            backgroundColor: .champagnePink
        )
    ]
    
    var body: some View {
        ZStack {
            // Background color that changes with the page
            pages[currentPage].backgroundColor
                .edgesIgnoringSafeArea(.all)
                .animation(.easeInOut(duration: 0.3), value: currentPage)
            
            VStack {
                // Skip button
                HStack {
                    Spacer()
                    
                    Button(action: {
                        HapticManager.shared.mediumTap()
                        finishOnboarding()
                    }) {
                        Text("Skip")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                
                Spacer()
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        pageView(for: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(maxHeight: 600)
                
                Spacer()
                
                // Page indicators and buttons
                VStack(spacing: 30) {
                    // Page indicators
                    HStack(spacing: 12) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 10, height: 10)
                                .scaleEffect(currentPage == index ? 1.2 : 1.0)
                                .animation(.spring(), value: currentPage)
                        }
                    }
                    
                    // Next/Get Started button
                    Button(action: {
                        HapticManager.shared.mediumTap()
                        if currentPage < pages.count - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            finishOnboarding()
                        }
                    }) {
                        HStack {
                            Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                                .font(.headline)
                                .foregroundColor(pages[currentPage].backgroundColor)
                            
                            Image(systemName: "arrow.right")
                                .font(.headline)
                                .foregroundColor(pages[currentPage].backgroundColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.light) // Force light mode for better visual appeal
        .sheet(isPresented: $showingCurrencyPicker) {
            CurrencyPickerView(viewModel: viewModel)
        }
    }
    
    private func pageView(for page: OnboardingPage) -> some View {
        VStack(spacing: 30) {
            // Image
            Image(systemName: page.imageName)
                .font(.system(size: 100))
                .foregroundColor(.white)
                .padding()
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 180, height: 180)
                )
            
            // Title
            Text(page.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Description
            Text(page.description)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .padding(.horizontal)
        }
        .padding(.horizontal, 20)
    }
    
    private func finishOnboarding() {
        // Mark onboarding as completed
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        // Default to light mode
        if viewModel.appearanceMode == .system {
            viewModel.appearanceMode = .light
        }
        
        // Show currency picker immediately after onboarding
        withAnimation {
            showOnboarding = false
            
            // Show currency picker with a slight delay to allow for smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingCurrencyPicker = true
            }
        }
    }
}

struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let backgroundColor: Color
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(showOnboarding: .constant(true))
            .environmentObject(ExpenseViewModel())
    }
} 