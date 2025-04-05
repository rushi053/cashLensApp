//
//  CashLensApp.swift
//  CashLens
//
//  Created by Rushiraj Jadeja on 10/03/25.
//

import SwiftUI

@main
struct CashLensApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var viewModel: ExpenseViewModel
    @StateObject private var categoryViewModel = CategoryViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var forceUpdate = false
    @State private var showOnboarding = false
    @State private var showSplash = true

    init() {
        let context = persistenceController.container.viewContext
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
        
        // Check if this is the first launch
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView(viewModel: viewModel)
                    .id(forceUpdate ? 1 : 0) // Force view refresh when appearance changes
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(categoryViewModel)
                    .preferredColorScheme(viewModel.appearanceMode.colorScheme)
                    .onReceive(NotificationCenter.default.publisher(for: .appearanceDidChange)) { _ in
                        // Toggle the force update state to trigger a view refresh
                        forceUpdate.toggle()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        if newPhase == .active {
                            // Refresh UI when app becomes active
                            forceUpdate.toggle()
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
