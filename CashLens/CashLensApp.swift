//
//  CashLensApp.swift
//  CashLens
//
//  Created by Rushiraj Jadeja on 10/03/25.
//

import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // Show notifications while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            DeepLinkRouter.shared.handleNotificationUserInfo(userInfo)
        }
        completionHandler()
    }
}

@main
struct CashLensApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel: ExpenseViewModel
    @StateObject private var categoryViewModel = CategoryViewModel()
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var proManager = ProManager.shared
    @StateObject private var budgetViewModel = BudgetViewModel()
    @StateObject private var themeStore = ThemeStore.shared
    @StateObject private var appIconStore = AppIconStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var showSplash = true
    @State private var showCurrencyPicker = false

    init() {
        let context = persistenceController.container.viewContext
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
        
        // Check if this is the first launch
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView(viewModel: viewModel)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(categoryViewModel)
                    .environmentObject(proManager)
                    .environmentObject(budgetViewModel)
                    .environmentObject(themeStore)
                    .environmentObject(appIconStore)
                    .preferredColorScheme(viewModel.appearanceMode.colorScheme)
                    .sheet(item: $deepLinkRouter.route) { route in
                        switch route {
                        case .allExpenses(let filter):
                            AllExpensesView(initialFilter: filter)
                                .environmentObject(viewModel)
                                .environmentObject(categoryViewModel)
                        case .export:
                            ExportDataView()
                                .environmentObject(viewModel)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .appearanceDidChange)) { _ in
                        // Note: Removed forceUpdate to prevent view recreation which dismisses sheets
                        // The preferredColorScheme binding should handle appearance changes automatically
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        if newPhase == .active {
                            viewModel.refreshData()
                            budgetViewModel.refreshProgressFromData()
                            // Push a fresh widget snapshot whenever the
                            // app foregrounds — covers the "user added an
                            // expense from another device / Shortcut /
                            // import" case where in-app `@Published`
                            // state didn't drive the change.
                            WidgetSnapshotCoordinator.shared.refreshNow()

                            Task {
                                await NotificationScheduler.refreshScheduledNotificationsIfNeeded(
                                    viewModel: viewModel,
                                    isPro: proManager.isPro
                                )
                            }

                            // Once-per-foreground orphan sweep for the
                            // Receipts directory. Catches the rare
                            // crash-between-write-and-delete window and
                            // any file that survived a failed import.
                            // Runs in the background so it never blocks
                            // the UI; the cost is one shallow directory
                            // read + at most a few `unlink` calls.
                            cleanupReceiptOrphansInBackground()
                        }
                    }
                    .onAppear {
                        budgetViewModel.setExpenseViewModel(viewModel)
                        // Bootstrap the widget snapshot pipe as soon as
                        // every app-level dependency is alive. The
                        // coordinator installs its Combine subscriptions
                        // once and writes an initial snapshot so a
                        // freshly-installed widget gets real data on its
                        // very first render instead of waiting for the
                        // user's next mutation.
                        WidgetSnapshotCoordinator.shared.bootstrap(
                            expenseVM: viewModel,
                            budgetVM: budgetViewModel,
                            categoryVM: categoryViewModel,
                            proManager: proManager,
                            themeStore: themeStore,
                            viewContext: persistenceController.container.viewContext
                        )
                    }
                
                // Show onboarding screen if needed
                if showOnboarding {
                    OnboardingView(showOnboarding: $showOnboarding)
                        .environmentObject(viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        ))
                        .zIndex(1) // Ensure onboarding is displayed over the main app
                }
                
                // Show splash screen
                if showSplash {
                    SplashScreenView(showSplash: $showSplash)
                        .transition(.opacity)
                        .zIndex(2) // Highest z-index to show above everything else
                }
            }
            .animation(.easeInOut, value: showOnboarding)
            .animation(.easeInOut, value: showSplash)
            .onChange(of: showOnboarding) { _, newValue in
                // When onboarding completes, show currency picker if not already shown
                if !newValue && !UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasShownCurrencyPicker) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showCurrencyPicker = true
                    }
                }
            }
            .sheet(isPresented: $showCurrencyPicker, onDismiss: {
                // Mark currency picker as shown
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasShownCurrencyPicker)
            }) {
                CurrencyPickerView(viewModel: viewModel, isInitialSetup: true)
            }
        }
    }

    /// Once-per-foreground sweep for the Receipts directory. Reads all
    /// `receiptImagePath` values currently referenced by the live
    /// expenses and deletes any file in `Documents/Receipts/` that
    /// isn't in that set. Idempotent and safe — does nothing if the
    /// directory doesn't exist (fresh install with no receipts).
    ///
    /// PERF: We capture the expense array by value (cheap thanks to
    /// Swift's copy-on-write storage) and do the O(N) `compactMap` +
    /// `Set` build **inside** the detached task, not on main. The
    /// previous implementation did the scan on the main actor before
    /// hopping off — a small but real per-foreground cost that grew
    /// with expense count.
    private func cleanupReceiptOrphansInBackground() {
        let expensesSnapshot = viewModel.expenses
        Task.detached(priority: .background) {
            let referenced = Set(expensesSnapshot.compactMap { $0.receiptImagePath })
            ReceiptStorage.cleanupOrphans(keep: referenced)
        }
    }
}
