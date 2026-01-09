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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var showSplash = true

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
                            // Only refresh data if needed, don't recreate the entire UI
                            viewModel.refreshData()
                            
                            Task {
                                await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                            }
                        }
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
        }
    }
}
