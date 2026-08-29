import SwiftUI
import StoreKit

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
    @EnvironmentObject private var proManager: ProManager
    @State private var selectedTab: Tab = .today
    @State private var showingAddExpense = false
    @State private var showingCurrencyPicker = false

    /// Native one-tap rating sheet. `FeedbackManager` decides *when* to
    /// ask; this action shows Apple's in-app star prompt directly — no
    /// intermediate modal, so rating is a single tap.
    @Environment(\.requestReview) private var requestReview

    // MARK: - Post-value paywall trigger

    /// Expense count captured when the add sheet opens, so the
    /// trigger can detect the save that *crosses* the threshold.
    /// `nil` when the sheet opened before full hydration — during the
    /// launch window `viewModel.expenses` only holds the recent hot
    /// window, and a capture there would fake a threshold crossing
    /// when the full history publishes mid-sheet.
    @State private var expenseCountAtAddSheetOpen: Int? = nil
    @State private var showingAutoPaywall = false

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
        // Success sibling of the error banner: a short-lived floating
        // capsule ("Added ₹450 to Food") posted by the add/edit expense
        // save paths via `SaveConfirmationReporter.report(...)`. Mounted
        // here so it appears over the presenting tab as the save sheet
        // slides away.
        .saveConfirmationToastHost()
        // Post-value paywall: watches the add-expense sheet (both the
        // modern and legacy tab paths present through the same
        // `showingAddExpense` binding) and evaluates the trigger when
        // it closes — never during the save moment itself.
        .onChange(of: showingAddExpense) { _, isPresented in
            if isPresented {
                // Only trust the count once the full history has
                // published; a hot-window count would read as a fake
                // crossing (e.g. 8 → 300) when hydration completes.
                expenseCountAtAddSheetOpen = viewModel.isFullyHydrated
                    ? viewModel.expenses.count
                    : nil
            } else {
                maybeShowPostValuePaywall()
            }
        }
        .sheet(isPresented: $showingAutoPaywall) {
            PaywallView(context: .insights)
                // Spend the once-ever shot only when the paywall is
                // actually on screen — writing the flags before the
                // 1.2s presentation delay meant a kill/background in
                // that window consumed the auto-show invisibly.
                .onAppear {
                    let defaults = UserDefaults.standard
                    defaults.set(true, forKey: UserDefaultsKeys.hasAutoShownPaywall)
                    defaults.set(Date(), forKey: UserDefaultsKeys.lastAutoPaywallDate)
                }
        }
        // One-time thank-you when a past donor's grandfather grant is
        // first applied. Same consume-on-appear contract as the
        // win-back sheet below: if presentation is blocked, ProManager
        // re-queues at the next launch scan.
        .sheet(item: $proManager.pendingDonorThanks) { grant in
            DonorThanksView(grant: grant)
                .onAppear { proManager.markDonorThanksShown() }
        }
        // One-time win-back after a Pro → free lapse. ProManager arms
        // this on foreground; at most once per lapse, never after
        // "No thanks", never for grandfathered donors.
        .sheet(isPresented: $proManager.shouldShowWinBack) {
            WinBackView()
                .environmentObject(proManager)
                // Consume the once-per-lapse shot only now that the
                // sheet is actually on screen. If another sheet had
                // blocked presentation, the pending flag survives for
                // the next foreground instead of being spent invisibly.
                .onAppear { proManager.markWinBackShown() }
        }
    }

    /// Evaluates `PaywallTrigger` after the add sheet dismisses and,
    /// on a hit, presents the paywall once after a short delay — so
    /// the save toast lands first and the moment never feels
    /// interrupted.
    private func maybeShowPostValuePaywall() {
        // Both ends of the crossing must come from the fully hydrated
        // dataset — bail if the sheet opened pre-hydration (no trusted
        // capture) or hydration still hasn't finished now.
        guard viewModel.isFullyHydrated,
              let previousCount = expenseCountAtAddSheetOpen else { return }
        let defaults = UserDefaults.standard
        let trigger = PaywallTrigger(
            previousCount: previousCount,
            currentCount: viewModel.expenses.count,
            isPro: proManager.isPro,
            hasAutoShownBefore: defaults.bool(forKey: UserDefaultsKeys.hasAutoShownPaywall),
            lastAutoShowDate: defaults.object(forKey: UserDefaultsKeys.lastAutoPaywallDate) as? Date
        )
        guard trigger.shouldAutoShow else { return }

        // NOTE: the once-ever flags are written from the paywall
        // sheet's `onAppear`, not here — see the sheet above.

        // Long enough for the sheet's dismissal animation and a beat
        // of the confirmation toast; short enough to still read as a
        // response to what the user just did.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            // If the user locked/backgrounded during the delay, skip —
            // a sheet would otherwise present above the lock overlay.
            guard !AppLockManager.shared.isLocked else { return }
            showingAutoPaywall = true
        }
    }

    /// True while a child tab (currently only AllExpensesView) is in
    /// bulk-select mode. Driven via `\.bulkSelectionBinding` env key
    /// so the child writes upward without us reaching into its
    /// internal state, and we read here to gate the FAB.
    @State private var isBulkSelecting: Bool = false

    /// FAB shows on every tab except `You`. The v1 app hid the FAB
    /// behind Home only — the IA audit caught this as a tap-cost
    /// problem (users on Stats had to flip back to Home just to log
    /// the expense they just thought of). v2 keeps the FAB present
    /// anywhere the user is thinking about money. The settings tab
    /// (`You`) is the only place where it would feel like noise.
    ///
    /// Also hidden in bulk-selection mode — Activity surfaces an
    /// inline action bar at the bottom there, and a floating "+"
    /// would overlap (and visually compete with) those actions.
    private var shouldShowFAB: Bool {
        selectedTab != .you && !isBulkSelecting
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
                TodayView(
                    onSeeAllActivity: { selectedTab = .activity },
                    onOpenInsights: { selectedTab = .insights },
                    onRequestAddExpense: { showingAddExpense = true }
                )
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
                // PERF: mount Profile only while You is selected.
                // TabView keeps visited tab roots alive; Profile observes
                // ~7 EnvironmentObjects + a large settings tree, so once
                // mounted it re-diffed on every expenses/budgets/pro
                // publish — permanently stuttering later tab transitions
                // ("smooth until I open You"). Unmounting when hidden
                // removes that fan-out; settings don't need to keep
                // scroll position across tabs.
                youTabRoot(themeId: themeId)
            }
        }
        .tint(.appPrimary)
        .environment(\.bulkSelectionBinding, $isBulkSelecting)
        .animation(Theme.Motion.snappy, value: isBulkSelecting)
        .overlay(alignment: .bottomTrailing) {
            // ZStack + scoped `.animation(value:)` so the FAB's
            // insert/remove transition runs on its own clock instead of
            // joining the system's tab-switch transaction — hiding it
            // when landing on You must never retime the bar's own
            // selection animation.
            ZStack {
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
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.snappy, value: shouldShowFAB)
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
            guard shouldShow else { return }
            feedbackManager.consumePromptTrigger()
            // Never over the app-lock cover; the missed ask retries
            // naturally at the next eligible moment (30d cooldown).
            guard !AppLockManager.shared.isLocked else { return }
            requestReview()
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
                    TodayView(
                        onSeeAllActivity: { selectedTab = .activity },
                        onOpenInsights: { selectedTab = .insights },
                        onRequestAddExpense: { showingAddExpense = true }
                    )
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

                    youTabRoot(themeId: themeId)
                        .tag(Tab.you)
                }
                .environment(\.bulkSelectionBinding, $isBulkSelecting)
                .animation(Theme.Motion.snappy, value: isBulkSelecting)

                // Floating Add Button - visible on Today + Activity
                // (hidden in bulk-select mode so it doesn't overlap
                // the inline selection action bar). Wrapped in a ZStack
                // with a scoped animation so its show/hide transition
                // animates on its own clock and never retimes the tab
                // switch itself.
                ZStack {
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
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
                .animation(Theme.Motion.snappy, value: shouldShowFAB)

                // Custom tab bar
                VStack {
                    Spacer()

                    // Tab bar background and items. Real system material
                    // (`.bar`) instead of the old flat fill + shadow, so
                    // content scrolling underneath reads through it the
                    // way it does under native bars — with the design
                    // system's hairline as the top edge.
                    Rectangle()
                        .fill(.bar)
                        .frame(height: tabBarHeight + geometry.safeAreaInsets.bottom)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: Theme.Stroke.hairline)
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
                guard shouldShow else { return }
                feedbackManager.consumePromptTrigger()
                guard !AppLockManager.shared.isLocked else { return }
                requestReview()
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

    /// You tab content — Profile is mounted only while selected so its
    /// EnvironmentObject fan-out can't tax Today/Activity/Insights
    /// transitions after the first visit.
    @ViewBuilder
    private func youTabRoot(themeId: String) -> some View {
        Group {
            if selectedTab == .you {
                ProfileView()
                    .environmentObject(viewModel)
            } else {
                Color.systemBackground
                    .ignoresSafeArea()
            }
        }
        .id("you-\(themeId)")
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

                // Scaled via UIFontMetrics so the label follows Dynamic
                // Type (the bar itself stays fixed-height, like the
                // native tab bar, so extreme sizes truncate gracefully).
                Text(label)
                    .font(.system(
                        size: UIFontMetrics(forTextStyle: .caption2)
                            .scaledValue(for: isIPad ? 11 : 9),
                        weight: .medium
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

// MARK: - Bulk selection environment binding
//
// Lets a child tab (currently AllExpensesView) tell the root tab
// view "I'm in bulk-select mode" so the root can hide the floating
// "+" button while a contextual action bar is on screen. Using a
// Binding keeps the source of truth in the child; MainTabView only
// reads it to gate the FAB. Defaults to a no-op binding so any
// view written without awareness of this key still compiles and
// renders normally outside the tab container (e.g. in previews).
private struct BulkSelectionBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var bulkSelectionBinding: Binding<Bool> {
        get { self[BulkSelectionBindingKey.self] }
        set { self[BulkSelectionBindingKey.self] = newValue }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        let previewViewModel = ExpenseViewModel()
        return MainTabView(viewModel: previewViewModel)
    }
}
