import SwiftUI

struct MainTabView: View {
    @StateObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var categoryViewModel: CategoryViewModel
    /// Subscribed (not just declared) so the tab bar tint and any
    /// SwiftUI-side `.appPrimary` reads re-render the moment the user picks
    /// a new accent theme. Without this subscription SwiftUI has no reason
    /// to re-evaluate the body and the tint visually lags behind.
    @EnvironmentObject private var themeStore: ThemeStore
    @StateObject private var feedbackManager = FeedbackManager.shared
    @State private var selectedTab: Tab = .home
    @State private var showingAddExpense = false
    @State private var showingCurrencyPicker = false
    @State private var showingFeedbackRequest = false
    
    // Tab bar configuration
    private let tabBarHeight: CGFloat = 60
    
    init(viewModel: ExpenseViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)

        // iOS 26+ uses the native Liquid Glass floating tab bar — no UITabBar
        // appearance customization needed (and we must NOT hide UITabBar).
        // For iOS 18–25, keep the existing custom tab bar setup.
        if #available(iOS 26.0, *) {
            // No-op: SwiftUI Tab + .tint(.appPrimary) handles everything in
            // the body, and `themeStore` observation triggers re-renders.
        } else {
            Self.configureLegacyTabBarAppearance()
        }
    }

    private static func configureLegacyTabBarAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()

        // Theme-aware tint — closure runs lazily per UIKit color resolution
        // and reads the live `ThemeStore.activeTheme`, so the legacy tab bar
        // (iOS 18–25) follows the same accent rules as the SwiftUI surfaces.
        let dynamicTint = UIColor { traitCollection in
            let theme = ThemeStore.activeTheme
            let hex = traitCollection.userInterfaceStyle == .dark ? theme.primaryDarkHex : theme.primaryLightHex
            return UIColor(hex: hex)
                ?? UIColor(hex: AppTheme.mauve.primaryLightHex)
                ?? .systemPurple
        }

        UITabBar.appearance().tintColor = dynamicTint

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.selected.iconColor = dynamicTint
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: dynamicTint]

        tabBarAppearance.stackedLayoutAppearance = itemAppearance
        tabBarAppearance.inlineLayoutAppearance = itemAppearance
        tabBarAppearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Hide the default tab bar (we draw our own custom one on iOS < 26).
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        // Mount the global save-error banner once at the tab root so
        // it covers every screen, sheet, and destination beneath
        // (the overlay floats above the floating tab bar). All
        // CRUD viewmodels post via `SaveErrorReporter.report(...)`
        // on a save failure; the banner host listens and renders a
        // non-blocking, auto-dismissing card. No save site needs to
        // know about the UI.
        .saveErrorBannerHost()
    }

    // MARK: - iOS 26+ native Liquid Glass tab bar

    @available(iOS 26.0, *)
    private var modernTabView: some View {
        // Theme id is folded into each tab's `.id(...)` so the tab content
        // remounts cleanly on a theme change. Without this the dynamic
        // `Color.appPrimary` reads inside child views (pills, buttons,
        // medallions, etc.) keep their previously-resolved value because
        // SwiftUI sees no input change and skips re-rendering them.
        let themeId = themeStore.currentTheme.id

        return TabView(selection: $selectedTab) {
            SwiftUI.Tab("Home", systemImage: "house.fill", value: Tab.home) {
                HomeView()
                    .environmentObject(viewModel)
                    .id("home-\(themeId)")
            }

            SwiftUI.Tab("Subscriptions", systemImage: "creditcard.and.123", value: Tab.subscriptions) {
                SubscriptionsView(expenseViewModel: viewModel)
                    .id("subs-\(themeId)")
            }

            SwiftUI.Tab("Statistics", systemImage: "chart.bar.fill", value: Tab.statistics) {
                StatisticsView()
                    .environmentObject(viewModel)
                    .id("stats-\(themeId)")
            }
        }
        .tint(.appPrimary)
        .overlay(alignment: .bottomTrailing) {
            if selectedTab == .home {
                let isPad = UIDevice.current.userInterfaceIdiom == .pad
                FloatingAddButton(
                    action: { showingAddExpense = true },
                    isIPad: isPad
                )
                .padding(.trailing, isPad ? 30 : 20)
                // Sit just above the floating Liquid Glass tab bar with a
                // small visual gap so the FAB feels grouped, not isolated.
                .padding(.bottom, isPad ? 82 : 68)
            }
        }
        .overlay {
            if showingFeedbackRequest {
                FeedbackRequestView()
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                    .zIndex(100)
            }
        }
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
        .onChange(of: selectedTab) { _, _ in
            HapticManager.shared.selectionChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            // The iOS 26 native `TabView` is fully SwiftUI — `.tint(.appPrimary)`
            // already re-resolves on the per-tab `.id` rebuild above. This
            // handler is intentionally empty for the modern path; kept here
            // so the codepath is symmetrical with the legacy variant below.
        }
    }

    // MARK: - iOS 18–25 legacy custom tab bar

    private var legacyTabView: some View {
        // See `modernTabView` — theme id is folded into each tab's `.id(...)`
        // so child views re-evaluate `Color.appPrimary` on a theme change.
        let themeId = themeStore.currentTheme.id

        return GeometryReader { geometry in
            ZStack {
                // Main content
                TabView(selection: $selectedTab) {
                    HomeView()
                        .environmentObject(viewModel)
                        .tag(Tab.home)
                        .id("home-\(themeId)")
                    
                    SubscriptionsView(expenseViewModel: viewModel)
                        .tag(Tab.subscriptions)
                        .id("subs-\(themeId)")
                    
                    StatisticsView()
                        .environmentObject(viewModel)
                        .tag(Tab.statistics)
                        .id("stats-\(themeId)")
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
            .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
                // Legacy `UITabBar.appearance()` caches resolved tint colors.
                // Re-apply with the now-current `ThemeStore.activeTheme` so
                // the tab icons / titles pick up the new accent immediately.
                Self.configureLegacyTabBarAppearance()
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
            .foregroundColor(isSelected ? .appPrimary : .secondary)
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
