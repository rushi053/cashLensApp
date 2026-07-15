//
//  CashLensShortcuts.swift
//  CashLens (main app target)
//
//  App Shortcuts — zero-setup Siri phrases. Every phrase MUST contain
//  `\(.applicationName)` (a hard App Intents requirement; phrases
//  without the app name are ignored by Siri). Parameter interpolation
//  in phrases only works for AppEnum/AppEntity parameters, so the
//  amount (an IntentCurrencyAmount) can't appear in a phrase — Siri
//  asks for it as a follow-up instead.
//
import AppIntents

struct CashLensShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "Log spending in \(.applicationName)",
                "Record an expense in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: GetSpendingIntent(),
            phrases: [
                "How much did I spend today in \(.applicationName)",
                "How much have I spent in \(.applicationName)",
                "Check my spending in \(.applicationName)",
                "What's my spending in \(.applicationName)"
            ],
            shortTitle: "Check Spending",
            systemImageName: "chart.bar.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .purple
}
