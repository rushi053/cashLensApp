//
//  CashLensApp.swift
//  CashLens
//
//  Created by Rushiraj Jadeja on 10/03/25.
//

import SwiftUI
import CoreData
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
    @StateObject private var categoryViewModel: CategoryViewModel
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var proManager = ProManager.shared
    @StateObject private var budgetViewModel: BudgetViewModel
    /// Promoted to app-level so Today (and any future surface) can
    /// read upcoming bills without spinning up a second instance.
    @StateObject private var subscriptionViewModel: SubscriptionViewModel
    @StateObject private var themeStore = ThemeStore.shared
    @StateObject private var appIconStore = AppIconStore.shared
    @StateObject private var appLockManager = AppLockManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var showCurrencyPicker = false

    init() {
        // SAFETY: If the persistent store failed to load, every view model
        // is wired to a throwaway in-memory container instead — fetching
        // against a coordinator with zero stores raises an exception, and
        // the whole point of the recovery flow is to never crash. The body
        // renders `StoreRecoveryView` in that case, so the in-memory
        // container is never visible to the user and the broken store on
        // disk is never touched.
        let context: NSManagedObjectContext
        if PersistenceController.shared.storeLoadFailed {
            context = PersistenceController(inMemory: true).container.viewContext
        } else {
            context = PersistenceController.shared.container.viewContext
        }

        // Create plain instances first so the expense-view-model dependency
        // can be wired *before* anything renders, then wrap in StateObjects.
        // The old `.onAppear` wiring left a window where
        // `markSubscriptionAsPaid` could run with a nil expenseViewModel
        // and silently drop the logged expense.
        let expenseVM = ExpenseViewModel(context: context)
        let budgetVM = BudgetViewModel(context: context)
        let subscriptionVM = SubscriptionViewModel(context: context)
        budgetVM.setExpenseViewModel(expenseVM)
        subscriptionVM.setExpenseViewModel(expenseVM)

        _viewModel = StateObject(wrappedValue: expenseVM)
        _budgetViewModel = StateObject(wrappedValue: budgetVM)
        _subscriptionViewModel = StateObject(wrappedValue: subscriptionVM)
        _categoryViewModel = StateObject(wrappedValue: CategoryViewModel(context: context))
        
        // Check if this is the first launch
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if persistenceController.storeLoadFailed {
                    // The store couldn't be opened (version mismatch or
                    // corruption). Show the calm recovery screen — data on
                    // disk is untouched and exportable from here.
                    StoreRecoveryView(storeFileURLs: persistenceController.storeFileURLs)
                } else {
                    mainContent
                }

                // App Lock overlay — topmost layer, above onboarding and
                // even the store-recovery screen (the recovery page shows
                // no amounts, but one consistent rule is simpler than a
                // special case). Drives itself from scene-phase changes
                // via the handler below.
                if appLockManager.isCoverVisible {
                    AppLockView(lockManager: appLockManager)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                appLockManager.handleScenePhase(newPhase)
            }
        }
    }

    private var mainContent: some View {
            ZStack {
                MainTabView(viewModel: viewModel)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(categoryViewModel)
                    .environmentObject(proManager)
                    .environmentObject(budgetViewModel)
                    .environmentObject(subscriptionViewModel)
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
                        case .addExpense:
                            // Quick Log widget "+" button → straight
                            // into the add-expense sheet.
                            AddExpenseView(viewModel: viewModel)
                                .environmentObject(categoryViewModel)
                        }
                    }
                    .onOpenURL { url in
                        deepLinkRouter.handleURL(url)
                    }
                    // (Removed a dead `.appearanceDidChange` handler here —
                    // `preferredColorScheme` reacts on its own.)
                    .onReceive(NotificationCenter.default.publisher(for: .appDidUnlock)) { _ in
                        // A notification/widget tap that arrived while the
                        // app was locked parked its route; present it now
                        // that the user has authenticated. Win-back
                        // evaluation was likewise skipped while locked.
                        deepLinkRouter.flushPendingRoute()
                        proManager.evaluateWinBackPrompt()
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

                            // Drain any expenses queued by the Quick Log
                            // widget (its intent runs in the widget
                            // extension process and can't reach the
                            // app-container store). Off-main; idempotent;
                            // handles days of accumulation. The drain
                            // itself re-publishes the widget snapshot so
                            // the widget's optimistic total reconciles.
                            drainWidgetQueueInBackground()

                            // Re-verify Pro entitlements on every foreground so
                            // mid-session expiry, refunds, or revocations are
                            // picked up without waiting for a relaunch.
                            Task {
                                await proManager.checkEntitlements()
                                // A detected Pro → free lapse (this
                                // session or a previous one) surfaces
                                // the one-time win-back sheet here.
                                proManager.evaluateWinBackPrompt()
                            }

                            Task {
                                // Digest bodies aggregate over the full
                                // history; don't compute them off the
                                // partial launch window.
                                await viewModel.waitUntilFullyHydrated()
                                // Roll any past-due subscription forward to
                                // its next future occurrence and re-arm its
                                // reminder — otherwise overdue subscriptions
                                // sit with a stale date forever and reminders
                                // die after one cycle. Runs before the
                                // scheduler refresh so digests see the
                                // reconciled dates.
                                subscriptionViewModel.reconcileOverdueSubscriptions()
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
            }
            .animation(.easeInOut, value: showOnboarding)
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
    /// Move widget-queued expenses into Core Data off the main thread,
    /// then surface one calm toast if anything landed. Safe to run on
    /// every foreground — a no-op when the queue is empty.
    private func drainWidgetQueueInBackground() {
        Task.detached(priority: .userInitiated) {
            let drained = QuickLogService.drainWidgetQueue()
            guard drained > 0 else { return }
            SaveConfirmationReporter.report(
                message: drained == 1
                    ? "Added 1 expense from your widget"
                    : "Added \(drained) expenses from your widget"
            )
        }
    }

    private func cleanupReceiptOrphansInBackground() {
        // SAFETY: With phased hydration, `expenses` may hold only the
        // recent launch window. Sweeping against that partial keep-set
        // would delete receipts still referenced by older expenses.
        // Only run once the full table has been published.
        guard viewModel.isFullyHydrated else { return }
        let expensesSnapshot = viewModel.expenses
        // SAFETY: If the in-memory expense list is empty (e.g. a failed
        // `loadExpenses()` resets it to []), the keep-set would be empty
        // and the sweep would delete EVERY receipt on disk even though
        // the expenses still exist in Core Data. Skip the sweep entirely
        // in that case — orphans will be caught on a later foreground.
        guard !expensesSnapshot.isEmpty else { return }
        Task.detached(priority: .background) {
            let referenced = Set(expensesSnapshot.compactMap { $0.receiptImagePath })
            ReceiptStorage.cleanupOrphans(keep: referenced)
        }
    }
}
