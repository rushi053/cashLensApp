import SwiftUI

/// v2 information architecture — see `redesign/v2` notes in
/// the project README and the audit canvases.
///
/// Old tabs (v1): Home / Subscriptions / Statistics, with Profile
/// hidden behind a header icon on Home only.
///
/// New tabs (v2): **Today / Activity / Insights / You**.
///
/// Why the change (from the IA audit):
///
///   • The ledger (`AllExpensesView`) — the app's most capable
///     screen, with search, calendar, bulk select, filters — used
///     to live in a sheet two taps from Home. It earns top-level
///     promotion as **Activity**.
///   • **Subscriptions** as a top-level tab over-indexed for the
///     median user. Most users have 5–10 subs and glance at them
///     weekly. The screen still exists (reachable from `You` →
///     Subscriptions) and recurring expenses show as a filter chip
///     inside Activity, but the tab itself is gone.
///   • **Profile** held high-stakes utilities (currency, export,
///     backup, themes, budgets) and yet had no stable home —
///     it was a sheet you could only reach from Home's header.
///     Promoted to **You** so it's always one tap away.
///   • The new **Today** tab is built around answering "am I OK?"
///     in two seconds — verdict hero + 7-day spark + recent + one
///     insight. No browsing controls; this is a status screen.
struct MainTabView: View {
    @StateObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var categoryViewModel: CategoryViewModel
    /// Subscribed (not just declared) so the tab bar tint and any
    /// SwiftUI-side `.appPrimary` reads re-render the moment the user picks
    /// a new accent theme. Without this subscription SwiftUI has no reason
    /// to re-evaluate the body and the tint visually lags behind.
    @EnvironmentObject private var themeStore: ThemeStore
    @StateObject private var feedbackManager = FeedbackManager.shared
    @State private var selectedTab: Tab = .today
    @State private var showingAddExpense = false
    @State private var showingCurrencyPicker = false
    @State private var showingFeedbackRequest = false

    // Tab bar configuration (legacy custom tab bar only)
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

    /// FAB shows on every tab except `You`. The v1 app hid the FAB
    /// behind Home only — the IA audit caught this as a tap-cost
    /// problem (users on Stats had to flip back to Home just to log
    /// the expense they just thought of). v2 keeps the FAB present
    /// anywhere the user is thinking about money. The settings tab
    /// (`You`) is the only place where it would feel like noise.
    private var shouldShowFAB: Bool {
        selectedTab != .you
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
            SwiftUI.Tab("Today", systemImage: "sun.max.fill", value: Tab.today) {
                TodayView(onSeeAllActivity: { selectedTab = .activity })
                    .environmentObject(viewModel)
                    .id("today-\(themeId)")
            }

            SwiftUI.Tab("Activity", systemImage: "list.bullet.rectangle.fill", value: Tab.activity) {
                AllExpensesView(isRootTab: true)
                    .environmentObject(viewModel)
                    .environmentObject(categoryViewModel)
                    .id("activity-\(themeId)")
            }

            SwiftUI.Tab("Insights", systemImage: "chart.bar.xaxis", value: Tab.insights) {
                StatisticsView()
                    .environmentObject(viewModel)
                    .id("insights-\(themeId)")
            }

            SwiftUI.Tab("You", systemImage: "person.crop.circle.fill", value: Tab.you) {
                ProfileView(isRootTab: true)
                    .environmentObject(viewModel)
                    .id("you-\(themeId)")
            }
        }
        .tint(.appPrimary)
        .overlay(alignment: .bottomTrailing) {
            if shouldShowFAB {
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
                    TodayView(onSeeAllActivity: { selectedTab = .activity })
                        .environmentObject(viewModel)
                        .tag(Tab.today)
                        .id("today-\(themeId)")

                    AllExpensesView(isRootTab: true)
                        .environmentObject(viewModel)
                        .environmentObject(categoryViewModel)
                        .tag(Tab.activity)
                        .id("activity-\(themeId)")

                    StatisticsView()
                        .environmentObject(viewModel)
                        .tag(Tab.insights)
                        .id("insights-\(themeId)")

                    ProfileView(isRootTab: true)
                        .environmentObject(viewModel)
                        .tag(Tab.you)
                        .id("you-\(themeId)")
                }

                // Floating Add Button - visible on Today + Activity
                if shouldShowFAB {
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
                        Rectangle()
                            .fill(Color.systemBackground)
                            .frame(height: tabBarHeight)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -4)

                        Rectangle()
                            .fill(Color.systemBackground)
                            .frame(height: geometry.safeAreaInsets.bottom)
                    }
                    .overlay(
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                TabButton(
                                    icon: "sun.max.fill",
                                    label: "Today",
                                    isSelected: selectedTab == .today,
                                    action: {
                                        selectedTab = .today
                                        HapticManager.shared.selectionChanged()
                                    },
                                    isIPad: isIPad(geometry)
                                )

                                TabButton(
                                    icon: "list.bullet.rectangle.fill",
                                    label: "Activity",
                                    isSelected: selectedTab == .activity,
                                    action: {
                                        selectedTab = .activity
                                        HapticManager.shared.selectionChanged()
                                    },
                                    isIPad: isIPad(geometry)
                                )

                                TabButton(
                                    icon: "chart.bar.xaxis",
                                    label: "Insights",
                                    isSelected: selectedTab == .insights,
                                    action: {
                                        selectedTab = .insights
                                        HapticManager.shared.selectionChanged()
                                    },
                                    isIPad: isIPad(geometry)
                                )

                                TabButton(
                                    icon: "person.crop.circle.fill",
                                    label: "You",
                                    isSelected: selectedTab == .you,
                                    action: {
                                        selectedTab = .you
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
                        .zIndex(100)
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
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)

        if !viewModel.hasShownCurrencyPicker && hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingCurrencyPicker = true
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
                viewModel.hasShownCurrencyPicker = true
            }
        }
    }

    private func isIPad(_ geometry: GeometryProxy) -> Bool {
        return geometry.size.width > 768 || UIDevice.current.userInterfaceIdiom == .pad
    }
}

// Custom Tab Button (used by legacy iOS 18-25 path)
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

/// v2 tab identity. Legacy raw values (`home`, `subscriptions`,
/// `statistics`) are gone — any persisted last-selected-tab state
/// would have been per-launch only, so this is a safe rename.
enum Tab: String {
    case today, activity, insights, you
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        let previewViewModel = ExpenseViewModel()
        return MainTabView(viewModel: previewViewModel)
    }
}
