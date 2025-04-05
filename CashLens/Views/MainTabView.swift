import SwiftUI

struct MainTabView: View {
    @StateObject var viewModel: ExpenseViewModel
    @State private var selectedTab: Tab = .home
    @State private var showingAddExpense = false
    @State private var showingCurrencyPicker = false
    
    // Tab bar configuration
    private let tabBarHeight: CGFloat = 50
    private let addButtonSize: CGFloat = 56
    private let addButtonYOffset: CGFloat = -20
    
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
            ZStack(alignment: .bottom) {
                // Main content
                TabView(selection: $selectedTab) {
                    HomeView()
                        .environmentObject(viewModel)
                        .tag(Tab.home)
                    
                    StatisticsView()
                        .environmentObject(viewModel)
                        .tag(Tab.statistics)
                }
                
                // Custom tab bar - adapted for iPad
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Tab bar with background
                    ZStack {
                        // Tab bar background
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.systemBackground)
                                .frame(height: tabBarHeight + (isIPad(geometry) ? 10 : 0)) // Taller tab bar on iPad
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
                            
                            // This rectangle extends to fill the bottom safe area
                            Rectangle()
                                .fill(Color.systemBackground)
                                .frame(height: geometry.safeAreaInsets.bottom)
                        }
                        
                        // Tab items
                        VStack(spacing: 0) {
                            HStack {
                                // Home tab
                                Spacer()
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
                                
                                // Spacer for add button - wider on iPad
                                Spacer()
                                if isIPad(geometry) {
                                    Spacer()
                                    Spacer()
                                }
                                Spacer()
                                
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
                                Spacer()
                            }
                            .padding(.top, isIPad(geometry) ? 10 : 6) // More padding on iPad
                            
                            // Add spacer to push content up from bottom safe area
                            Spacer()
                                .frame(height: geometry.safeAreaInsets.bottom)
                        }
                        
                        // Add button - larger on iPad
                        AddButton(
                            action: { showingAddExpense = true },
                            isIPad: isIPad(geometry)
                        )
                        .offset(y: addButtonYOffset)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(viewModel: viewModel)
            }
            .onAppear {
                checkAndShowCurrencyPicker()
            }
        }
    }
    
    private func checkAndShowCurrencyPicker() {
        // Only show currency picker if onboarding has been completed
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !viewModel.hasShownCurrencyPicker && hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingCurrencyPicker = true
                UserDefaults.standard.set(true, forKey: "hasShownCurrencyPicker")
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
            VStack(spacing: isIPad ? 8 : 6) {
                Image(systemName: icon)
                    .font(.system(size: isIPad ? 26 : 22))
                
                Text(label)
                    .font(.system(size: isIPad ? 12 : 10, weight: .semibold))
            }
            .foregroundColor(isSelected ? .mauve : .secondary)
            .frame(width: isIPad ? 90 : 70, height: isIPad ? 56 : 44)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum Tab: String {
    case home, statistics
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        let previewViewModel = ExpenseViewModel()
        return MainTabView(viewModel: previewViewModel)
    }
} 
