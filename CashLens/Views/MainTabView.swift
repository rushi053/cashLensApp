import SwiftUI

struct MainTabView: View {
    @StateObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var categoryViewModel: CategoryViewModel
    @StateObject private var feedbackManager = FeedbackManager.shared
    @State private var selectedTab: Tab = .home
    @State private var showingAddExpense = false
    @State private var showingCurrencyPicker = false
    @State private var showingFeedbackRequest = false
    
    // Tab bar configuration
    private let tabBarHeight: CGFloat = 60
    
    init(viewModel: ExpenseViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        
        // Customize tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        
        // Set the selected item color to the exact same mauve/lavender used in time frame selector
        // Get the UIColor representation of our Color.mauve for both light and dark mode
        let lightMauve = UIColor(red: 190/255, green: 155/255, blue: 240/255, alpha: 1.0)
        let darkMauve = UIColor(red: 160/255, green: 125/255, blue: 210/255, alpha: 1.0)
        
        // Create a dynamic color that adapts to light/dark mode
        let dynamicMauve = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? darkMauve : lightMauve
        }
        
        // Apply the color to the tab bar
        UITabBar.appearance().tintColor = dynamicMauve
        
        // Configure the tab bar item appearance for normal and selected states
        let itemAppearance = UITabBarItemAppearance()
        
        // Set the selected icon color
        itemAppearance.selected.iconColor = dynamicMauve
        
        // Set the selected text color
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: dynamicMauve]
        
        // Apply the item appearance to all tab bar positions
        tabBarAppearance.stackedLayoutAppearance = itemAppearance
        tabBarAppearance.inlineLayoutAppearance = itemAppearance
        tabBarAppearance.compactInlineLayoutAppearance = itemAppearance
        
        // Apply the appearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // Hide the default tab bar
        UITabBar.appearance().isHidden = true
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content
                TabView(selection: $selectedTab) {
                    HomeView()
                        .environmentObject(viewModel)
                        .tag(Tab.home)
                    
                    SubscriptionsView(expenseViewModel: viewModel)
                        .tag(Tab.subscriptions)
                    
                    StatisticsView()
                        .environmentObject(viewModel)
                        .tag(Tab.statistics)
                }
                
                // Floating Add Button - only visible on Home tab
                if selectedTab == .home {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            FloatingAddButton(
                                action: { showingAddExpense = true },
                                isIPad: isIPad(geometry)
                            )
                            .padding(.trailing, isIPad(geometry) ? 30 : 20)
                            .padding(.bottom, tabBarHeight + geometry.safeAreaInsets.bottom + (isIPad(geometry) ? 20 : 10))
                        }
                    }
                }
                
                // Custom tab bar
                VStack {
                    Spacer()
                    
                    // Tab bar background and items
                    VStack(spacing: 0) {
                        // Tab bar background
                            Rectangle()
                                .fill(Color.systemBackground)
                            .frame(height: tabBarHeight)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -4)
                            
                        // Bottom safe area background
                            Rectangle()
                                .fill(Color.systemBackground)
                                .frame(height: geometry.safeAreaInsets.bottom)
                        }
                    .overlay(
                        // Tab items
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                // Home tab
                                TabButton(
                                    icon: "house.fill",
                                    label: "Home",
                                    isSelected: selectedTab == .home,
                                    action: {
                                        selectedTab = .home
                                        HapticManager.shared.selectionChanged()
                                    },
                                    isIPad: isIPad(geometry)
                                )
                                
                                // Subscriptions tab
                                TabButton(
                                    icon: "creditcard.and.123",
                                    label: "Subscriptions",
                                    isSelected: selectedTab == .subscriptions,
                                    action: {
                                        selectedTab = .subscriptions
                                        HapticManager.shared.selectionChanged()
                                    },
                                    isIPad: isIPad(geometry)
                                )
                                
                                // Statistics tab
                                TabButton(
                                    icon: "chart.bar.fill",
                                    label: "Statistics",
                                    isSelected: selectedTab == .statistics,
                                    action: {
                                        selectedTab = .statistics
                                        HapticManager.shared.selectionChanged()
                                    },
                                    isIPad: isIPad(geometry)
                                )
                            }
                            .padding(.top, isIPad(geometry) ? 12 : 8)
                            
                            Spacer()
                        }
                        )
                }
                
                // Feedback Request Modal
                if showingFeedbackRequest {
                    FeedbackRequestView()
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                        .zIndex(100) // Ensure it appears above everything
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: viewModel)
                    .environmentObject(categoryViewModel)
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(viewModel: viewModel)
            }
            .onAppear {
                checkAndShowCurrencyPicker()
            }
            .onReceive(feedbackManager.$shouldShowFeedbackRequest) { shouldShow in
                showingFeedbackRequest = shouldShow
            }
        }
    }
    
    private func checkAndShowCurrencyPicker() {
        // Only show currency picker if onboarding has been completed
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        
        if !viewModel.hasShownCurrencyPicker && hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingCurrencyPicker = true
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
                viewModel.hasShownCurrencyPicker = true
            }
        }
    }

    // Helper to detect if we're on iPad
    private func isIPad(_ geometry: GeometryProxy) -> Bool {
        return geometry.size.width > 768 || UIDevice.current.userInterfaceIdiom == .pad
    }
}

// Custom Tab Button
struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    let isIPad: Bool
    
    init(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void, isIPad: Bool = false) {
        self.icon = icon
        self.label = label
        self.isSelected = isSelected
        self.action = action
        self.isIPad = isIPad
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: isIPad ? 6 : 4) {
                Image(systemName: icon)
                    .font(.system(size: isIPad ? 24 : 20, weight: .medium))
                
                Text(label)
                    .font(.system(size: isIPad ? 11 : 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .mauve : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: isIPad ? 50 : 40)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum Tab: String {
    case home, subscriptions, statistics
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        let previewViewModel = ExpenseViewModel()
        return MainTabView(viewModel: previewViewModel)
    }
} 
