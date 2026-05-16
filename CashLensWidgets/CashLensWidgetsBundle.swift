//
//  CashLensWidgetsBundle.swift
//  CashLensWidgets
//
//  Entry point for the widget extension. Lists every widget the bundle
//  vends — Home Screen widgets first, then Lock Screen accessories.
//
//  Adding a new widget? Add it to `body` below AND keep its `kind`
//  string stable for the lifetime of the binary — changing a kind
//  orphans every widget the user has already placed on their home /
//  lock screen.
//

import WidgetKit
import SwiftUI

@main
struct CashLensWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home Screen
        SpendingWidget()        // Free for everyone (the "hero" surface)
        BudgetWidget()          // Pro
        SubscriptionsWidget()   // Pro
        StreakWidget()          // Pro

        // Lock Screen
        SpendingLockWidget()    // Free
        StreakLockWidget()      // Pro (gated inside the entry view)
    }
}
